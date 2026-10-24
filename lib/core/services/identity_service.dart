import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/lyra_crypto.dart';
import '../protocol/lyra_message.dart';
import '../protocol/lyra_protocol.dart';
import 'secret_store.dart';

/// Cihazın kalıcı kimliği: id, takma ad, X25519 anahtar çifti, parmak izi.
class IdentityService extends ChangeNotifier {
  static const _kDeviceId = 'identity.deviceId';
  static const _kAlias = 'identity.alias';
  static const _kPrivateKey = 'identity.privateKey';
  static const _kPublicKey = 'identity.publicKey';
  static const _kFingerprint = 'identity.fingerprint';

  late String deviceId;
  late String alias;
  late String _privateKeyB64;
  late String publicKeyBase64;
  late String fingerprint;
  SimpleKeyPair? _keyPair;

  final SharedPreferences prefs;

  /// Özel anahtarın güvenli saklanması (O-13): platform kasası,
  /// erişilemezse düz metin yedeğine düşer.
  final SecretStore secrets;

  IdentityService(this.prefs, {SecretStore? secrets})
      : secrets = secrets ?? SecretStore(prefs);

  static Future<IdentityService> load(SharedPreferences prefs,
      {SecretStore? secrets}) async {
    final service = IdentityService(prefs, secrets: secrets);
    await service._init();
    return service;
  }

  Future<void> _init() async {
    deviceId = prefs.getString(_kDeviceId) ?? _generateId();
    alias = prefs.getString(_kAlias) ?? _defaultAlias();
    // Özel anahtar yalnızca güvenli kasada saklanır (eski düz metin
    // kopya varsa SecretStore.read otomatik taşır).
    _privateKeyB64 = await secrets.read(_kPrivateKey) ?? '';
    publicKeyBase64 = prefs.getString(_kPublicKey) ?? '';
    fingerprint = prefs.getString(_kFingerprint) ?? '';

    if (_privateKeyB64.isEmpty || publicKeyBase64.isEmpty) {
      final keyPair = await LyraCryptoIdentity.generateKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      _privateKeyB64 = await LyraCryptoIdentity.exportPrivateKey(keyPair);
      publicKeyBase64 = base64Encode(publicKey.bytes);
      fingerprint = await LyraCryptoIdentity.fingerprintOf(publicKey.bytes);
      _keyPair = keyPair;
      await _persist();
    } else {
      // Eski düz metin kayıttan kasaya geçişi tamamla.
      await secrets.write(_kPrivateKey, _privateKeyB64);
      _keyPair = await LyraCryptoIdentity.importPrivateKey(
        _privateKeyB64,
        base64Decode(publicKeyBase64),
      );
    }
  }

  Future<void> _persist() async {
    await prefs.setString(_kDeviceId, deviceId);
    await prefs.setString(_kAlias, alias);
    await secrets.write(_kPrivateKey, _privateKeyB64);
    await prefs.setString(_kPublicKey, publicKeyBase64);
    await prefs.setString(_kFingerprint, fingerprint);
  }

  SimpleKeyPair get keyPair {
    final kp = _keyPair;
    if (kp == null) throw StateError('kimlik henüz yüklenmedi');
    return kp;
  }

  List<int> get publicKeyBytes => base64Decode(publicKeyBase64);

  String get os => Platform.operatingSystem;

  String get deviceType {
    if (Platform.isAndroid || Platform.isIOS) return 'mobile';
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return 'desktop';
    }
    return 'unknown';
  }

  /// Ağda tanıtılacak isim.
  Future<void> setAlias(String value) async {
    alias = value.trim().isEmpty ? alias : value.trim();
    await _persist();
    notifyListeners();
  }

  /// El sıkışma bilgisi üretir.
  HelloInfo hello(int transferPort) => HelloInfo(
        version: LyraProtocol.protocolVersion,
        id: deviceId,
        name: alias,
        os: os,
        deviceType: deviceType,
        publicKey: publicKeyBytes,
        fingerprint: fingerprint,
      );

  static String _generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _defaultAlias() {
    final suffix = Random().nextInt(90) + 10;
    return 'SendLyra-$suffix';
  }
}
