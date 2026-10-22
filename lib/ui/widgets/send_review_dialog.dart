import 'package:flutter/material.dart';

import '../../core/models/send_selection.dart';
import '../../core/utils/format.dart';
import '../strings.dart';

/// Gönderim öncesi seçilen öğeleri listeleyen, çıkarmaya izin veren diyalog.
class SendReviewDialog extends StatefulWidget {
  final List<SendSelection> initial;

  const SendReviewDialog({super.key, required this.initial});

  /// Sonuç: kullanıcı onaylarsa temizlenmiş seçim listesi döner.
  static Future<List<SendSelection>?> show(
    BuildContext context,
    List<SendSelection> selections,
  ) {
    return showDialog<List<SendSelection>>(
      context: context,
      builder: (_) => SendReviewDialog(initial: selections),
    );
  }

  @override
  State<SendReviewDialog> createState() => _SendReviewDialogState();
}

class _SendReviewDialogState extends State<SendReviewDialog> {
  late final List<SendSelection> _items = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final totalSize = _items.fold<int>(0, (sum, i) => sum + i.size);

    return AlertDialog(
      title: Text('${s.t('reviewTitle')} (${_items.length} ${s.t('items')})'),
      content: SizedBox(
        width: 420,
        child: _items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.t('emptySelection'),
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.t('reviewHint'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            item.isDirectory
                                ? Icons.folder_rounded
                                : Icons.insert_drive_file_outlined,
                            color: item.isDirectory
                                ? Colors.amber.shade700
                                : scheme.primary,
                          ),
                          title: Text(
                            item.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(formatBytes(item.size)),
                          trailing: IconButton(
                            tooltip: s.t('removeItem'),
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () =>
                                setState(() => _items.removeAt(index)),
                          ),
                        );
                      },
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
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: _items.isEmpty
              ? null
              : () => Navigator.of(context).pop(_items),
          child: Text(s.t('sendAction')),
        ),
      ],
    );
  }
}

/// Hedef cihaz seçimi — tekli veya çoklu.
class DevicePickerDialog extends StatefulWidget {
  final List<DeviceChoice> devices;
  final bool multi;

  const DevicePickerDialog({
    super.key,
    required this.devices,
    required this.multi,
  });

  static Future<List<DeviceChoice>?> show(
    BuildContext context,
    List<DeviceChoice> devices, {
    required bool multi,
  }) {
    return showDialog<List<DeviceChoice>>(
      context: context,
      builder: (_) => DevicePickerDialog(devices: devices, multi: multi),
    );
  }

  @override
  State<DevicePickerDialog> createState() => _DevicePickerDialogState();
}

/// Seçilebilir cihaz satırı.
class DeviceChoice {
  final String id;
  final String name;
  final String subtitle;
  bool selected;

  DeviceChoice({
    required this.id,
    required this.name,
    required this.subtitle,
    this.selected = false,
  });
}

class _DevicePickerDialogState extends State<DevicePickerDialog> {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final anySelected = widget.devices.any((d) => d.selected);

    return AlertDialog(
      title: Text(widget.multi ? s.t('multiSelect') : s.t('pickDevice')),
      content: SizedBox(
        width: 420,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.devices.length,
          itemBuilder: (context, index) {
            final device = widget.devices[index];
            return ListTile(
              leading: widget.multi
                  ? Checkbox(
                      value: device.selected,
                      onChanged: (v) => setState(
                          () => device.selected = v ?? false),
                    )
                  : const Icon(Icons.devices_rounded),
              title: Text(device.name),
              subtitle: Text(device.subtitle),
              onTap: widget.multi
                  ? () => setState(() => device.selected = !device.selected)
                  : () => Navigator.of(context).pop([device]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.t('cancel')),
        ),
        if (widget.multi)
          FilledButton(
            onPressed: anySelected
                ? () => Navigator.of(context).pop([
                      for (final d in widget.devices)
                        if (d.selected) d,
                    ])
                : null,
            child: Text(s.t('sendAction')),
          ),
      ],
    );
  }
}
