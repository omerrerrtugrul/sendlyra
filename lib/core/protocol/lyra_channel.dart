import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'lyra_crypto.dart';
import 'lyra_message.dart';
import 'lyra_protocol.dart';

/// Bir LyraLink bağlantısının uçtan uca şifreli kanalı.
///
/// Akış şeması:
///  1. Açık metin NL-JSON "hello" el sıkışması
///  2. X25519 + HKDF ile oturum anahtarlarının türetilmesi
///  3. Şifreli kareler: `[4 bayt uzunluk][şifreli veri]`
///     - Düz metin: `[0x00][JSON utf8]`  → kontrol mesajı
///     - Düz metin: `[0x01][ham bayt]`   → dosya verisi
class LyraChannel {
  final Socket socket;
  final bool isClient;

  LyraCipher? _sendCipher;
  LyraCipher? _recvCipher;
  final _events = StreamController<LyraEvent>.broadcast();
  final _done = Completer<void>();

  bool _encrypted = false;
  bool _pumping = false;
  bool _closed = false;
  Future<void> _sendChain = Future<void>.value();

  /// Birikmiş ham baytlar — parça kuyruğu ile O(n²) kopyalama engellenir (O-15).
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  HelloInfo? peerInfo;

  LyraChannel(this.socket, {required this.isClient}) {
    socket.listen(
      feed,
      onError: (Object e) => fail(LyraProtocolException('socket hatası: $e')),
      onDone: () {
        if (!_closed) close();
      },
      cancelOnError: true,
    );
  }

  Stream<LyraEvent> get events => _events.stream;
  Future<void> get done => _done.future;
  bool get isEncrypted => _encrypted;
  bool get isClosed => _closed;

  /// El sıkışmayı başlatır; karşı tarafın Hello bilgisini döndürür.
  Future<HelloInfo> handshake(
    HelloInfo local, {
    required SimpleKeyPair keyPair,
    Duration timeout = LyraProtocol.handshakeTimeout,
  }) async {
    final ready = Completer<HelloInfo>();
    final sub = events.listen((event) {
      if (event.type == 'hello' && !ready.isCompleted) {
        try {
          ready.complete(HelloInfo.fromJson(event.data));
        } catch (e) {
          ready.completeError(e);
        }
      }
    });

    try {
      // Açık metin hello — henüz şifreleme yok.
      socket.add(utf8.encode('${jsonEncode(local.toJson())}\n'));
      final peer = await ready.future.timeout(timeout, onTimeout: () {
        throw const LyraProtocolException('hello zaman aşımı');
      });

      // K-1: parmak izi, açık anahtarın tam SHA-256 özetiyle birebir
      // doğrulanır. Beyan edilen `fp` ile gerçek anahtar uyuşmazsa
      // bağlantı (aktif MITM girişimi dahil) reddedilir.
      final expectedFp = await LyraCryptoIdentity.fingerprintOf(peer.publicKey);
      if (peer.fingerprint != expectedFp) {
        throw const LyraProtocolException(
            'parmak izi doğrulaması başarısız: beyan edilen iz anahtarla uyuşmuyor');
      }

      final keys = await deriveSessionKeys(
        myKeyPair: keyPair,
        theirPublicKey: peer.publicKey,
        isClient: isClient,
      );
      _sendCipher = LyraCipher(keys.sendKey);
      _recvCipher = LyraCipher(keys.recvKey);
      _encrypted = true;
      peerInfo = peer;
      return peer;
    } finally {
      await sub.cancel();
    }
  }

  /// Gelen ham baytları besler (socket dinleyicisinden çağrılır).
  void feed(List<int> chunk) {
    if (_closed) return;
    _buffer.add(chunk);
    _schedulePump();
  }

  void _schedulePump() {
    if (_pumping || _closed) return;
    _pumping = true;
    _pump().whenComplete(() {
      _pumping = false;
      if (_buffer.length > 0 && !_closed) _schedulePump();
    });
  }

