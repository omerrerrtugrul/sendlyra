import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/services/identity_service.dart';
import 'package:sendlyra/core/services/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A-1 kök neden kaydı: `flutter_secure_storage` platform kanalı,
/// `testWidgets` içindeki sahte zaman (FakeAsync) diliminde asla
/// tamamlanmaz — bu yüzden widget testlerinde `FakeSecretStore`
/// (test/helpers/fake_secret_store.dart) kullanılır.
///
/// Bu testler GERÇEK asenkron zamanla (`test()`) çalışır ve kasa
/// erişilemeyen ortamdaki yedek akışın (SharedPreferences) sorunsuz
/// tamamlandığını doğrular.
void main() {
  test('SecretStore.read gerçek asenkronda tamamlanır', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SecretStore(prefs);
    final value = await store.read('probe-key');
    expect(value, isNull);
  });

  test('IdentityService.load gerçek asenkronda tamamlanır', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final identity = await IdentityService.load(prefs);
    expect(identity.fingerprint, isNotEmpty);
  });
}
