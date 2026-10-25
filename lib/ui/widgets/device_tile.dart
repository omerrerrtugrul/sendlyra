import 'package:flutter/material.dart';

import '../../core/models/device.dart';
import '../../core/utils/format.dart';
import '../strings.dart';

/// Ağda bulunan bir cihazı temsil eden satır.
class DeviceTile extends StatelessWidget {
  final LyraDevice device;
  final String? displayName;
  final bool isFavorite;
  final bool isVerified;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onRenameFavorite;
  final VoidCallback? onSendFiles;
  final VoidCallback? onSendText;
  final VoidCallback? onSendClipboard;
  final VoidCallback? onInfo;
  final VoidCallback? onVerify;

  const DeviceTile({
    super.key,
    required this.device,
    this.displayName,
    this.isFavorite = false,
    this.isVerified = false,
    this.onToggleFavorite,
    this.onRenameFavorite,
    this.onSendFiles,
    this.onSendText,
    this.onSendClipboard,
    this.onInfo,
    this.onVerify,
  });

  IconData get _icon {
    if (device.deviceType == 'mobile') return Icons.smartphone_rounded;
    if (device.os.contains('mac')) return Icons.laptop_mac_rounded;
    if (device.os.contains('win')) return Icons.desktop_windows_rounded;
    return Icons.computer_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final title = displayName ?? device.name;

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor:
              isFavorite ? Colors.amber.withValues(alpha: 0.2) : scheme.primaryContainer,
          child: Icon(
            _icon,
            color: isFavorite ? Colors.amber.shade800 : scheme.onPrimaryContainer,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (isFavorite) ...[
              const SizedBox(width: 6),
              Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade700),
            ],
            if (isVerified) ...[
              const SizedBox(width: 6),
              Icon(Icons.verified_rounded,
                  size: 18, color: scheme.primary),
            ],
          ],
        ),
        subtitle: Text(
          '${device.busy ? '[${s.t('busy')}] ' : ''}'
          '${isFavorite
              ? '${device.name} · ${fingerprintShort(device.fingerprint)}'
              : '${fingerprintShort(device.fingerprint)}  ·  ${s.t('lastSeen')}: ${timeAgo(device.lastSeen, locale: s.locale)}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onVerify != null)
              IconButton(
                tooltip: isVerified
                    ? s.t('verifyBadge')
                    : s.t('verifyTitle'),
                onPressed: onVerify,
                icon: Icon(
                  isVerified
                      ? Icons.verified_rounded
                      : Icons.verified_outlined,
                  size: 22,
                  color: isVerified ? scheme.primary : null,
                ),
              ),
            if (onToggleFavorite != null)
              IconButton(
                tooltip: isFavorite
                    ? s.t('favoriteRemove')
                    : s.t('favoriteAdd'),
                onPressed: onToggleFavorite,
                icon: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFavorite ? Colors.amber.shade700 : null,
                ),
              ),
            if (isFavorite && onRenameFavorite != null)
              IconButton(
                tooltip: s.t('favoriteName'),
                onPressed: onRenameFavorite,
                icon: const Icon(Icons.edit_rounded, size: 20),
              ),
            IconButton.filledTonal(
              tooltip: s.t('sendFiles'),
              onPressed: onSendFiles,
              icon: const Icon(Icons.file_upload_outlined),
            ),
            IconButton.outlined(
              tooltip: s.t('sendText'),
              onPressed: onSendText,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            if (onInfo != null || onSendClipboard != null)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'info') onInfo?.call();
                  if (v == 'clipboard') onSendClipboard?.call();
                },
                itemBuilder: (_) => [
                  if (onSendClipboard != null)
                    PopupMenuItem(
                      value: 'clipboard',
                      child: Text(s.t('sendClipboard')),
                    ),
                  if (onInfo != null)
                    PopupMenuItem(
                      value: 'info',
                      child: Text(s.t('fingerprint')),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
