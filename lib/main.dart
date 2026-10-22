import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/history_service.dart';
import 'core/services/identity_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/transfer_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final prefs = await SharedPreferences.getInstance();
    final identity = await IdentityService.load(prefs);
    final settings = SettingsService(prefs);
    final history = HistoryService(prefs);
    final transfer = TransferService(
      identity: identity,
      settings: settings,
      history: history,
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
