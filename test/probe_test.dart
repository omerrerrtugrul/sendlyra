import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/services/identity_service.dart';
import 'package:sendlyra/core/services/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('probe: SecretStore.read tamamlanır', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SecretStore(prefs);
    final value = await store
        .read('probe-key')
        .timeout(const Duration(seconds: 5), onTimeout: () => 'TIMEOUT');
    expect(value, isNull);
  });

  testWidgets('probe: IdentityService.load tamamlanır', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final identity = await IdentityService.load(prefs)
        .timeout(const Duration(seconds: 5), onTimeout: () => throw 'TIMEOUT');
    expect(identity.fingerprint, isNotEmpty);
  });
}
