import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../models/transfer_job.dart';
import '../utils/hash_isolate.dart';
import '../utils/path_safety.dart';
import 'lyra_channel.dart';
import 'lyra_crypto.dart';
import 'lyra_message.dart';

/// Sunucu tarafı politikası: PIN kontrolü ve teklif kararı.
class ServerPolicy {
  /// Geçerli PIN; `null` ise PIN istenmez.
  final String? Function() pin;

  /// Gelen teklif için kullanıcı kararı.
  final Future<AcceptDecision> Function(IncomingOffer offer, HelloInfo peer,
      {required bool pinVerified}) onOffer;

  /// El sıkışma sonrası ek kimlik kontrolü (ör. bilinen parmak izi ile
  /// karşılaştırma). Hata nedeni döndürürse bağlantı reddedilir.
  final Future<String?> Function(HelloInfo peer)? onHandshake;

  const ServerPolicy(
      {required this.pin, required this.onOffer, this.onHandshake});
}

/// Transfer sunucusu: gelen bağlantıları dinler ve dosyaları diske yazar.
class LyraTransferServer {
  final HelloInfo localInfo;
  final SimpleKeyPair keyPair;
  final int port;
  final String saveDir;
  final ServerPolicy policy;

  final void Function(TransferJob job)? onJobCreated;
  final void Function(TransferJob job)? onJobUpdated;
  final void Function(TransferJob job)? onJobFinished;

  ServerSocket? _server;

  /// Gerçek bağlı port — [port] 0 ise çekirdeğin atadığı geçici port.
  /// Testler ve dinamik port ayrılmaları yarışa karşı bunu kullanır.
  int get boundPort => _server?.port ?? port;
  final _connections = <LyraChannel>{};

  /// PIN deneme kilidi: adres → başarısız deneme zamanları.
  final _pinAttempts = <String, List<DateTime>>{};
  static const _maxPinAttempts = 5;
  static const _pinLockout = Duration(minutes: 5);

  /// Aynı anda kabul edilebilecek gelen transfer sayısı (meşgul kuralı).
  static const int maxConcurrentIncoming = 3;
  int _activeIncoming = 0;

  LyraTransferServer({
    required this.localInfo,
    required this.keyPair,
    required this.port,
    required this.saveDir,
    required this.policy,
    this.onJobCreated,
    this.onJobUpdated,
    this.onJobFinished,
  });

  Future<void> start() async {
    if (_server != null) return;
    final server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    _server = server;
    server.listen((socket) {
      final channel = LyraChannel(socket, isClient: false);
      _connections.add(channel);
      _session(channel).whenComplete(() {
        _connections.remove(channel);
        channel.close();
      });
    });
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    for (final c in _connections.toList()) {
      c.close();
    }
    _connections.clear();
  }

