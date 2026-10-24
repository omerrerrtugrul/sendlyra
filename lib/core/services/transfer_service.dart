import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/device.dart';
import '../models/transfer_job.dart';
import '../protocol/lyra_message.dart';
import '../protocol/transfer_client.dart';
import '../protocol/transfer_server.dart';
import '../utils/multicast_lock.dart';
import 'discovery_service.dart';
import 'history_service.dart';
import 'identity_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';

/// E-04: kuyrukta bekleyen bir gönderim.
class _QueuedSend {
  _QueuedSend(this.job, this.target, this.files, this.relPaths, this.text,
      this.pin);

  final TransferJob job;
  final LyraDevice target;
  final List<File> files;
  final List<String> relPaths;
  final String? text;
  final String? pin;
}

/// Gelen bir teklifin UI'a bildirilmesi için bekleyen istek.
class IncomingRequest {
  final IncomingOffer offer;
  final HelloInfo peer;
  final bool pinVerified;
  final Completer<AcceptDecision> decision = Completer<AcceptDecision>();

  IncomingRequest({
    required this.offer,
    required this.peer,
    required this.pinVerified,
  });

  void accept({Map<String, int> resumeOffsets = const {}}) {
    if (!decision.isCompleted) {
      decision.complete(AcceptDecision.accept(resumeOffsets));
    }
  }

  void reject([String reason = 'err.userRejected']) {
    if (!decision.isCompleted) {
      decision.complete(AcceptDecision.reject(reason));
    }
  }
}

/// Keşif + transfer + geçmiş için üst düzey orkestratör.
class TransferService extends ChangeNotifier {
  final IdentityService identity;
  final SettingsService settings;
  final HistoryService history;

  DiscoveryService? _discovery;
  LyraTransferServer? _server;
  bool _started = false;

  /// Y-9: ilerleme bildirimleri 300 ms'de bir tazelenir; her veri
  /// karesinde tam yeniden çizim tetiklenmez.
  Timer? _notifyTimer;
  bool _notifyPending = false;

  /// Y-8: canlı ayar uygulaması için son bilinen değerler.
  int? _lastPort;
  String? _lastSaveDir;
  bool? _lastDiscoveryOn;
  Timer? _settingsDebounce;

  final List<TransferJob> jobs = [];
  final _incomingController = StreamController<IncomingRequest>.broadcast();

  /// E-03: transfer sonucu bildirimleri (null ise bildirim yok).
  final TransferNotifier? notifier;

  /// E-04: meşgul hedefler için bekleyen gönderimler.
  final List<_QueuedSend> _queue = [];
  Timer? _queueTimer;
  StreamSubscription<void>? _discoverySub;

  TransferService({
    required this.identity,
    required this.settings,
    required this.history,
    this.notifier,
  });

  /// E-04: kuyrukta bekleyen iş sayısı (testler için).
  @visibleForTesting
  int get queueLength => _queue.length;

  /// UI'ın dinlemesi gereken gelen teklif akışı.
  Stream<IncomingRequest> get incomingRequests => _incomingController.stream;

