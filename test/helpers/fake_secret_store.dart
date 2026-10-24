import 'package:sendlyra/core/services/secret_store.dart';

/// Test ortamı için güvenli kasa taklidi.
///
/// `flutter_secure_storage` platform kanalları test bağlamında
/// (FakeAsync) askıda kalabilir; bu sınıf tamamen `SharedPreferences`
/// üzerinden çalışarak testleri deterministik ve hızlı tutar.
class FakeSecretStore extends SecretStore {
  FakeSecretStore(super.prefs);

  @override
  bool get secureAvailable => false;

  @override
  Future<String?> read(String key) async => prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await prefs.remove(key);
  }
}
