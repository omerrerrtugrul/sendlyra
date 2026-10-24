import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../models/device.dart';
import '../models/transfer_job.dart';
import '../utils/hash_isolate.dart';
import 'lyra_channel.dart';
import 'lyra_message.dart';
import 'lyra_protocol.dart';

/// Gönderim istemcisi: bir hedef cihaza dosya/metin yollar.
class LyraTransferClient {
  final HelloInfo localInfo;
  final SimpleKeyPair keyPair;

  LyraTransferClient({required this.localInfo, required this.keyPair});

  Future<void> send({
    required LyraDevice target,
    required TransferJob job,
    List<File> files = const [],
    List<String> relPaths = const [],
    String? text,
    String? pin,
    void Function()? onChanged,
    Future<String?> Function(HelloInfo peer)? onHandshake,
  }) async {
    final socket = await Socket.connect(
      target.address,
      target.port,
      timeout: LyraProtocol.handshakeTimeout,
    );
    final channel = LyraChannel(socket, isClient: true);
    final queue = LyraEventQueue(channel.events);
    var aborted = false;
    final abortSignal = Completer<void>();

    final router = ControlRouter(queue, onUnhandled: (type, data) {
      if (type == MsgType.cancel) {
        aborted = true;
        if (!abortSignal.isCompleted) abortSignal.complete();
        if (!job.isFinished) {
          job.state = JobState.cancelled;
          job.error = data['reason'] as String? ?? 'err.peerCancelled';
          job.finishedAt = DateTime.now();
          onChanged?.call();
        }
      } else if (type == MsgType.error) {
        aborted = true;
        if (!abortSignal.isCompleted) abortSignal.complete();
        if (!job.isFinished) {
          job.state = JobState.failed;
          job.error = data['reason'] as String? ?? 'err.peerError';
          job.finishedAt = DateTime.now();
          onChanged?.call();
        }
      }
    });

    try {
      final peer = await channel.handshake(localInfo, keyPair: keyPair);
      // Ek kimlik kontrolü (TOFU / bilinen parmak izi karşılaştırması).
      final handshakeError = await onHandshake?.call(peer);
      if (handshakeError != null) {
        throw LyraProtocolException(handshakeError);
      }

      // 1) Kimlik doğrulama (PIN)
      final authWait = router.waitFor(MsgType.authResult,
          timeout: LyraProtocol.handshakeTimeout);
      channel.sendControl({'t': MsgType.auth, 'pin': pin ?? ''});
      final auth = await authWait;
      if (auth['ok'] != true) {
        throw LyraProtocolException(
            auth['reason'] as String? ?? 'err.pinWrong');
      }

      // 2) Teklif
      final offerFiles = <Map<String, dynamic>>[];
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final rel = i < relPaths.length ? relPaths[i] : null;
        offerFiles.add({
          'id': 'f$i',
          'name': _baseName(f.path),
          if (rel != null && rel.isNotEmpty) 'rel': rel,
          'size': await f.length(),
          'mime': _guessMime(f.path),
        });
      }
      channel.sendControl({
        't': MsgType.offer,
        'job': job.id,
        'files': offerFiles,
        if (text != null) 'text': text,
      });

      job.state = JobState.waitingApproval;
      onChanged?.call();

      // 3) Karar: accept / reject / pending → accept|reject
      var decision = await router.waitForAny(
        const [MsgType.accept, MsgType.reject, MsgType.pending],
        timeout: LyraProtocol.approvalTimeout,
      );
      if (decision['t'] == MsgType.pending) {
        decision = await router.waitForAny(
          const [MsgType.accept, MsgType.reject],
          timeout: LyraProtocol.approvalTimeout,
        );
      }

      if (decision['t'] == MsgType.reject) {
        job.state = JobState.cancelled;
        job.error = decision['reason'] as String? ?? 'err.userRejected';
        job.finishedAt = DateTime.now();
        onChanged?.call();
        return;
      }

      final resume = <String, int>{};
      final resumeRaw = decision['resume'];
      if (resumeRaw is Map) {
        resumeRaw.forEach((k, v) {
          resume['$k'] = (v as num?)?.toInt() ?? 0;
        });
      }
      // Sunucunun bildirdiği nihai adlar (çakışma yönetimi).
      final namesRaw = decision['names'];
      if (namesRaw is Map) {
        namesRaw.forEach((k, v) {
          if (v is! String) return;
          final ft = job.files.cast<FileTransfer?>().firstWhere(
                (f) => f?.id == k,
                orElse: () => null,
              );
          if (ft != null) ft.relPath = v;
        });
      }

      job.state = JobState.transferring;
      onChanged?.call();

      // 4) Dosya akışı
      for (var i = 0; i < files.length; i++) {
        if (aborted) return;
        final file = files[i];
        final meta = offerFiles[i];
        final fileId = meta['id'] as String;
        final offset = resume[fileId] ?? 0;
        final ft = job.files.firstWhere((f) => f.id == fileId);
        await _streamFile(channel, file, fileId, offset, ft, job, onChanged);
      }

      if (aborted) return;

      // 5) Kapanış — alıcının onayını beklemeden başarı ilan edilmez (Y-11).
      channel.sendControl({'t': MsgType.done, 'job': job.id});
      final acked = await Future.any<bool>([
        router
            .waitFor(MsgType.done, timeout: LyraProtocol.approvalTimeout)
            .then((_) => true)
            .catchError((_) => false),
        abortSignal.future.then((_) => false),
      ]);
      if (aborted) return;
      if (!acked) {
        job.state = JobState.failed;
        job.error = 'err.noAck';
        job.finishedAt = DateTime.now();
        onChanged?.call();
        return;
      }
      job.state = JobState.completed;
      job.finishedAt = DateTime.now();
      onChanged?.call();
    } catch (e) {
      if (!job.isFinished) {
        job.state = JobState.failed;
        job.error = '$e';
        job.finishedAt = DateTime.now();
        onChanged?.call();
      }
      rethrow;
    } finally {
      router.dispose();
      channel.close();
    }
  }

  Future<void> _streamFile(
    LyraChannel channel,
    File file,
    String fileId,
    int offset,
    FileTransfer ft,
    TransferJob job,
    void Function()? onChanged,
  ) async {
    final raf = await file.open();
    try {
      if (offset > 0) {
        // Resume: atlanan baş kısım istenmez; ilerleme göstergesi için
        // iş sayacı offset kadar ileri alınır.
        await raf.setPosition(offset);
        ft.done = offset;
        job.transferred += offset;
        onChanged?.call();
      }
      channel.sendControl({
        't': MsgType.fileStart,
        'job': job.id,
        'file': fileId,
        'offset': offset,
      });

      var chunk = await raf.read(LyraProtocol.chunkSize);
      while (chunk.isNotEmpty) {
        channel.sendData(chunk);
        ft.done += chunk.length;
        job.transferred += chunk.length;
        onChanged?.call();
        chunk = await raf.read(LyraProtocol.chunkSize);
      }
      ft.completed = true;
      onChanged?.call();
    } finally {
      await raf.close();
    }
    // Bütünlük özeti: tam dosya üzerinden, UI isolate'inden ayrı (O-17).
    // Resume edilmiş aktarımlarda da tüm dosya kapsanır (Y-7).
    final digest = await sha256OfFile(file.path);
    channel.sendControl({
      't': MsgType.fileEnd,
      'job': job.id,
      'file': fileId,
      'sha256': digest,
    });
  }

  static String _baseName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    final name = parts.isEmpty ? path : parts.last;
    return name.isEmpty ? 'dosya' : name;
  }

  static String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text/plain';
    if (lower.endsWith('.zip')) return 'application/zip';
    return 'application/octet-stream';
  }
}
