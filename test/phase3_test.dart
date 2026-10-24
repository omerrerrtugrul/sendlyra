import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/models/device.dart';
import 'package:sendlyra/core/models/transfer_job.dart';
import 'package:sendlyra/core/protocol/lyra_crypto.dart';
import 'package:sendlyra/core/protocol/lyra_message.dart';
import 'package:sendlyra/core/protocol/transfer_server.dart';
import 'package:sendlyra/core/services/history_service.dart';
import 'package:sendlyra/core/services/identity_service.dart';
import 'package:sendlyra/core/services/notification_service.dart';
import 'package:sendlyra/core/services/settings_service.dart';
import 'package:sendlyra/core/services/transfer_service.dart';
import 'package:sendlyra/core/utils/format.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_secret_store.dart';

Future<SimpleKeyPair> _keyPair() => LyraCryptoIdentity.generateKeyPair();

Future<HelloInfo> _hello(SimpleKeyPair keyPair, {String id = 'peer'}) async {
  final pk = (await keyPair.extractPublicKey()).bytes;
  final fp = await LyraCryptoIdentity.fingerprintOf(pk);
  return HelloInfo(
    version: 1,
    id: id,
    name: 'test-peer',
    os: 'linux',
    deviceType: 'desktop',
    publicKey: pk,
    fingerprint: fp,
  );
}

/// Servis test yığını: gerçek ağ yok, sahte güvenli kasa.
Future<(TransferService, FakeTransferNotifier)> _service() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secrets = FakeSecretStore(prefs);
  final identity = await IdentityService.load(prefs, secrets: secrets);
  final settings = SettingsService(prefs, secrets: secrets);
  await settings.loadSecrets();
  final history = HistoryService(prefs);
  final notifier = FakeTransferNotifier();
  final service = TransferService(
    identity: identity,
    settings: settings,
    history: history,
    notifier: notifier,
  );
  addTearDown(service.dispose);
  return (service, notifier);
}

void main() {
  group('E-04: meşgul kuyruklaması', () {
    test('meşgul hedefe gönderim kuyruğa düşer, iptal edilebilir', () async {
      final (service, notifier) = await _service();
      final target = LyraDevice(
        id: 'peer',
        name: 'meşgul-cihaz',
        os: 'linux',
        deviceType: 'desktop',
        address: InternetAddress.loopbackIPv4.address,
        port: 1,
        publicKeyBase64: '',
        fingerprint: 'f' * 64,
        lastSeen: DateTime.now(),
        busy: true,
      );

      final job = await service.send(
        target: target,
        files: const [],
        text: 'kuyrukta beklesin',
      );
      expect(job.state, JobState.queued);
      expect(service.queueLength, 1);
      // Henüz bitmedi: bildirim ve geçmiş kaydı olmamalı.
      expect(notifier.notified, isEmpty);

      service.cancelJob(job);
      expect(job.state, JobState.cancelled);
      expect(service.queueLength, 0);
    });

    test('err.busy reddi kuyruklanır; cihaz uygun olunca tamamlanır',
        () async {
      // Loopback sunucu: ilk teklifi "meşgul" diye reddet, sonrakini kabul et.
      final serverKp = await _keyPair();
      final serverHello = await _hello(serverKp, id: 'server');
      final saveDir = Directory.systemTemp.createTempSync('lyra-queue-test');
      addTearDown(() => saveDir.deleteSync(recursive: true));

      var offers = 0;
      final server = LyraTransferServer(
        localInfo: serverHello,
        keyPair: serverKp,
        port: 0, // çekirdek ephemeral port atar — port yarışı olmaz
        saveDir: saveDir.path,
        policy: ServerPolicy(
          pin: () => null,
          onOffer: (offer, peer, {required pinVerified}) async {
            offers++;
            if (offers == 1) {
              return const AcceptDecision.reject('err.busy');
            }
            return const AcceptDecision.accept({});
          },
        ),
      );
      await server.start();
      addTearDown(server.stop);

      final (service, notifier) = await _service();
      final target = LyraDevice(
        id: 'server',
        name: 'test-peer',
        os: 'linux',
        deviceType: 'desktop',
        address: InternetAddress.loopbackIPv4.address,
        port: server.boundPort,
        publicKeyBase64: '',
        fingerprint: serverHello.fingerprint,
        lastSeen: DateTime.now(),
      );

      final job = await service.send(
        target: target,
        files: const [],
        text: 'kuyruk testi',
      );

      // İlk deneme err.busy ile bitti → iş kuyruğa dönmüş olmalı.
      expect(job.state, JobState.queued);
      expect(service.queueLength, 1);
      expect(notifier.notified, isEmpty);

      // Kuyruktan ikinci deneme: bu kez kabul edilir.
      await service.pumpQueue();
      expect(job.state, JobState.completed);
      expect(service.queueLength, 0);
      expect(offers, 2);

      // Bitirilen iş bir kez bildirilmiş olmalı.
      expect(notifier.notified, [job]);
    });
  });

  group('E-03: bildirim içerikleri', () {
    TransferJob job({JobState state = JobState.completed, String? error}) {
      final j = TransferJob(
        id: 'j1',
        direction: JobDirection.send,
        peerId: 'p',
        peerName: 'dizustu',
        peerAddress: '192.168.1.5',
        files: const [],
        text: 'merhaba dunya',
        createdAt: DateTime.now(),
      );
      j.state = state;
      j.error = error;
      return j;
    }

    test('tamamlanan gönderim (TR)', () {
      final (title, body) = notificationContent(job());
      expect(title, 'Gönderim tamamlandı');
      expect(body, contains('merhaba'));
    });

    test('başarısız alım (EN)', () {
      final received = TransferJob(
        id: 'j2',
        direction: JobDirection.receive,
        peerId: 'p',
        peerName: 'telefon',
        peerAddress: '192.168.1.6',
        files: const [],
        text: 'selam',
        createdAt: DateTime.now(),
      )..state = JobState.failed;
      final (title, body) = notificationContent(received, locale: 'en');
      expect(title, 'Receive failed');
      expect(body, contains('selam'));
    });
  });

  group('E-02: pano metni', () {
    test('boş/yalnız boşluklu pano elenir', () {
      expect(normalizeClipboardText(null), isNull);
      expect(normalizeClipboardText(''), isNull);
      expect(normalizeClipboardText('   \n\t '), isNull);
    });

    test('metin kırpılır', () {
      expect(normalizeClipboardText('  merhaba  '), 'merhaba');
      expect(normalizeClipboardText('satır\niçeriği'), 'satır\niçeriği');
    });
  });
}
