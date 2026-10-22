import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'lyra_message.dart';

/// HKDF-SHA256 (RFC 5869) — paket bağımlılığı olmadan, sadece `crypto` ile.
Uint8List hkdfSha256({
  required List<int> ikm,
  required List<int> salt,
  required List<int> info,
  int length = 32,
}) {
  final hmacExtract = crypto.Hmac(crypto.sha256, salt);
  final prk = hmacExtract.convert(ikm).bytes;

  final out = <int>[];
  List<int> prev = const [];
  var counter = 1;
  while (out.length < length) {
    final hmacExpand = crypto.Hmac(crypto.sha256, prk);
    final input = <int>[...prev, ...info, counter];
    prev = hmacExpand.convert(input).bytes;
    out.addAll(prev);
    counter++;
    if (counter > 255) {
      throw StateError('HKDF çıktısı çok uzun');
    }
  }
  return Uint8List.fromList(out.sublist(0, length));
}

/// X25519 + HKDF ile oturum anahtarlarını türetir.
///
/// `isClient` tarafın gönderim anahtarı c2s, alım anahtarı s2c olur;
/// sunucu tam tersini kullanır. Böylece iki yönlü trafik ayrı anahtarlarla
/// şifrelenir ve nonce tekrarı imkânsız hale gelir.
class LyraHandshakeKeys {
  final SecretKey sendKey;
  final SecretKey recvKey;

  const LyraHandshakeKeys({required this.sendKey, required this.recvKey});
}

Future<LyraHandshakeKeys> deriveSessionKeys({
  required SimpleKeyPair myKeyPair,
  required List<int> theirPublicKey,
  required bool isClient,
}) async {
  final algorithm = X25519();
  final shared = await algorithm.sharedSecretKey(
    keyPair: myKeyPair,
    remotePublicKey: SimplePublicKey(
      List<int>.from(theirPublicKey),
      type: KeyPairType.x25519,
    ),
  );
  final myPk = (await myKeyPair.extractPublicKey()).bytes;
  // Tuz (salt): istemci|sunucu açık anahtarları — iki taraf da aynı değeri görür.
  final salt = isClient
      ? <int>[...myPk, ...theirPublicKey]
      : <int>[...theirPublicKey, ...myPk];
  final ikm = await shared.extractBytes();

  final c2s = hkdfSha256(
    ikm: ikm,
    salt: salt,
    info: utf8.encode('LyraLink-c2s-v1'),
  );
  final s2c = hkdfSha256(
    ikm: ikm,
    salt: salt,
    info: utf8.encode('LyraLink-s2c-v1'),
  );

  return isClient
      ? LyraHandshakeKeys(
          sendKey: SecretKey(c2s),
          recvKey: SecretKey(s2c),
        )
      : LyraHandshakeKeys(
          sendKey: SecretKey(s2c),
          recvKey: SecretKey(c2s),
        );
}

/// Kriptografik kimlik üretimi ve parmak izi.
class LyraCryptoIdentity {
  /// Yeni bir X25519 anahtar çifti üretir.
  static Future<SimpleKeyPair> generateKeyPair() =>
      X25519().newKeyPair();

  /// Açık anahtarın SHA-256 parmak izinin ilk 8 baytı (hex).
  static Future<String> fingerprintOf(List<int> publicKey) async {
    final digest = crypto.sha256.convert(publicKey);
    return digest.bytes
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Özel anahtar baytlarını (base64) saklanabilir biçime çevirir.
  static Future<String> exportPrivateKey(SimpleKeyPair keyPair) async {
    final bytes = await keyPair.extractPrivateKeyBytes();
    return base64Encode(bytes);
  }

  /// Kayıtlı anahtardan anahtar çifti yeniden kurar.
  static Future<SimpleKeyPair> importPrivateKey(
    String base64Key,
    List<int> publicKey,
  ) async {
    final privateBytes = base64Decode(base64Key);
    return SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(
        List<int>.from(publicKey),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
  }
}

/// Yönlendirilmiş, sayaca dayalı AEAD kripto kanalı.
///
/// Nonce = 8 baytlık sayaç (big-endian) + 4 baytlık sıfır dolgu.
/// Her anahtar için sayaç 0'dan başlar ve asla tekrar etmez.
class LyraCipher {
  final SecretKey _key;
  final _algorithm = Chacha20.poly1305Aead();
  int _sendCounter = 0;
  int _recvCounter = 0;

  LyraCipher(this._key);

  static const int _macLength = 16;

  Uint8List _nonce(int counter) {
    final nonce = Uint8List(12);
    final bd = ByteData.sublistView(nonce);
    bd.setUint64(0, counter);
    return nonce;
  }

  /// Düz metni şifreler (ciphertext || mac).
  Future<Uint8List> seal(List<int> plaintext) async {
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: _key,
      nonce: _nonce(_sendCounter++),
    );
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  /// Şifreli kareyi çözer.
  Future<Uint8List> open(List<int> frame) async {
    if (frame.length < _macLength) {
      throw const LyraProtocolException('kare çok kısa');
    }
    final cipherText = frame.sublist(0, frame.length - _macLength);
    final mac = frame.sublist(frame.length - _macLength);
    final box = SecretBox(
      cipherText,
      nonce: _nonce(_recvCounter++),
      mac: Mac(mac),
    );
    try {
      return Uint8List.fromList(await _algorithm.decrypt(box, secretKey: _key));
    } on SecretBoxAuthenticationError {
      throw const LyraProtocolException('doğrulama başarısız (kare bozuk ya da anahtar uyuşmuyor)');
    }
  }
}
