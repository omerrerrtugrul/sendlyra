import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/history_service.dart';
import 'core/services/identity_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/secret_store.dart';
import 'core/services/settings_service.dart';
import 'core/services/transfer_service.dart';
import 'core/services/web_share_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final prefs = await SharedPreferences.getInstance();
    final secrets = SecretStore(prefs);
    final identity = await IdentityService.load(prefs, secrets: secrets);
    final settings = SettingsService(prefs, secrets: secrets);
    await settings.loadSecrets();
    final history = HistoryService(prefs);
    // E-03: transfer sonucu bildirimleri.
    final notifier =
        LocalTransferNotifier(locale: () => settings.localeCode);
    final transfer = TransferService(
      identity: identity,
      settings: settings,
      history: history,
      notifier: notifier,
    );
    // W-01: web paylaşım sunucusu (kullanıcı açana kadar çalışmaz).
    final webShare = WebShareService(
      settings: settings,
      history: history,
      saveDirResolver: transfer.resolveSaveDir,
    );

    String? startupError;
    try {
      await transfer.start();
    } catch (e) {
      // Ağ servisleri başlatılamasa bile uygulama açılmalı.
      startupError = '$e';
    }

    runApp(SendLyraApp(
      identity: identity,
      settings: settings,
      history: history,
      transfer: transfer,
      webShare: webShare,
      startupError: startupError,
    ));
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('SendLyra başlatılamadı:\n$e',
                textAlign: TextAlign.center),
          ),
        ),
      ),
    ));
  }
}