  Future<void> _pump() async {
    // Biriken tüm baytlar tek seferde alınır; işlenemeyen kuyruk
    // (tamamlanmamış satır/kare) geri eklenir — yalnızca kuyruk kopyalanır.
    final buf = _buffer.takeBytes();
    var offset = 0;
    while (!_closed) {
      if (!_encrypted) {
        final idx = buf.indexOf(0x0A, offset);
        if (idx < 0) break;
        final line = utf8.decode(buf.sublist(offset, idx));
        offset = idx + 1;
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line);
          if (json is Map<String, dynamic>) {
            _events.add(LyraEvent.control(json['t'] as String?, json));
          }
        } catch (_) {
          // Bozuk satır yutulur; üst katman gerekirse zaman aşımıyla kopar.
        }
        continue;
      }

      if (buf.length - offset < 4) break;
      final len = ByteData.sublistView(
        Uint8List.fromList(buf.sublist(offset, offset + 4)),
      ).getUint32(0);
      if (len == 0 || len > LyraProtocol.maxFrameSize) {
        fail(const LyraProtocolException('kare boyutu sınırı aşıldı'));
        return;
      }
      if (buf.length - offset - 4 < len) break;
      final frame = buf.sublist(offset + 4, offset + 4 + len);
      offset += 4 + len;

      try {
        final plain = await _recvCipher!.open(frame);
        if (plain.isEmpty) continue;
        if (plain[0] == 0x00) {
          final json = jsonDecode(utf8.decode(plain.sublist(1)));
          if (json is Map<String, dynamic>) {
            _events.add(LyraEvent.control(json['t'] as String?, json));
          }
        } else if (plain[0] == 0x01) {
          _events.add(LyraEvent.data(plain.sublist(1)));
        } else {
          // D-23: bilinmeyen düz metin tipi sessizce yutulmaz.
          fail(const LyraProtocolException(
              'bilinmeyen kare tipi — bağlantı kapatılıyor'));
          return;
        }
      } catch (e) {
        fail(e is LyraProtocolException
            ? e
            : LyraProtocolException('kare çözülemedi: $e'));
        return;
      }
    }
    if (offset < buf.length && !_closed) {
      _buffer.add(buf.sublist(offset));
    }
  }

  /// Kontrol mesajı gönderir (şifreli, sıralı).
  void sendControl(Map<String, dynamic> json) {
    _enqueueSend(<int>[0x00, ...utf8.encode(jsonEncode(json))]);
  }

  /// Ham veri karesi gönderir (şifreli, sıralı).
  void sendData(List<int> bytes) {
    _enqueueSend(<int>[0x01, ...bytes]);
  }

  /// Kontrol mesajı gönderir ve teline yazılmasını bekler.
  Future<void> sendControlAndWait(Map<String, dynamic> json) {
    _enqueueSend(<int>[0x00, ...utf8.encode(jsonEncode(json))]);
    return _sendChain;
  }

  void _enqueueSend(List<int> plaintext) {
    final cipher = _sendCipher;
    if (cipher == null) {
      fail(const LyraProtocolException('kanal henüz şifreli değil'));
      return;
    }
    // Gönderimler sıralı: hem nonce sayacı hem tel sırası korunur.
    _sendChain = _sendChain.then((_) async {
      if (_closed) return;
      final sealed = await cipher.seal(plaintext);
      final header = ByteData(4)..setUint32(0, sealed.length);
      socket.add(header.buffer.asUint8List());
      socket.add(sealed);
    }).catchError((Object e) {
      fail(e is LyraProtocolException ? e : LyraProtocolException('$e'));
    });
  }

  /// Kanalı hata ile kapatır.
  void fail(Object error) {
    if (!_events.isClosed) {
      _events.addError(error);
    }
    close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (!_events.isClosed) {
      _events.close();
    }
    if (!_done.isCompleted) {
      _done.complete();
    }
    socket.destroy();
  }
}

/// Olayları sırayla tüketen, arabellekli kuyruk.
///
/// Broadcast akışta dinleyici yokken kaybolan olayları engeller ve yavaş
/// disk yazımında geri basınç (backpressure) uygular.
class LyraEventQueue {
  static const int _highWater = 48; // ~3 MB arabellek

  final ListQueue<LyraEvent> _queue = ListQueue<LyraEvent>();
  final ListQueue<Completer<LyraEvent?>> _waiters = ListQueue<Completer<LyraEvent?>>();
  StreamSubscription<LyraEvent>? _sub;
  Object? _error;
  bool _closed = false;
  bool _paused = false;