  Future<void> _session(LyraChannel channel) async {
    final queue = LyraEventQueue(channel.events);
    TransferJob? job;
    RandomAccessFile? raf;
    FileTransfer? currentFile;
    String? currentPartPath;
    var counted = false;

    try {
      final peer = await channel.handshake(localInfo, keyPair: keyPair);
      final remoteAddr = channel.socket.remoteAddress.address;

      // Ek kimlik kontrolü (ör. bilinen parmak iziyle karşılaştırma / TOFU).
      final handshakeError = await policy.onHandshake?.call(peer);
      if (handshakeError != null) {
        await channel
            .sendControlAndWait({'t': MsgType.error, 'reason': handshakeError});
        return;
      }

      // 1) Kimlik doğrulama
      var pinVerified = false;
      final expectedPin = policy.pin();
      IncomingOffer? offer;
      var done = false;

      while (!done) {
        final event = await queue.next();
        if (event == null) break;

        if (event.isData) {
          final data = event.bytes!;
          if (raf == null) continue;
          // O-19: beyan edilen boyutu aşan yazma reddedilir.
          final file = currentFile;
          if (file != null &&
              file.size > 0 &&
              file.done + data.length > file.size) {
            await channel.sendControlAndWait({
              't': MsgType.error,
              'reason': 'err.sizeMismatch',
            });
            job?.state = JobState.failed;
            job?.error = 'err.sizeMismatch';
            job?.finishedAt = DateTime.now();
            if (job != null) onJobFinished?.call(job);
            done = true;
            continue;
          }
          await raf.writeFrom(data);
          currentFile!.done += data.length;
          job!.transferred += data.length;
          onJobUpdated?.call(job);
          continue;
        }

        final type = event.type;
        final data = event.data;
        switch (type) {
          case MsgType.auth:
            if (_isLockedOut(remoteAddr)) {
              await channel.sendControlAndWait({
                't': MsgType.authResult,
                'ok': false,
                'reason': 'err.tooManyAttempts',
              });
              done = true;
              break;
            }
            final pinValue = data['pin'] as String? ?? '';
            pinVerified = expectedPin == null ||
                expectedPin.isEmpty ||
                LyraCryptoIdentity.constantTimeEquals(
                    pinValue, expectedPin);
            await channel.sendControlAndWait({
              't': MsgType.authResult,
              'ok': pinVerified,
              if (!pinVerified) 'reason': 'err.pinWrong',
            });
            if (!pinVerified) {
              _registerFailedAttempt(remoteAddr);
              done = true;
            }

          case MsgType.offer:
            // K-3: PIN tanımlıysa ve kimlik doğrulaması yapılmadıysa
            // teklif hiçbir koşulda kabul edilemez.
            if ((expectedPin != null && expectedPin.isNotEmpty) &&
                !pinVerified) {
              await channel.sendControlAndWait({
                't': MsgType.error,
                'reason': 'err.pinRequired',
              });
              done = true;
              break;
            }
            // Meşgul kuralı: eşzamanlı gelen transfer sınırı.
            if (_activeIncoming >= maxConcurrentIncoming) {
              await channel.sendControlAndWait({
                't': MsgType.reject,
                'reason': 'err.busy',
              });
              done = true;
              break;
            }
            offer = IncomingOffer.fromJson(data);
            job = TransferJob(
              id: offer.jobId.isEmpty ? _newId() : offer.jobId,
              direction: JobDirection.receive,
              peerId: peer.id,
              peerName: peer.name,
              peerAddress: channel.socket.remoteAddress.address,
              files: [
                for (final f in offer.files)
                  FileTransfer(
                    id: f.id,
                    name: f.name,
                    size: f.size,
                    relPath: f.targetPath,
                  ),
              ],
              text: offer.text,
              createdAt: DateTime.now(),
            );
            onJobCreated?.call(job);

            // Kullanıcı kararı beklenirken karşı tarafa "bekliyor" bildir.
            channel.sendControl({'t': MsgType.pending});
            final decision = await policy.onOffer(offer, peer,
                pinVerified: pinVerified);
            if (!decision.accepted) {
              await channel.sendControlAndWait({
                't': MsgType.reject,
                'reason': decision.reason ?? 'err.userRejected',
              });
              job.state = JobState.cancelled;
              job.error = decision.reason ?? 'err.userRejected';
              job.finishedAt = DateTime.now();
              onJobFinished?.call(job);
              done = true;
              break;
            }
            _activeIncoming++;
            counted = true;

            // Devam ettirme: yarım dosyaların boyutlarını bildir.
            // Çakışma yönetimi: hedef ad doluysa `ad (2).ext` üretilir ve
            // son ad istemciye bildirilir (Y-6).
            final resume = <String, int>{};
            final names = <String, String>{};
            for (final f in offer.files) {
              final partPath =
                  '${safeJoin(saveDir, f.targetPath)}${LyraTransferServer.partSuffix}';
              final part = File(partPath);
              if (await part.exists()) {
                final len = await part.length();
                if (len > 0 && len < f.size) {
                  resume[f.id] = len;
                }
                names[f.id] = f.targetPath;
                continue;
              }
              final resolved =
                  await _resolveCollision(saveDir, f.targetPath);
              names[f.id] = resolved;
              final ft = job.files.firstWhere((x) => x.id == f.id);
              ft.relPath = resolved;
            }
            channel.sendControl({
              't': MsgType.accept,
              'job': job.id,
              'resume': resume,
              'names': names,
            });
            job.state = JobState.transferring;
            onJobUpdated?.call(job);

            // O-18: metin mesajı kalıcı olarak diske kaydedilir.
            final text = offer.text;
            if (text != null && text.trim().isNotEmpty) {
              try {
                final stamp = DateTime.now()
                    .toIso8601String()
                    .replaceAll(':', '')
                    .split('.');
                final name = sanitizeFileName('mesaj-${stamp.first}.txt');
                final textPath = safeJoin(saveDir, name);
                await File(textPath).writeAsString(text);
                job.textSavedPath = textPath;
              } catch (_) {
                // Kaydetme başarısız olsa transfer sürer.
              }
            }

          case MsgType.fileStart:
            final fileId = data['file'] as String? ?? '';
            currentFile = job?.files.cast<FileTransfer?>().firstWhere(
                  (f) => f?.id == fileId,
                  orElse: () => null,
                );
            if (currentFile == null) break;
            final offset = (data['offset'] as num?)?.toInt() ?? 0;
            final path = safeJoin(saveDir, currentFile.relPath ?? currentFile.name);
            final partPath = '$path${LyraTransferServer.partSuffix}';
            currentPartPath = partPath;
            final part = File(partPath);
            await part.parent.create(recursive: true);
            raf = await part.open(
                mode: offset > 0 ? FileMode.append : FileMode.write);
            if (offset > 0) {
              currentFile.done = offset;
              job!.transferred += offset;
            }

          case MsgType.fileEnd:
            await raf?.flush();
            await raf?.close();
            raf = null;
            final file = currentFile;
            final activeJob = job;
            if (file != null && currentPartPath != null && activeJob != null) {
              final expected = data['sha256'] as String?;
              // Y-6: nihai ad; hedef o arada dolmuşsa çakışma adı.
              final finalPath =
                  safeJoin(saveDir, file.relPath ?? file.name);
              var target = finalPath;
              if (await File(target).exists()) {
                final resolved = await _resolveCollision(
                    saveDir, file.relPath ?? file.name);
                target = safeJoin(saveDir, resolved);
                file.relPath = resolved;
              }
              await File(currentPartPath).rename(target);
              file.savedPath = target;

              // Bütünlük doğrulaması: tam dosya üzerinden, arka planda
              // (Y-7 + O-17). Uyuşmazsa dosya yarım adıyla geri alınır.
              if (expected != null && expected.isNotEmpty) {
                final actual = await sha256OfFile(target);
                if (actual != expected) {
                  file.error = 'err.hashMismatch';
                  try {
                    await File(target).rename(currentPartPath);
                  } catch (_) {}
                  await channel.sendControlAndWait({
                    't': MsgType.error,
                    'reason': 'err.hashMismatch',
                  });
                  activeJob.state = JobState.failed;
                  activeJob.error = 'err.hashMismatch';
                  activeJob.finishedAt = DateTime.now();
                  onJobUpdated?.call(activeJob);
                  done = true;
                  break;
                }
              }
              file.completed = true;
              currentPartPath = null;
              onJobUpdated?.call(activeJob);
            }

          case MsgType.done:
            await raf?.close();
            raf = null;
            await channel.sendControlAndWait({'t': MsgType.done, 'job': job?.id});
            if (job != null) {
              job.state = JobState.completed;
              job.finishedAt = DateTime.now();
              onJobFinished?.call(job);
            }
            done = true;

          case MsgType.cancel:
            await raf?.close();
            raf = null;
            if (job != null) {
              job.state = JobState.cancelled;
              job.error = data['reason'] as String? ?? 'iptal edildi';
              job.finishedAt = DateTime.now();
              onJobFinished?.call(job);
            }
            done = true;

          case MsgType.ping:
            channel.sendControl({'t': MsgType.pong});

          default:
            break;
        }
      }
    } catch (e) {
      if (job != null && !job.isFinished) {
        job.state = JobState.failed;
        job.error = '$e';
        job.finishedAt = DateTime.now();
        onJobFinished?.call(job);
      }
    } finally {
      if (counted && _activeIncoming > 0) _activeIncoming--;
      await raf?.close();
      queue.dispose();
    }
  }

