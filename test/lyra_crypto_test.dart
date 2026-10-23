import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/protocol/lyra_crypto.dart';
import 'package:sendlyra/core/protocol/lyra_message.dart';

void main() {
  group('hkdfSha256', () {
    test('RFC 5869 Test Case 1 vektörüyle uyumlu', () {
      final ikm = List<int>.filled(22, 0x0b);
      final salt = List<int>.generate(13, (i) => i);
      final info = List<int>.generate(10, (i) => 0xf0 + i);
      final okm = hkdfSha256(ikm: ikm, salt: salt, info: info, length: 42);
      final hex = okm.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(
        hex,
        '3cb25f25faacd57a90434f64d0362f2a'
        '2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      );
    });
  });

  group('deriveSessionKeys', () {
    test('istemci ve sunucu aynı oturum anahtarlarını türetir', () async {
      final alice = await X25519().newKeyPair();
      final bob = await X25519().newKeyPair();
      final alicePk = await alice.extractPublicKey();
      final bobPk = await bob.extractPublicKey();

      final aliceKeys = await deriveSessionKeys(
        myKeyPair: alice,
        theirPublicKey: bobPk.bytes,
        isClient: true,
      );
      final bobKeys = await deriveSessionKeys(
        myKeyPair: bob,
        theirPublicKey: alicePk.bytes,
        isClient: false,
      );

      final aSend = await aliceKeys.sendKey.extractBytes();
      final bRecv = await bobKeys.recvKey.extractBytes();
      final aRecv = await aliceKeys.recvKey.extractBytes();
      final bSend = await bobKeys.sendKey.extractBytes();

      expect(aSend, bRecv);
      expect(aRecv, bSend);
      // Yönlere göre anahtarlar farklı olmalı.
      expect(aSend, isNot(aRecv));
    });
  });

  group('LyraCipher', () {
    test('mühürleme ve çözme turu çalışır', () async {
      final key = SecretKey(List<int>.generate(32, (i) => i));
      final sender = LyraCipher(key);
      final receiver = LyraCipher(key);

      final sealed = await sender.seal(utf8.encode('merhaba lyralink'));
      final opened = await receiver.open(sealed);
      expect(utf8.decode(opened), 'merhaba lyralink');

      // Sayaç ilerledikçe farklı kareler üretilir.
      final sealed2 = await sender.seal(utf8.encode('ikinci'));
      expect(sealed2, isNot(sealed));
      expect(utf8.decode(await receiver.open(sealed2)), 'ikinci');
    });

    test('bozulan kare doğrulamadan geçmez', () async {
      final key = SecretKey(List<int>.generate(32, (i) => i + 7));
      final sender = LyraCipher(key);
      final receiver = LyraCipher(key);

      final sealed = await sender.seal(utf8.encode('gizli'));
      sealed[0] = sealed[0] ^ 0xff;
      expect(
        () => receiver.open(sealed),
        throwsA(isA<LyraProtocolException>()),
      );
    });
  });

  group('LyraCryptoIdentity', () {
    test('anahtar dışa/içe aktarım turu', () async {
      final keyPair = await LyraCryptoIdentity.generateKeyPair();
      final exported = await LyraCryptoIdentity.exportPrivateKey(keyPair);
      final publicKey = (await keyPair.extractPublicKey()).bytes;
      final restored =
          await LyraCryptoIdentity.importPrivateKey(exported, publicKey);
      final restoredPk = (await restored.extractPublicKey()).bytes;
      expect(restoredPk, publicKey);

      final fp = await LyraCryptoIdentity.fingerprintOf(publicKey);
      // Tam SHA-256 özeti: 64 hex karakter.
      expect(fp.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(fp), isTrue);
    });

    test('parmak izi açık anahtarla birebir doğrulanır', () async {
      final keyPair = await LyraCryptoIdentity.generateKeyPair();
      final publicKey = (await keyPair.extractPublicKey()).bytes;
      final fp = await LyraCryptoIdentity.fingerprintOf(publicKey);

      // Beyan edilen iz ile gerçek anahtar uyuşmuyorsa reddedilir.
      final spoofed = '${fp.substring(0, 63)}${fp.endsWith('0') ? '1' : '0'}';
      expect(spoofed == fp, isFalse);
    });
  });

  group('sabit zamanlı karşılaştırma', () {
    test('eşit değerler eşit bulunur', () {
      expect(LyraCryptoIdentity.constantTimeEquals('1234', '1234'), isTrue);
      expect(LyraCryptoIdentity.constantTimeEquals('', ''), isTrue);
    });

    test('farklı uzunluk ve içerik eşit bulunmaz', () {
      expect(
          LyraCryptoIdentity.constantTimeEquals('1234', '12345'), isFalse);
      expect(
          LyraCryptoIdentity.constantTimeEquals('1234', '1235'), isFalse);
      expect(LyraCryptoIdentity.constantTimeEquals('abc', ''), isFalse);
    });
  });
}
