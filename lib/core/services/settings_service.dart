import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama ayarları (kalıcı).
class SettingsService extends ChangeNotifier {
  static const _kSaveDir = 'settings.saveDir';
  static const _kThemeMode = 'settings.themeMode';
  static const _kAccent = 'settings.accent';
  static const _kRequireApproval = 'settings.requireApproval';
  static const _kPin = 'settings.pin';
  static const _kTrusted = 'settings.trustedFps';
  static const _kQuickSave = 'settings.quickSave';
  static const _kFavorites = 'settings.favorites';
  static const _kKnownPeers = 'settings.knownPeers';
  static const _kTransferPort = 'settings.transferPort';
  static const _kDiscoveryOn = 'settings.discoveryOn';
  static const _kLocale = 'settings.locale';

  final SharedPreferences prefs;

  late String saveDir;
  late ThemeMode themeMode;
  late int accentIndex;
  late bool requireApproval;
  /// 'off' = onay iste, 'all' = herkesten otomatik kabul,
  /// 'favorites' = yalnızca favorilerden otomatik kabul.
  late String quickSaveMode;
  late String? pin;

  /// Güvenilir cihazlar — her zaman **doğrulanmış parmak izine** bağlıdır;
  /// karşı tarafın beyan ettiği kimliğe değil (taklit engeli).
  late List<String> trustedFingerprints;

  /// Favoriler — anahtar: parmak izi, değer: özel ad.
  late Map<String, String> favoriteNames;

  /// TOFU: cihaz kimliği → ilk karşılaşımda görülen parmak izi.
  /// Sonraki bağlantıda iz değişirse bağlantı reddedilir.
  late Map<String, String> knownPeers;

  late int transferPort;
  late bool discoveryOn;
  late String localeCode;

  SettingsService(this.prefs) {
    saveDir = prefs.getString(_kSaveDir) ?? '';
    themeMode = ThemeMode
        .values[prefs.getInt(_kThemeMode) ?? ThemeMode.system.index];
    accentIndex = prefs.getInt(_kAccent) ?? 0;
    requireApproval = prefs.getBool(_kRequireApproval) ?? true;
    quickSaveMode = prefs.getString(_kQuickSave) ??
        (requireApproval ? 'off' : 'all');
    pin = prefs.getString(_kPin);
    trustedFingerprints = prefs.getStringList(_kTrusted) ?? [];
    favoriteNames = _decodeFavorites(prefs.getString(_kFavorites));
    knownPeers = _decodeFavorites(prefs.getString(_kKnownPeers));
    transferPort = prefs.getInt(_kTransferPort) ?? 47802;
    discoveryOn = prefs.getBool(_kDiscoveryOn) ?? true;
    localeCode = prefs.getString(_kLocale) ?? 'tr';
  }

  bool get hasPin => pin != null && pin!.isNotEmpty;

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
    requireApproval = mode == 'off';
    await prefs.setString(_kQuickSave, mode);
    await prefs.setBool(_kRequireApproval, requireApproval);
    notifyListeners();
  }

  bool isFavorite(String fingerprint) =>
      favoriteNames.containsKey(fingerprint);

  String? favoriteName(String fingerprint) => favoriteNames[fingerprint];

  Future<void> setFavorite(String fingerprint, bool favorite,
      {String? name}) async {
    if (favorite) {
      favoriteNames[fingerprint] =
          (name != null && name.trim().isNotEmpty) ? name.trim() : 'Favori';
    } else {
      favoriteNames.remove(fingerprint);
    }
    await _persistFavorites();
    notifyListeners();
  }

  Future<void> renameFavorite(String fingerprint, String name) async {
    if (!favoriteNames.containsKey(fingerprint)) return;
    favoriteNames[fingerprint] =
        name.trim().isEmpty ? 'Favori' : name.trim();
    await _persistFavorites();
    notifyListeners();
  }

  Future<void> _persistFavorites() async {
    await prefs.setString(_kFavorites, jsonEncode(favoriteNames));
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
    requireApproval = value;
    await prefs.setBool(_kRequireApproval, value);
    notifyListeners();
  }

  Future<void> setPin(String? value) async {
    pin = (value == null || value.isEmpty) ? null : value;
    if (pin == null) {
      await prefs.remove(_kPin);
    } else {
      await prefs.setString(_kPin, pin!);
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
