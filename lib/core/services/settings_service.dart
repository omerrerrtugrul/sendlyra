import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secret_store.dart';

/// Uygulama ayarları (kalıcı).
class SettingsService extends ChangeNotifier {
  static const _kSaveDir = 'settings.saveDir';
  static const _kThemeMode = 'settings.themeMode';
  static const _kAccent = 'settings.accent';
  static const _kRequireApproval = 'settings.requireApproval';
  static const _kPin = 'settings.pin';
  static const _kTrusted = 'settings.trustedFps';
  static const _kVerified = 'settings.verifiedFps';
  static const _kQuickSave = 'settings.quickSave';
  static const _kFavorites = 'settings.favorites';
  static const _kKnownPeers = 'settings.knownPeers';
  static const _kTransferPort = 'settings.transferPort';
  static const _kDiscoveryOn = 'settings.discoveryOn';
  static const _kWebPort = 'settings.webPort';
  static const _kWebPin = 'settings.webPin';
  static const _kWebTlsCert = 'settings.webTlsCert';
  static const _kWebTlsKey = 'settings.webTlsKey';
  static const _kLocale = 'settings.locale';
  static const _kTrustNoticeShown = 'settings.trustMigrationNoticeShown';

  final SharedPreferences prefs;

  /// PIN gibi gizli değerlerin güvenli saklanması (O-13).
  final SecretStore? secrets;

  late String saveDir;
  late ThemeMode themeMode;
  late int accentIndex;

  /// Tek kaynak (O-16): onay kipi yalnızca [quickSaveMode] ile belirlenir.
  bool get requireApproval => quickSaveMode == 'off';
  /// 'off' = onay iste, 'all' = herkesten otomatik kabul,
  /// 'favorites' = yalnızca favorilerden otomatik kabul.
  late String quickSaveMode;
  late String? pin;

  /// Güvenilir cihazlar — her zaman **doğrulanmış parmak izine** bağlıdır;
  /// karşı tarafın beyan ettiği kimliğe değil (taklit engeli).
  late List<String> trustedFingerprints;

  /// R-1: parmak izi karşılaştırmasıyla kullanıcı tarafından doğrulanmış
  /// cihazların parmak izleri (QR/ekran üzerinden birebir karşılaştırma).
  late List<String> verifiedFingerprints;

  /// Favoriler — anahtar: parmak izi, değer: özel ad.
  late Map<String, String> favoriteNames;

  /// TOFU: cihaz kimliği → ilk karşılaşımda görülen parmak izi.
  /// Sonraki bağlantıda iz değişirse bağlantı reddedilir.
  late Map<String, String> knownPeers;

  late int transferPort;
  late bool discoveryOn;

  /// W-01: web paylaşım sunucusu portu.
  late int webPort;

  /// W-04: web PIN (tarayıcı oturumu için) — cihaz PIN'inden ayrı.
  late String? webPin;

  /// W-05: HTTPS için isteğe bağlı sertifika/anahtar yolları.
  late String webTlsCert;
  late String webTlsKey;
  late String localeCode;

  SettingsService(this.prefs, {this.secrets}) {
    saveDir = prefs.getString(_kSaveDir) ?? '';
    themeMode = ThemeMode
        .values[prefs.getInt(_kThemeMode) ?? ThemeMode.system.index];
    accentIndex = prefs.getInt(_kAccent) ?? 0;
    // Eski `requireApproval` anahtarı yalnızca başlangıç değeri için.
    final legacyApproval = prefs.getBool(_kRequireApproval) ?? true;
    quickSaveMode =
        prefs.getString(_kQuickSave) ?? (legacyApproval ? 'off' : 'all');
    // R-2: kasa mevcutken düz metin kopya asla okunmaz; PIN yalnızca
    // [loadSecrets] ile kasadan yüklenir. Kasa olmayan ortamda
    // (secrets == null, ör. testler) eski düz metin akışı korunur.
    pin = (secrets == null) ? prefs.getString(_kPin) : null;
    trustedFingerprints = prefs.getStringList(_kTrusted) ?? [];
    verifiedFingerprints = prefs.getStringList(_kVerified) ?? [];
    favoriteNames = _decodeFavorites(prefs.getString(_kFavorites));
    knownPeers = _decodeFavorites(prefs.getString(_kKnownPeers));
    transferPort = prefs.getInt(_kTransferPort) ?? 47802;
    discoveryOn = prefs.getBool(_kDiscoveryOn) ?? true;
    webPort = prefs.getInt(_kWebPort) ?? 8765;
    webPin = (secrets == null) ? prefs.getString(_kWebPin) : null;
    webTlsCert = prefs.getString(_kWebTlsCert) ?? '';
    webTlsKey = prefs.getString(_kWebTlsKey) ?? '';
    localeCode = prefs.getString(_kLocale) ?? 'tr';
  }

