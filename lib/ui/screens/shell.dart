import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/identity_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/transfer_service.dart';
import '../logo.dart';
import '../strings.dart';
import '../widgets/incoming_request_dialog.dart';
import '../widgets/qr_sheet.dart';
import 'devices_page.dart';
import 'settings_page.dart';
import 'transfers_page.dart';

/// Uygulama kabuğu: sekme navigasyonu + gelen tekliflerin yönetimi.
class ShellScreen extends StatefulWidget {
  final String? startupError;

  const ShellScreen({super.key, this.startupError});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;
  StreamSubscription<IncomingRequest>? _incomingSub;

  @override
  void initState() {
    super.initState();
    _incomingSub =
        context.read<TransferService>().incomingRequests.listen(_onIncoming);
    if (widget.startupError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final s = AppStrings.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${s.t('startupError')}: ${widget.startupError}')),
        );
      });
    }
    // R-3: güven/favori kayıtları parmak izine taşındıysa bir kez bilgi ver.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final settings = context.read<SettingsService>();
      if (!settings.needsTrustMigrationNotice) return;
      final s = AppStrings.of(context);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.t('trustMigrationTitle')),
          content: Text(s.t('trustMigrationBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(s.t('ok')),
            ),
          ],
        ),
      );
      await settings.markTrustMigrationNoticeShown();
    });
  }

  void _onIncoming(IncomingRequest request) {
    if (!mounted) return;
    IncomingRequestDialog.show(context, request);
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final identity = context.watch<IdentityService>();
    final settings = context.watch<SettingsService>();
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final pages = [
      DevicesPage(onGoToTransfers: () => setState(() => _index = 1)),
      const TransfersPage(),
      const SettingsPage(),
    ];

    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SendLyraWordmark(),
        const SizedBox(width: 12),
        Flexible(
          child: Tooltip(
            message: identity.alias,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .secondaryContainer
                    .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                identity.alias,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: title,
        actions: [
          // Keşif durumu rozeti
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (settings.discoveryOn ? Colors.green : Colors.orange)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  settings.discoveryOn
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_off_rounded,
                  size: 16,
                  color: settings.discoveryOn
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
                const SizedBox(width: 6),
                Text(
                  settings.discoveryOn ? s.t('discoveryOn') : s.t('discoveryOff'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          Tooltip(
            message: s.t('tooltipQr'),
            child: IconButton(
              onPressed: () => QrPanel.show(context),
              icon: const Icon(Icons.qr_code_2_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              minWidth: 96,
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.devices_rounded),
                  label: Text(s.t('tabDevices')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.swap_vert_rounded),
                  label: Text(s.t('tabTransfers')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.settings_rounded),
                  label: Text(s.t('tabSettings')),
                ),
              ],
            ),
          if (wide)
            VerticalDivider(
              width: 1,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.5),
            ),
          Expanded(
            child: IndexedStack(index: _index, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.devices_rounded),
                  label: s.t('tabDevices'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.swap_vert_rounded),
                  label: s.t('tabTransfers'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_rounded),
                  label: s.t('tabSettings'),
                ),
              ],
            ),
    );
  }
}
