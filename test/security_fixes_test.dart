import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/protocol/lyra_channel.dart';
import 'package:sendlyra/core/protocol/lyra_crypto.dart';
import 'package:sendlyra/core/protocol/lyra_message.dart';
import 'package:sendlyra/core/protocol/transfer_server.dart';
import 'package:sendlyra/core/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SimpleKeyPair> _keyPair() => LyraCryptoIdentity.generateKeyPair();

Future<HelloInfo> _hello(
  SimpleKeyPair keyPair, {
  String id = 'peer-1',
  String? spoofedFingerprint,
}) async {
  final pk = (await keyPair.extractPublicKey()).bytes;
  final fp = await LyraCryptoIdentity.fingerprintOf(pk);
  return HelloInfo(
    version: 1,
    id: id,
    name: 'test-peer',
    os: 'linux',
    deviceType: 'desktop',
    publicKey: pk,
    fingerprint: spoofedFingerprint ?? fp,
  );
}

void main() {
  group('K-1: el sıkışma kimlik doğrulaması', () {
    test('sahte parmak izi ile hello reddedilir', () async {
      final serverKp = await _keyPair();
      final attackerKp = await _keyPair();
      final serverHello = await _hello(serverKp, id: 'server');

      final listener =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(listener.close);

      final handshakeFuture = () async {
        final socket = await listener.first;
        final channel = LyraChannel(socket, isClient: false);
        addTearDown(channel.close);
        return channel.handshake(serverHello, keyPair: serverKp);
      }();

      // Saldırgan: gerçek anahtarının parmak izi yerine başka bir iz
      // beyan ediyor (aktif MITM taklidi).
      final attackerHello = await _hello(attackerKp,
          spoofedFingerprint:
              'a' * 64); // gerçek sha256(pk) ile uyuşmayacak
      final raw = await Socket.connect(
          InternetAddress.loopbackIPv4, listener.port);
      addTearDown(raw.destroy);
      raw.add(utf8.encode('${jsonEncode(attackerHello.toJson())}\n'));

      await expectLater(
        handshakeFuture,
        throwsA(isA<LyraProtocolException>()),
      );
    });

    test('geçerli parmak izi el sıkışmayı tamamlar', () async {
      final serverKp = await _keyPair();
      final clientKp = await _keyPair();
      final serverHello = await _hello(serverKp, id: 'server');
      final clientHello = await _hello(clientKp, id: 'client');

      final listener =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(listener.close);

      final serverFuture = () async {
        final socket = await listener.first;
        final channel = LyraChannel(socket, isClient: false);
        addTearDown(channel.close);
        return channel.handshake(serverHello, keyPair: serverKp);
      }();

      final raw = await Socket.connect(
          InternetAddress.loopbackIPv4, listener.port);
      final clientChannel = LyraChannel(raw, isClient: true);
      addTearDown(clientChannel.close);
      final clientDone =
          clientChannel.handshake(clientHello, keyPair: clientKp);

      final serverPeer = await serverFuture;
      final clientPeer = await clientDone;
      expect(serverPeer.id, 'client');
      expect(clientPeer.id, 'server');
    });
  });

  group('K-3: PIN kilidi', () {
    test('auth gönderilmeden gelen teklif reddedilir', () async {
      final serverKp = await _keyPair();
      final clientKp = await _keyPair();
      final serverHello = await _hello(serverKp, id: 'server');
      final clientHello = await _hello(clientKp, id: 'client');

      var onOfferCalled = false;
      final saveDir = Directory.systemTemp.createTempSync('lyra-pin-test');
      addTearDown(() => saveDir.deleteSync(recursive: true));

      // Boş port bul, sonra sunucuyu o portta başlat.
      final probe =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final server = LyraTransferServer(
        localInfo: serverHello,
        keyPair: serverKp,
        port: port,
        saveDir: saveDir.path,
        policy: ServerPolicy(
          pin: () => '1234',
          onOffer: (offer, peer, {required pinVerified}) async {
            onOfferCalled = true;
            return const AcceptDecision.reject('beklenmiyordu');
          },
        ),
      );
      await server.start();
      addTearDown(server.stop);

      final socket =
          await Socket.connect(InternetAddress.loopbackIPv4, port);
      final channel = LyraChannel(socket, isClient: true);
      addTearDown(channel.close);
      await channel.handshake(clientHello, keyPair: clientKp);

      // K-3 saldırısı: auth göndermeden doğrudan offer.
      final errorWait = channel.events
          .where((e) => !e.isData && e.type == 'error')
          .first
          .timeout(const Duration(seconds: 5));
      channel.sendControl({
        't': 'offer',
        'job': 'evil-job',
        'files': [
          {'id': 'f0', 'name': 'payload.txt', 'size': 5},
        ],
      });

      // Sunucu hata ile karşılık vermeli; politika asla çağrılmamalı.
      final error = await errorWait;
      expect(error.data['reason'], 'err.pinRequired');
      expect(onOfferCalled, isFalse);
    });

    test('yanlış PIN denemesi başarısız olur ve kilitlenir', () async {
      final serverKp = await _keyPair();
      final clientKp = await _keyPair();
      final serverHello = await _hello(serverKp, id: 'server');
      final clientHello = await _hello(clientKp, id: 'client');

      final saveDir = Directory.systemTemp.createTempSync('lyra-pin-test2');
      addTearDown(() => saveDir.deleteSync(recursive: true));
      final listener =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = listener.port;
      await listener.close();

      final server = LyraTransferServer(
        localInfo: serverHello,
        keyPair: serverKp,
        port: port,
        saveDir: saveDir.path,
        policy: ServerPolicy(
          pin: () => '1234',
          onOffer: (offer, peer, {required pinVerified}) async =>
              const AcceptDecision.reject('gerekmez'),
        ),
      );
      await server.start();
      addTearDown(server.stop);

      // 5 hatalı deneme → kilitleme; 6. denemede "çok fazla hatalı".
      Object? lastReason;
      for (var i = 0; i < 6; i++) {
        final socket =
            await Socket.connect(InternetAddress.loopbackIPv4, port);
        final channel = LyraChannel(socket, isClient: true);
        await channel.handshake(clientHello, keyPair: clientKp);
        final wait = channel.events
            .where((e) => !e.isData && e.type == 'auth-result')
            .first
            .timeout(const Duration(seconds: 5));
        channel.sendControl({'t': 'auth', 'pin': 'yanlis-$i'});
        final result = await wait;
        lastReason = result.data['reason'];
        channel.close();
      }
      expect(lastReason, 'err.tooManyAttempts');
    });
  });

  group('K-2: TOFU parmak izi pingleme', () {
    test('parmak izi değişimi tespit edilir', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      await settings.rememberPeer('cihaz-1', 'iz-a');
      expect(settings.fingerprintChanged('cihaz-1', 'iz-a'), isFalse);
      expect(settings.fingerprintChanged('cihaz-1', 'iz-b'), isTrue);
      // Bilinmeyen cihaz → ilk karşılaşma, hata sayılmaz.
      expect(settings.fingerprintChanged('cihaz-2', 'iz-x'), isFalse);
    });

    test('güvenilir liste parmak izine bağlıdır', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);

      await settings.setTrusted('iz-a', true);
      expect(settings.isTrusted('iz-a'), isTrue);
      // Aynı cihaz kimliği farklı izle gelirse güven geçerli olmaz.
      expect(settings.isTrusted('iz-b'), isFalse);
      await settings.setTrusted('iz-a', false);
      expect(settings.isTrusted('iz-a'), isFalse);
    });
  });
}