  bool get hasPin => pin != null && pin!.isNotEmpty;
  bool get hasWebPin => webPin != null && webPin!.isNotEmpty;

  /// Hızlı kaydetme kipi: gelen istekler otomatik kabul edilir mi?
  /// Karar her zaman doğrulanmış parmak izi üzerinden verilir.
  bool autoAcceptFrom(String fingerprint) {
    switch (quickSaveMode) {
      case 'all':
        return true;
      case 'favorites':
        return favoriteNames.containsKey(fingerprint);
      default:
        return false;
    }
  }

  Future<void> setQuickSaveMode(String mode) async {
    quickSaveMode = mode;
    // Eski alanla uyumluluk: 'off' → onay iste.
    await prefs.setString(_kQuickSave, mode);
    await prefs.setBool(_kRequireApproval, mode == 'off');
    notifyListeners();
  }

  bool isFavorite(String fingerprint) =>
      favoriteNames.containsKey(fingerprint);

  String? favoriteName(String fingerprint) => favoriteNames[fingerprint];

  /// [fallbackName], ad verilmediğinde kullanılır — UI katmanından i18n ile
  /// geçilir (D-07: çekirdek içinde sabit Türkçe metin tutulmaz).
  Future<void> setFavorite(String fingerprint, bool favorite,
      {String? name, String fallbackName = 'Favorite'}) async {
    if (favorite) {
      favoriteNames[fingerprint] =
          (name != null && name.trim().isNotEmpty) ? name.trim() : fallbackName;
    } else {
      favoriteNames.remove(fingerprint);
    }
    await _persistFavorites();
    notifyListeners();
  }

  Future<void> renameFavorite(String fingerprint, String name,
      {String fallbackName = 'Favorite'}) async {
    if (!favoriteNames.containsKey(fingerprint)) return;
    favoriteNames[fingerprint] =
        name.trim().isEmpty ? fallbackName : name.trim();
    await _persistFavorites();
    notifyListeners();
  }

  Future<void> _persistFavorites() async {
    await prefs.setString(_kFavorites, jsonEncode(favoriteNames));
  }

  /// R-3: güven/favori kayıtları kimlikten parmak izine taşındı; eski
  /// kimlik tabanlı kayıtlar sessizce düşer. Eski biçimde kayıt kalmışsa
  /// kullanıcıya bir kez bilgi verilir.
  bool get needsTrustMigrationNotice {
    if (prefs.getBool(_kTrustNoticeShown) ?? false) return false;
    final legacyTrusted = prefs.get('settings.trusted');
    final fav = prefs.get(_kFavorites);
    final legacyFavorites = fav is String &&
        fav.isNotEmpty &&
        !fav.trim().startsWith('{');
    return legacyTrusted != null || legacyFavorites;
  }

  Future<void> markTrustMigrationNoticeShown() async {
    await prefs.setBool(_kTrustNoticeShown, true);
  }