  List<LyraDevice> get devices {
    final values = _discovery?.devices.values ?? const <LyraDevice>[];
    final list = values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<TransferJob> get activeJobs =>
      jobs.where((j) => !j.isFinished).toList();
  List<TransferJob> get finishedJobs =>
      jobs.where((j) => j.isFinished).toList();

  Future<void> start() async {
    if (_started) return;
    _started = true;
    // E-03: bildirim altyapısı; başarısız olsa bile uygulama çalışır.
    try {
      await notifier?.init();
    } catch (_) {
      // Bildirim yoksa transferler sessizce sürer.
    }
    // R-2 (savunma): PIN güvenli kasadan yüklenmeden istek kabul edilmesin.
    await settings.loadSecrets();
    settings.removeListener(_onSettingsChanged);
    settings.addListener(_onSettingsChanged);

    _discovery = DiscoveryService(
      identity: () => BeaconIdentity(
        id: identity.deviceId,
        name: identity.alias,
        os: identity.os,
        deviceType: identity.deviceType,
        port: settings.transferPort,
        publicKeyBase64: identity.publicKeyBase64,
        fingerprint: identity.fingerprint,
        busy: activeJobs.isNotEmpty,
      ),
    );
    // E-04: cihaz meşguliyeti değişince kuyruk yeniden denenir.
    await _discoverySub?.cancel();
    _discoverySub = _discovery?.changes.listen((_) {
      unawaited(pumpQueue());
    });
    if (settings.discoveryOn) {
      await MulticastLock.acquire();
      await _discovery?.start();
    }
    _lastDiscoveryOn = settings.discoveryOn;

    await _startServer();
  }

  Future<void> _startServer() async {
    final saveDir = await resolveSaveDir();
    final server = LyraTransferServer(
      localInfo: identity.hello(settings.transferPort),
      keyPair: identity.keyPair,
      port: settings.transferPort,
      saveDir: saveDir,
      policy: ServerPolicy(
        pin: () => settings.pin,
        onHandshake: _verifyPeer,
        onOffer: (offer, peer, {required pinVerified}) async {
          final request = IncomingRequest(
            offer: offer,
            peer: peer,
            pinVerified: pinVerified,
          );
          // Hızlı kaydetme kipleri: kullanıcı onayı olmadan kabul.
          // Karar her zaman doğrulanmış parmak izi üzerinden verilir.
          if (pinVerified && settings.autoAcceptFrom(peer.fingerprint)) {
            request.accept();
            return request.decision.future;
          }
          if (settings.isTrusted(peer.fingerprint) && pinVerified) {
            request.accept();
            return request.decision.future;
          }
          _incomingController.add(request);
          return request.decision.future.timeout(
            const Duration(seconds: 120),
            onTimeout: () => const AcceptDecision.reject('err.timeout'),
          );
        },
      ),
      onJobCreated: _onJobCreated,
      onJobUpdated: _onJobUpdated,
      onJobFinished: _onJobFinished,
    );
    await server.start();
    _server = server;
    _lastPort = settings.transferPort;
    _lastSaveDir = saveDir;
  }

  /// El sıkışma sonrası ek kimlik kontrolü (TOFU).
  ///
  /// Parmak izi kanal katmanında `sha256(pk)` ile birebir doğrulanır;
  /// burada da ilk karşılaşımda kaydedilen iz ile karşılaştırılır.
  /// Değişmişse bağlantı reddedilir (taklit / MITM uyarısı).
  Future<String?> _verifyPeer(HelloInfo peer) async {
    if (settings.fingerprintChanged(peer.id, peer.fingerprint)) {
      return 'err.fingerprintChanged';
    }
    await settings.rememberPeer(peer.id, peer.fingerprint);
    return null;
  }

  /// Varsayılan indirme klasörünü çözer; ayarlardaki değer önceliklidir.
  Future<String> resolveSaveDir() async {
    if (settings.saveDir.isNotEmpty) return settings.saveDir;
    Directory base;
    try {
      base = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      base = Directory.systemTemp;
    }
    final dir = Directory('${base.path}/SendLyra');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  void _onJobCreated(TransferJob job) {
    jobs.insert(0, job);
    _sampleSpeed(job);
    _pruneJobs();
    notifyListeners();
  }

  /// D-24: biten işler bellekte tutulur ama budanır (en fazla 50).
  void _pruneJobs() {
    const maxFinished = 50;
    final finished = jobs.where((j) => j.isFinished).toList();
    if (finished.length > maxFinished) {
      for (final job in finished.sublist(maxFinished)) {
        jobs.remove(job);
      }
    }
  }

  void _onJobUpdated(TransferJob job) {
    _sampleSpeed(job);
    _scheduleNotify();
  }

  /// Y-9: bildirimleri en fazla 300 ms'de bir tazeler.
  void _scheduleNotify() {
    if (_notifyTimer != null) {
      _notifyPending = true;
      return;
    }
    notifyListeners();
    _notifyTimer = Timer(const Duration(milliseconds: 300), () {
      _notifyTimer = null;
      if (_notifyPending) {
        _notifyPending = false;
        _scheduleNotify();
      }
    });
  }

  /// Y-8: ayar değişiklikleri servislere otomatik uygulanır.
  void _onSettingsChanged() {
    _settingsDebounce?.cancel();
    _settingsDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!_started) return;
      final portChanged = _lastPort != settings.transferPort;
      final dirChanged = _lastSaveDir != settings.saveDir;
      if (portChanged || dirChanged) {
        _lastPort = settings.transferPort;
        _lastSaveDir = settings.saveDir;
        await _server?.stop();
        await _startServer();
      }
      final discoveryChanged = _lastDiscoveryOn != settings.discoveryOn;
      if (discoveryChanged) {
        _lastDiscoveryOn = settings.discoveryOn;
        if (settings.discoveryOn) {
          await MulticastLock.acquire();
          await _discovery?.start();
        } else {
          await _discovery?.stop();
          await MulticastLock.release();
        }
      }
      notifyListeners();
    });
  }

  /// Hız tahmini: 500 ms'lik pencerede üstel yumuşatma.
  void _sampleSpeed(TransferJob job) {
    final now = DateTime.now();
    final last = job.lastSampleAt;
    if (last == null) {
      job.lastSampleAt = now;
      job.lastSampleBytes = job.transferred;
      return;
    }
    final dt = now.difference(last).inMilliseconds;
    if (dt < 500) return;
    final delta = job.transferred - job.lastSampleBytes;
    final instant = delta * 1000 / dt;
    job.speedBps =
        job.speedBps <= 0 ? instant : job.speedBps * 0.7 + instant * 0.3;
    job.lastSampleAt = now;
    job.lastSampleBytes = job.transferred;
  }

  void _onJobFinished(TransferJob job) {
    unawaited(history.add(job));
    _notifyFinished(job);
    notifyListeners();
  }

  /// E-03: bildirim hatası asla transferi etkilemez.
  void _notifyFinished(TransferJob job) {
    try {
      notifier?.notifyJobFinished(job);
    } catch (_) {
      // Yoksayılır.
    }
  }

  /// Seçilen dosyaları hedef cihaza gönderir.
  ///
  /// [relPaths] klasör yapısını korur; her dosya için göreli yol içerir.
  /// Hedef meşgulse iş (E-04) kuyruğa alınır ve cihaz uygun olunca
  /// otomatik olarak gönderilir.
  Future<TransferJob> send({
    required LyraDevice target,
    required List<File> files,
    List<String> relPaths = const [],
    String? text,
    String? pin,
  }) async {
    final job = TransferJob(
      id: _newJobId(),
      direction: JobDirection.send,
      peerId: target.id,
      peerName: target.name,
      peerAddress: target.address,
      files: [
        for (var i = 0; i < files.length; i++)
          FileTransfer(
            id: 'f$i',
            name: _baseName(files[i].path),
            size: _fileLength(files[i]),
            relPath: i < relPaths.length ? relPaths[i] : null,
          ),
      ],
      text: text,
      createdAt: DateTime.now(),
    );
    jobs.insert(0, job);

    final queued = _QueuedSend(job, target, files, relPaths, text, pin);
    if (target.busy) {
      // E-04: meşgul cihaza gönderim doğrudan denenmez, kuyruğa düşer.
      job.state = JobState.queued;
      _queue.add(queued);
      _scheduleQueuePump();
      notifyListeners();
      return job;
    }

    notifyListeners();
    await _runSend(queued);
    return job;
  }

  /// Kuyruktan gelen ya da yeni bir gönderimi gerçekten çalıştırır.
  Future<void> _runSend(_QueuedSend s) async {
    final job = s.job;
    final client = LyraTransferClient(
      localInfo: identity.hello(settings.transferPort),
      keyPair: identity.keyPair,
    );

    try {
      await client.send(
        target: s.target,
        job: job,
        files: s.files,
        relPaths: s.relPaths,
        text: s.text,
        pin: s.pin,
        onChanged: () => _onJobUpdated(job),
        onHandshake: _verifyPeer,
      );
    } catch (_) {
      // Durum job nesnesine işlendi.
    }

    // E-04: alıcı "meşgul" dediyse iş kuyruğa geri alınır.
    if (job.error == 'err.busy') {
      _requeue(s);
      return;
    }
    unawaited(history.add(job));
    _notifyFinished(job);
    notifyListeners();
  }

  /// E-04: işi kuyruğa geri alır (cihaz uygun olunca yeniden denenir).
  void _requeue(_QueuedSend s) {
    s.job.state = JobState.queued;
    s.job.error = null;
    s.job.finishedAt = null;
    _queue.add(s);
    _scheduleQueuePump();
    notifyListeners();
  }

  /// E-04: kuyruk doluysa periyodik deneme zamanlayıcısını açar.
  void _scheduleQueuePump() {
    _queueTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => pumpQueue(),
    );
  }

  /// E-04: kuyruktaki işleri dener.
  ///
  /// Cihaz durumu keşiften okunur; bilinmeyen cihaz "meşgul değil"
  /// sayılır ve bağlantı denenir (başarısızsa iş hata ile biter).
  Future<void> pumpQueue() async {
    if (_queue.isEmpty) {
      _queueTimer?.cancel();
      _queueTimer = null;
      return;
    }
    final ready = <_QueuedSend>[
      for (final s in _queue)
        if (!_isPeerBusy(s.target.id)) s,
    ];
    for (final s in ready) {
      _queue.remove(s);
    }
    await Future.wait([for (final s in ready) _runSend(s)]);
    if (_queue.isEmpty) {
      _queueTimer?.cancel();
      _queueTimer = null;
    }
  }

  bool _isPeerBusy(String peerId) {
    final device = _discovery?.devices[peerId];
    return device?.busy ?? false;
  }

  /// Aktif bir işi iptal eder (yerel taraf).
  void cancelJob(TransferJob job) {
    if (job.isFinished) return;
    // E-04: kuyruktaki iş de iptal edilebilir.
    _queue.removeWhere((s) => s.job == job);
    job.state = JobState.cancelled;
    job.error = 'err.localCancel';
    job.finishedAt = DateTime.now();
    unawaited(history.add(job));
    notifyListeners();
  }

  static String _baseName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }

  static int _fileLength(File f) {
    try {
      return f.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  static String _newJobId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        (DateTime.now().millisecond % 1000).toRadixString(36);
  }

  Future<void> restartServices() async {
    await _server?.stop();
    await _discovery?.stop();
    _discovery = null;
    _started = false;
    await start();
    notifyListeners();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _settingsDebounce?.cancel();
    _notifyTimer?.cancel();
    _queueTimer?.cancel();
    _discoverySub?.cancel();
    _server?.stop();
    _discovery?.dispose();
    _incomingController.close();
    MulticastLock.release();
    super.dispose();
  }
}
