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

/// Sonsuz (repeat) animasyonlar nedeniyle `pumpAndSettle` kullanılmaz;
/// bunun yerine sınırlı sayıda kare pompalanır.
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
  testWidgets('uygulama açılır ve dört sekme görünür', (tester) async {
    await pumpApp(tester);
    expect(find.text('Cihazlar'), findsWidgets);
    expect(find.text('Transferler'), findsWidgets);
    expect(find.text('Web'), findsWidgets);
    expect(find.text('Ayarlar'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IP ile bağlan butonu diyalog açar (Provider hatası yok)',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('IP ile bağlan'));
    await settle(tester);
    expect(find.text('Doğrudan bağlantı'), findsOneWidget);
    expect(find.widgetWithText(TextField, '192.168.1.24'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kendi cihaz adı düzenleme diyalogu açılır', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Adı düzenle').first);
    await settle(tester);
    expect(find.text('Adı düzenle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('QR butonu diyalog açar ve içerik taşmaz', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    await tester.tap(find.byTooltip('Bağlantı QR kodumu göster'));
    await settle(tester);
    expect(find.text('Kapat'), findsOneWidget);
    // Taşma hatası olmamalı
    expect(find.textContaining('OVERFLOWED'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sekmeler arasında geçiş çalışır', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Transferler').first);
    await settle(tester);
    expect(find.text('Aktif transferler'), findsOneWidget);

    await tester.tap(find.text('Ayarlar').first);
    await settle(tester);
    expect(find.text('GENEL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hızlı kaydetme kipi değiştirilebilir', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Ayarlar').first);
    await settle(tester);

    await tester.ensureVisible(find.text('Hepsini otomatik kabul et'));
    await settle(tester);
    await tester.tap(find.text('Hepsini otomatik kabul et'));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIN ayarlama akışı çalışır', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Ayarlar').first);
    await settle(tester);

    await tester.ensureVisible(find.text('PIN belirle'));
    await settle(tester);
    await tester.tap(find.text('PIN belirle'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.tap(find.text('Tamam'));
    await settle(tester);
    expect(find.text('PIN kaldır'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tema ve dil değişimi uygulanır', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Ayarlar').first);
    await settle(tester);

    await tester.ensureVisible(find.text('Koyu'));
    await settle(tester);
    await tester.tap(find.text('Koyu'));
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Türkçe'), 250);
    await settle(tester);
    await tester.tap(find.text('Türkçe').first);
    await settle(tester);
    await tester.tap(find.text('English').last);
    await settle(tester);
    // Kaydırma sonrası görünür alandaki çevrilmiş metin:
    expect(find.text('Language'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