  static Map<String, String> _decodeFavorites(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry('$k', '$v'));
      }
    } catch (_) {}
    return {};
  }

  Future<void> setSaveDir(String value) async {
    saveDir = value;
    await prefs.setString(_kSaveDir, value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    await prefs.setInt(_kThemeMode, value.index);
    notifyListeners();
  }

  Future<void> setAccentIndex(int value) async {
    accentIndex = value;
    await prefs.setInt(_kAccent, value);
    notifyListeners();
  }

  Future<void> setRequireApproval(bool value) async {
    await setQuickSaveMode(value ? 'off' : 'all');
  }

  /// PIN'i güvenli kasadan yükler (uygulama başlangıcında çağrılır).
  ///
  /// R-2: bu yöntem [TransferService.start] içinde de savunma amaçlı
  /// çağrılır; böylece PIN'i yüklenmeden istek kabul edilmez.
  Future<void> loadSecrets() async {
    final store = secrets;
    if (store == null) return;
    final value = await store.read(_kPin);
    pin = (value == null || value.isEmpty) ? null : value;
    final webValue = await store.read(_kWebPin);
    webPin = (webValue == null || webValue.isEmpty) ? null : webValue;
    notifyListeners();
  }

  Future<void> setPin(String? value) async {
    pin = (value == null || value.isEmpty) ? null : value;
    final store = secrets;
    if (store != null) {
      if (pin == null) {
        await store.delete(_kPin);
      } else {
        await store.write(_kPin, pin!);
      }
      notifyListeners();
      return;
    }
    if (pin == null) {
      await prefs.remove(_kPin);
    } else {
      await prefs.setString(_kPin, pin!);
    }
    notifyListeners();
  }

  /// W-04: web PIN'i güvenli kasada saklar (R-2 ile aynı disiplin).
  Future<void> setWebPin(String? value) async {
    webPin = (value == null || value.isEmpty) ? null : value;
    final store = secrets;
    if (store != null) {
      if (webPin == null) {
        await store.delete(_kWebPin);
      } else {
        await store.write(_kWebPin, webPin!);
      }
      notifyListeners();
      return;
    }
    if (webPin == null) {
      await prefs.remove(_kWebPin);
    } else {
      await prefs.setString(_kWebPin, webPin!);
    }
    notifyListeners();
  }

  /// W-01: web sunucu portu.
  Future<void> setWebPort(int value) async {
    webPort = value;
    await prefs.setInt(_kWebPort, value);
    notifyListeners();
  }

  /// W-05: HTTPS sertifika/anahtar yolları (boş = düz HTTP).
  Future<void> setWebTls({String? cert, String? key}) async {
    if (cert != null) {
      webTlsCert = cert;
      await prefs.setString(_kWebTlsCert, cert);
    }
    if (key != null) {
      webTlsKey = key;
      await prefs.setString(_kWebTlsKey, key);
    }
    notifyListeners();
  }

  /// TOFU: bilinen parmak izi (cihaz kimliğine göre).
  String? knownFingerprintFor(String deviceId) => knownPeers[deviceId];

  /// İlk karşılaşımda parmak izini kaydeder.
  Future<void> rememberPeer(String deviceId, String fingerprint) async {
    if (knownPeers[deviceId] == fingerprint) return;
    knownPeers[deviceId] = fingerprint;
    await prefs.setString(_kKnownPeers, jsonEncode(knownPeers));
  }

  /// Parmak izi bilinen kayıttan farklı mı? (taklit / MITM uyarısı)
  bool fingerprintChanged(String deviceId, String fingerprint) {
    final known = knownPeers[deviceId];
    return known != null && known.isNotEmpty && known != fingerprint;
  }

  bool isTrusted(String fingerprint) =>
      trustedFingerprints.contains(fingerprint);

  Future<void> setTrusted(String fingerprint, bool trusted) async {
    if (trusted && !trustedFingerprints.contains(fingerprint)) {
      trustedFingerprints.add(fingerprint);
    } else if (!trusted) {
      trustedFingerprints.remove(fingerprint);
    }
    await prefs.setStringList(_kTrusted, trustedFingerprints);
    notifyListeners();
  }

  /// R-1: parmak izi karşılaştırmasıyla doğrulanmış mı?
  bool isVerified(String fingerprint) =>
      verifiedFingerprints.contains(fingerprint);

  /// R-1: parmak izi doğrulamasını kaydeder/kaldırır. Doğrulama, kullanıcının
  /// karşı cihazın ekranındaki izle birebir karşılaştırma yapmasıyla verilir.
  Future<void> setVerified(String fingerprint, bool verified) async {
    if (verified && !verifiedFingerprints.contains(fingerprint)) {
      verifiedFingerprints.add(fingerprint);
    } else if (!verified) {
      verifiedFingerprints.remove(fingerprint);
    }
    await prefs.setStringList(_kVerified, verifiedFingerprints);
    notifyListeners();
  }

  Future<void> setTransferPort(int value) async {
    transferPort = value;
    await prefs.setInt(_kTransferPort, value);
    notifyListeners();
  }

  Future<void> setDiscoveryOn(bool value) async {
    discoveryOn = value;
    await prefs.setBool(_kDiscoveryOn, value);
    notifyListeners();
  }

  Future<void> setLocaleCode(String value) async {
    localeCode = value;
    await prefs.setString(_kLocale, value);
    notifyListeners();
  }
}