  static const String partSuffix = '.lyrapart';

  /// Hedef yol doluysa `ad (2).ext` biçiminde çakışmasız göreli yol üretir.
  static Future<String> _resolveCollision(
      String saveDir, String relPath) async {
    final base = safeJoin(saveDir, relPath);
    if (!await File(base).exists() &&
        !await File('$base$partSuffix').exists()) {
      return relPath;
    }
    final slash = relPath.replaceAll(r'\', '/').lastIndexOf('/');
    final dir = slash >= 0 ? relPath.substring(0, slash + 1) : '';
    final name = slash >= 0 ? relPath.substring(slash + 1) : relPath;
    final unique = uniqueName(name, (candidate) {
      final p = safeJoin(saveDir, '$dir$candidate');
      return File(p).existsSync() || File('$p$partSuffix').existsSync();
    });
    return '$dir$unique';
  }

  /// Başarısız PIN denemesi kaydeder.
  void _registerFailedAttempt(String address) {
    final list = _pinAttempts.putIfAbsent(address, () => <DateTime>[])
      ..add(DateTime.now());
    list.removeWhere(
        (t) => DateTime.now().difference(t) > _pinLockout);
    if (list.length > _maxPinAttempts) {
      // Kilit süresi boyunca listeyi uzat; _isLockedOut süreyi yönetir.
      list.add(DateTime.now());
    }
  }

  /// Adres kilitli mi? (son başarısız denemeden bu yana süre geçmediyse)
  bool _isLockedOut(String address) {
    final list = _pinAttempts[address];
    if (list == null || list.length < _maxPinAttempts) return false;
    final last = list.last;
    return DateTime.now().difference(last) < _pinLockout;
  }

  static String _newId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
