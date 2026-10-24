import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/services/history_service.dart';
import 'core/services/identity_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/transfer_service.dart';
import 'core/services/web_share_service.dart';
import 'ui/screens/shell.dart';
import 'ui/theme.dart';

/// Uygulama kökü: servisleri sağlar, temayı ve dili yönetir.
class SendLyraApp extends StatelessWidget {
  final IdentityService identity;
  final SettingsService settings;
  final HistoryService history;
  final TransferService transfer;
  final WebShareService webShare;
  final String? startupError;

  const SendLyraApp({
    super.key,
    required this.identity,
    required this.settings,
    required this.history,
    required this.transfer,
    required this.webShare,
    this.startupError,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<IdentityService>.value(value: identity),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<TransferService>.value(value: transfer),
        ChangeNotifierProvider<HistoryService>.value(value: history),
        ChangeNotifierProvider<WebShareService>.value(value: webShare),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settingsService, _) {
          final accent = SendLyraTheme.accent(settingsService.accentIndex);
          return MaterialApp(
            title: 'SendLyra',
            debugShowCheckedModeBanner: false,
            theme: SendLyraTheme.light(accent),
            darkTheme: SendLyraTheme.dark(accent),
            themeMode: settingsService.themeMode,
            locale: Locale(settingsService.localeCode),
            home: ShellScreen(startupError: startupError),
          );
        },
      ),
    );
  }
}