  LyraEventQueue(Stream<LyraEvent> source) {
    _sub = source.listen(
      _onEvent,
      onError: (Object e) {
        _error = e;
        _closed = true;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
    );
  }

  void _onEvent(LyraEvent event) {
    _queue.addLast(event);
    if (!_paused && _queue.length >= _highWater) {
      _paused = true;
      _sub?.pause();
    }
    _wake();
  }

  void _wake() {
    while (_waiters.isNotEmpty && (_queue.isNotEmpty || _closed)) {
      final waiter = _waiters.removeFirst();
      if (_queue.isNotEmpty) {
        waiter.complete(_queue.removeFirst());
      } else if (_error != null) {
        waiter.completeError(_error!);
      } else {
        waiter.complete(null);
      }
    }
    if (_paused && _queue.length < _highWater ~/ 2) {
      _paused = false;
      _sub?.resume();
    }
  }

  /// Sıradaki olayı bekler; akış kapandıysa `null` döner (hatada fırlatır).
  Future<LyraEvent?> next() {
    if (_queue.isNotEmpty) {
      final event = _queue.removeFirst();
      if (_paused && _queue.length < _highWater ~/ 2) {
        _paused = false;
        _sub?.resume();
      }
      return Future<LyraEvent?>.value(event);
    }
    if (_closed) {
      if (_error != null) return Future<LyraEvent?>.error(_error!);
      return Future<LyraEvent?>.value(null);
    }
    final completer = Completer<LyraEvent?>();
    _waiters.addLast(completer);
    return completer.future;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

/// Kontrol mesajlarını tiplerine göre bekleyen yönlendirici.
///
/// Henüz bekleyen olmayan mesajları küçük bir arabellekte tutar; böylece
/// yanıt, bekleme kaydından önce gelse bile kaybolmaz.
class ControlRouter {
  final LyraEventQueue queue;
  final Map<String, List<Completer<Map<String, dynamic>>>> _waiters = {};
  final Map<String, List<Map<String, dynamic>>> _buffer = {};
  final void Function(String type, Map<String, dynamic> data)? onUnhandled;

  ControlRouter(this.queue, {this.onUnhandled}) {
    _loop();
  }

  Future<void> _loop() async {
    try {
      while (true) {
        final event = await queue.next();
        if (event == null) break;
        if (event.isData) continue;
        final type = event.type;
        if (type == null) continue;
        final waiters = _waiters.remove(type);
        if (waiters != null && waiters.isNotEmpty) {
          for (final waiter in waiters) {
            if (!waiter.isCompleted) waiter.complete(event.data);
          }
        } else {
          final buf = _buffer.putIfAbsent(type, () => []);
          buf.add(event.data);
          if (buf.length > 8) buf.removeAt(0);
          onUnhandled?.call(type, event.data);
        }
      }
    } catch (_) {
      // Bağlantı kapandı; bekleyenler zaman aşımıyla sonlanır.
    }
  }

  Future<Map<String, dynamic>> waitFor(
    String type, {
    Duration timeout = LyraProtocol.approvalTimeout,
  }) {
    final buf = _buffer[type];
    if (buf != null && buf.isNotEmpty) {
      return Future.value(buf.removeAt(0));
    }
    final completer = Completer<Map<String, dynamic>>();
    _waiters.putIfAbsent(type, () => []).add(completer);
    return completer.future.timeout(timeout, onTimeout: () {
      _remove(completer);
      throw LyraProtocolException('$type yanıtı zaman aşımına uğradı');
    });
  }

  Future<Map<String, dynamic>> waitForAny(
    List<String> types, {
    Duration timeout = LyraProtocol.approvalTimeout,
  }) {
    for (final type in types) {
      final buf = _buffer[type];
      if (buf != null && buf.isNotEmpty) {
        return Future.value(buf.removeAt(0));
      }
    }
    final completer = Completer<Map<String, dynamic>>();
    for (final type in types) {
      _waiters.putIfAbsent(type, () => []).add(completer);
    }
    return completer.future.timeout(timeout, onTimeout: () {
      _remove(completer);
      throw const LyraProtocolException('karar yanıtı zaman aşımına uğradı');
    }).whenComplete(() => _remove(completer));
  }

  void _remove(Completer<Map<String, dynamic>> completer) {
    for (final list in _waiters.values) {
      list.remove(completer);
    }
  }

  void dispose() {
    _waiters.clear();
    _buffer.clear();
    queue.dispose();
  }
}
