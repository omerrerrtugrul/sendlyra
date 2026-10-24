import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gizli değerlerin (özel anahtar, PIN) güvenli saklanması.
///
/// Platform kasası (Keychain / Keystore / Credential Manager) kullanılır.
/// Kasaya erişilemeyen ortamlarda (ör. libsecret olmayan Linux, testler)
/// sessizce `SharedPreferences`'a düşer; hiçbir durumda uygulama kırılmaz.
///
/// Geçiş (migrasyon): eski düz metin kopya okuma sırasında otomatik olarak
/// kasaya taşınır ve `SharedPreferences`'tan silinir.
class SecretStore {
  static const FlutterSecureStorage _secure =
      FlutterSecureStorage();

  final SharedPreferences prefs;

  /// Güvenli kasa kullanılabilir mi? İlk hatadan sonra kalıcı olarak kapanır.
  bool _secureAvailable = true;

  bool get secureAvailable => _secureAvailable;

  SecretStore(this.prefs);

  /// Değeri okur: önce kasa, sonra (eski/yerleşik) düz metin kopya.
  ///
  /// Geçiş: düz metin kopya bulunursa kasa çalışıyorsa otomatik olarak
  /// kasaya taşınır ve `SharedPreferences`'tan silinir (dokümandaki
  /// migrasyon sözü — R-2 incelemesinde gerçek davranışla eşitlendi).
  Future<String?> read(String key) async {
    if (_secureAvailable) {
      try {
        final value = await _secure.read(key: key);
        if (value != null) return value;
      } catch (_) {
        _secureAvailable = false;
      }
    }
    final legacy = prefs.getString(key);
    if (legacy != null && legacy.isNotEmpty && _secureAvailable) {
      try {
        await _secure.write(key: key, value: legacy);
        await prefs.remove(key);
      } catch (_) {
        _secureAvailable = false;
      }
    }
    return legacy;
  }

  /// Değeri yazar. Kasa çalışıyorsa düz metin kopya silinir (geçiş dahil).
  Future<void> write(String key, String value) async {
    if (_secureAvailable) {
      try {
        await _secure.write(key: key, value: value);
        await prefs.remove(key);
        return;
      } catch (_) {
        _secureAvailable = false;
      }
    }
    await prefs.setString(key, value);
  }

  /// Değeri siler (her iki kaynaktan).
  Future<void> delete(String key) async {
    if (_secureAvailable) {
      try {
        await _secure.delete(key: key);
      } catch (_) {
        _secureAvailable = false;
      }
    }
    await prefs.remove(key);
  }
}
