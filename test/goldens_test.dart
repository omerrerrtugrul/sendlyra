import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sendlyra/app.dart';
import 'package:sendlyra/core/services/history_service.dart';
import 'package:sendlyra/core/services/identity_service.dart';
import 'package:sendlyra/core/services/settings_service.dart';
import 'package:sendlyra/core/services/share_intent_service.dart';
import 'package:sendlyra/core/services/transfer_service.dart';
import 'package:sendlyra/core/services/web_share_service.dart';
import 'helpers/fake_secret_store.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<TransferService> pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  // A-1: flutter_secure_storage test bağlamında (FakeAsync) askıda kalır —
  // widget testlerinde FakeSecretStore kullanılır.
  final identity =
      await IdentityService.load(prefs, secrets: FakeSecretStore(prefs));
  final settings = SettingsService(prefs);
  final history = HistoryService(prefs);
  final transfer = TransferService(
    identity: identity,
    settings: settings,
    history: history,
  );
  final webShare = WebShareService(settings: settings, history: history);
  await tester.pumpWidget(SendLyraApp(
    identity: identity,
    settings: settings,
    history: history,
    transfer: transfer,
    webShare: webShare,
    shareIntent: ShareIntentService(),
  ));
  await settle(tester);
  return transfer;
}

void main() {
  testWidgets('golden: cihazlar sayfası', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/devices.png'),
    );
  });

  testWidgets('golden: transferler sayfası', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    await tester.tap(find.text('Transferler').first);
    await settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/transfers.png'),
    );
  });

  testWidgets('golden: ayarlar sayfası', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    await tester.tap(find.text('Ayarlar').first);
    await settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings.png'),
    );
  });

  testWidgets('QR diyaloğu taşmasız açılır', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    await tester.tap(find.byTooltip('Bağlantı QR kodumu göster'));
    await settle(tester);
    await settle(tester);
    // IP FutureBuilder'ı golden karşılaştırmasını kararsız yapar;
    // bu yüzden yalnızca taşma/istisna kontrolü yapılır.
    expect(find.textContaining('OVERFLOWED'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
