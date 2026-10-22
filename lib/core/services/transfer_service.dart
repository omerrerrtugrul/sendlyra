import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/device.dart';
import '../models/transfer_job.dart';
import '../protocol/lyra_message.dart';
import '../protocol/transfer_client.dart';
import '../protocol/transfer_server.dart';
import 'discovery_service.dart';
import 'history_service.dart';
import 'identity_service.dart';
import 'settings_service.dart';

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

  void reject([String reason = 'kullanıcı reddetti']) {
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

  final List<TransferJob> jobs = [];
  final _incomingController = StreamController<IncomingRequest>.broadcast();

  TransferService({
    required this.identity,
    required this.settings,
    required this.history,
  });

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

    _discovery = DiscoveryService(
      identity: () => BeaconIdentity(
        id: identity.deviceId,
        name: identity.alias,
        os: identity.os,
        deviceType: identity.deviceType,
        port: settings.transferPort,
        publicKeyBase64: identity.publicKeyBase64,
        fingerprint: identity.fingerprint,
      ),
    );
    if (settings.discoveryOn) {
      await _discovery?.start();
    }

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
        onOffer: (offer, peer, {required pinVerified}) async {
          final request = IncomingRequest(
            offer: offer,
            peer: peer,
            pinVerified: pinVerified,
          );
          // Hızlı kaydetme kipleri: kullanıcı onayı olmadan kabul.
          if (pinVerified && settings.autoAcceptFrom(peer.id)) {
            request.accept();
            return request.decision.future;
          }
          if (settings.isTrusted(peer.id) && pinVerified) {
            request.accept();
            return request.decision.future;
          }
          _incomingController.add(request);
          return request.decision.future.timeout(
            const Duration(seconds: 120),
            onTimeout: () => const AcceptDecision.reject('zaman aşımı'),
          );
        },
      ),
      onJobCreated: _onJobCreated,
      onJobUpdated: _onJobUpdated,
      onJobFinished: _onJobFinished,
    );
    await server.start();
    _server = server;
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
    notifyListeners();
  }

  void _onJobUpdated(TransferJob job) {
    _sampleSpeed(job);
    notifyListeners();
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
    notifyListeners();
  }

  /// Seçilen dosyaları hedef cihaza gönderir.
  ///
  /// [relPaths] klasör yapısını korur; her dosya için göreli yol içerir.
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
    notifyListeners();

    final client = LyraTransferClient(
      localInfo: identity.hello(settings.transferPort),
      keyPair: identity.keyPair,
    );

    try {
      await client.send(
        target: target,
        job: job,
        files: files,
        relPaths: relPaths,
        text: text,
        pin: pin,
        onChanged: () => _onJobUpdated(job),
      );
    } catch (_) {
      // Durum job nesnesine işlendi.
    }
    unawaited(history.add(job));
    notifyListeners();
    return job;
  }

  /// Aktif bir işi iptal eder (yerel taraf).
  void cancelJob(TransferJob job) {
    if (job.isFinished) return;
    job.state = JobState.cancelled;
    job.error = 'yerel olarak iptal edildi';
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
    _server?.stop();
    _discovery?.dispose();
    _incomingController.close();
    super.dispose();
  }
}
