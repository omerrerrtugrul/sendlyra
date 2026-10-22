import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../models/transfer_job.dart';
import '../utils/path_safety.dart';
import 'lyra_channel.dart';
import 'lyra_message.dart';

/// Sunucu tarafı politikası: PIN kontrolü ve teklif kararı.
class ServerPolicy {
  /// Geçerli PIN; `null` ise PIN istenmez.
  final String? Function() pin;

  /// Gelen teklif için kullanıcı kararı.
  final Future<AcceptDecision> Function(IncomingOffer offer, HelloInfo peer,
      {required bool pinVerified}) onOffer;

  const ServerPolicy({required this.pin, required this.onOffer});
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
  final _connections = <LyraChannel>{};

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
    final sink = _DigestSink();
    ByteConversionSink? hasher;

    try {
      final peer = await channel.handshake(localInfo, keyPair: keyPair);

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
          await raf.writeFrom(data);
          currentFile!.done += data.length;
          job!.transferred += data.length;
          hasher?.add(data);
          onJobUpdated?.call(job);
          continue;
        }

        final type = event.type;
        final data = event.data;
        switch (type) {
          case MsgType.auth:
            final pinValue = data['pin'] as String? ?? '';
            pinVerified = expectedPin == null ||
                expectedPin.isEmpty ||
                pinValue == expectedPin;
            channel.sendControl({
              't': MsgType.authResult,
              'ok': pinVerified,
              if (!pinVerified) 'reason': 'PIN hatalı',
            });
            if (!pinVerified) {
              done = true;
            }

          case MsgType.offer:
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

            final decision = await policy.onOffer(offer, peer,
                pinVerified: pinVerified);
            if (!decision.accepted) {
              channel.sendControl({
                't': MsgType.reject,
                'reason': decision.reason ?? 'reddedildi',
              });
              job.state = JobState.cancelled;
              job.error = decision.reason ?? 'reddedildi';
              job.finishedAt = DateTime.now();
              onJobFinished?.call(job);
              done = true;
              break;
            }

            // Devam ettirme: yarım dosyaların boyutlarını bildir.
            final resume = <String, int>{};
            for (final f in offer.files) {
              final partPath =
                  '${safeJoin(saveDir, f.targetPath)}${LyraTransferServer.partSuffix}';
              final part = File(partPath);
              if (await part.exists()) {
                final len = await part.length();
                if (len > 0 && len < f.size) {
                  resume[f.id] = len;
                }
              }
            }
            channel.sendControl({
              't': MsgType.accept,
              'job': job.id,
              'resume': resume,
            });
            job.state = JobState.transferring;
            onJobUpdated?.call(job);

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
            hasher = sha256.startChunkedConversion(sink);

          case MsgType.fileEnd:
            await raf?.flush();
            await raf?.close();
            raf = null;
            final file = currentFile;
            final activeJob = job;
            if (file != null && currentPartPath != null && activeJob != null) {
              final expected = data['sha256'] as String?;
              hasher?.close();
              hasher = null;
              if (expected != null &&
                  sink.value.isNotEmpty &&
                  sink.value != expected) {
                file.error = 'sha256 uyuşmuyor';
                channel.sendControl({
                  't': MsgType.error,
                  'reason': 'sha256 uyuşmuyor',
                });
                activeJob.state = JobState.failed;
                activeJob.error = 'sha256 uyuşmuyor';
                activeJob.finishedAt = DateTime.now();
                onJobUpdated?.call(activeJob);
                done = true;
                break;
              }
              final finalPath =
                  safeJoin(saveDir, file.relPath ?? file.name);
              await File(currentPartPath).rename(finalPath);
              file.savedPath = finalPath;
              file.completed = true;
              currentPartPath = null;
              onJobUpdated?.call(activeJob);
            }

          case MsgType.done:
            await raf?.close();
            raf = null;
            channel.sendControl({'t': MsgType.done, 'job': job?.id});
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
      await raf?.close();
      queue.dispose();
    }
  }

  static const String partSuffix = '.lyrapart';

  static String _newId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

/// SHA-256 sonuç sink'i.
class _DigestSink implements Sink<Digest> {
  String value = '';

  @override
  void add(Digest data) {
    value = data.toString();
  }

  @override
  void close() {}
}
