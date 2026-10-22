import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/identity_service.dart';
import '../../core/services/settings_service.dart';
import '../strings.dart';

/// Kendi bağlantı QR'ımızı gösteren panel.
///
/// Dar ekranlarda alt sayfa (bottom sheet), geniş ekranlarda ortalanmış
/// diyalog olarak açılır. İçerik taşması olmaması için kaydırılabilirdir.
class QrPanel extends StatelessWidget {
  final IdentityService identity;
  final SettingsService settings;

  const QrPanel({super.key, required this.identity, required this.settings});

  /// Uygun pencere türüne göre açar.
  static Future<void> show(BuildContext context) {
    final settings = context.read<SettingsService>();
    final identity = context.read<IdentityService>();
    final panel = QrPanel(identity: identity, settings: settings);
    final wide = MediaQuery.sizeOf(context).width >= 700;

    if (wide) {
      return showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: panel,
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(child: panel),
    );
  }

  Future<String> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<String>(
      future: _localIp(),
      builder: (context, snapshot) {
        final data = jsonEncode({
          'n': identity.alias,
          'a': snapshot.data ?? '127.0.0.1',
          'p': settings.transferPort,
          'f': identity.fingerprint,
        });
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SendLyraQrHeader(alias: identity.alias, fingerprint: identity.fingerprint),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: data,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${snapshot.data ?? ''}:${settings.transferPort}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontFeatures: const []),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(s.t('close')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// QR başlığı: ad + parmak izi.
class SendLyraQrHeader extends StatelessWidget {
  final String alias;
  final String fingerprint;

  const SendLyraQrHeader({
    super.key,
    required this.alias,
    required this.fingerprint,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          alias,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '${s.t('fingerprint')}: $fingerprint',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}
