import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/settings_service.dart';
import '../../core/services/transfer_service.dart';
import '../../core/utils/format.dart';
import '../strings.dart';

/// Gelen aktarım teklifi için onay diyaloğu.
class IncomingRequestDialog extends StatefulWidget {
  final IncomingRequest request;

  const IncomingRequestDialog({super.key, required this.request});

  static Future<void> show(BuildContext context, IncomingRequest request) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncomingRequestDialog(request: request),
    );
  }

  @override
  State<IncomingRequestDialog> createState() => _IncomingRequestDialogState();
}

class _IncomingRequestDialogState extends State<IncomingRequestDialog> {
  bool _trust = false;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final offer = widget.request.offer;
    final peer = widget.request.peer;
    final totalSize = offer.files.fold<int>(0, (sum, f) => sum + f.size);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Row(
        children: [
          Icon(Icons.downloading_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(s.t('incomingTitle'))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offer.text != null
                ? '${peer.name} ${s.t('incomingText')}'
                : '${peer.name} ${s.t('incomingWants')}:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (offer.text != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(offer.text!),
                    ),
                  for (final f in offer.files)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.insert_drive_file_outlined,
                          color: scheme.primary),
                      title: Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(formatBytes(f.size)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${s.t('total')}: ${formatBytes(totalSize)}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _trust,
            onChanged: (v) => setState(() => _trust = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              s.t('trustDevice'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.request.reject();
            Navigator.of(context).pop();
          },
          child: Text(s.t('reject')),
        ),
        FilledButton(
          onPressed: () {
            if (_trust) {
              // Güven kaydı her zaman doğrulanmış parmak izine bağlanır.
              context
                  .read<SettingsService>()
                  .setTrusted(widget.request.peer.fingerprint, true);
            }
            widget.request.accept();
            Navigator.of(context).pop();
          },
          child: Text(s.t('accept')),
        ),
      ],
    );
  }
}
