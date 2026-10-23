import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/device.dart';
import '../../core/models/send_selection.dart';
import '../../core/models/transfer_job.dart';
import '../../core/services/identity_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/transfer_service.dart';
import '../../core/utils/format.dart';
import '../logo.dart';
import '../strings.dart';
import '../widgets/device_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/send_review_dialog.dart';

/// Keşfedilen cihazlar, kendi cihaz kartı ve gönderim akışları.
class DevicesPage extends StatefulWidget {
  final VoidCallback? onGoToTransfers;

  const DevicesPage({super.key, this.onGoToTransfers});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  bool _dragging = false;

  // ---------- Gönderim akışı ----------

  Future<void> _startSendFlow({List<SendSelection>? preset}) async {
    var selections = preset ?? await _pickSelections();
    if (selections == null || selections.isEmpty) return;

    if (!mounted) return;
    selections = await SendReviewDialog.show(context, selections);
    if (selections == null || selections.isEmpty) return;

    if (!mounted) return;
    final transfer = context.read<TransferService>();
    final settings = context.read<SettingsService>();
    final devices = transfer.devices;
    if (devices.isEmpty) {
      await _manualConnect();
      return;
    }

    final choices = [
      for (final d in devices)
        DeviceChoice(
          id: d.id,
          name: settings.isFavorite(d.fingerprint)
              ? '${settings.favoriteName(d.fingerprint) ?? d.name} · ${d.name}'
              : d.name,
          subtitle: '${d.address}:${d.port}',
        ),
    ];

    if (!mounted) return;
    final picked = await DevicePickerDialog.show(context, choices,
        multi: true);
    if (picked == null || picked.isEmpty) return;

    final entries = expandSelections(selections);
    if (entries.isEmpty) return;

    final byId = {for (final d in devices) d.id: d};
    for (final choice in picked) {
      final device = byId[choice.id];
      if (device == null) continue;
      await _sendEntries(device, entries);
    }
  }

  Future<void> _sendEntries(
      LyraDevice device, List<SendFileEntry> entries) async {
    final transfer = context.read<TransferService>();
    final settings = context.read<SettingsService>();
    final messenger = ScaffoldMessenger.of(context);

    var job = await transfer.send(
      target: device,
      files: [for (final e in entries) e.file],
      relPaths: [for (final e in entries) e.relPath],
      pin: settings.pin,
    );

    // PIN reddedildiyse bir kez daha sor ve tekrar dene.
    if (job.state == JobState.failed && (job.error ?? '').contains('PIN')) {
      if (!mounted) return;
      final pin = await _askPin();
      if (pin != null && pin.isNotEmpty) {
        job = await transfer.send(
          target: device,
          files: [for (final e in entries) e.file],
          relPaths: [for (final e in entries) e.relPath],
          pin: pin,
        );
      }
    }

    if (!mounted) return;
    widget.onGoToTransfers?.call();
    final s = AppStrings.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(job.state == JobState.failed
            ? '${s.t('error')}: ${job.error ?? ''}'
            : '${device.name}: ${entries.length} ${s.t('items')}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<List<SendSelection>?> _pickSelections() async {
    final s = AppStrings.of(context);
    final selections = <SendSelection>[];

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: Text(s.t('addFiles')),
              onTap: () => Navigator.of(sheetContext).pop('files'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_folder_upload_outlined),
              title: Text(s.t('addFolder')),
              onTap: () => Navigator.of(sheetContext).pop('folder'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return null;

    if (action == 'files') {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      for (final path in result?.paths ?? const <String?>[]) {
        if (path != null) {
          selections.add(SendSelection(path: path, isDirectory: false));
        }
      }
    } else {
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir != null) {
        selections.add(SendSelection(path: dir, isDirectory: true));
      }
    }
    return selections.isEmpty ? null : selections;
  }

  /// Sürükle-bırak ile gelen yolları seçime çevirir.
  List<SendSelection> _selectionsFromPaths(List<String> paths) {
    final out = <SendSelection>[];
    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        out.add(SendSelection(path: path, isDirectory: true));
      } else if (type == FileSystemEntityType.file) {
        out.add(SendSelection(path: path, isDirectory: false));
      }
    }
    return out;
  }

  // ---------- Diyaloglar ----------

  Future<void> _editAlias() async {
    final identity = context.read<IdentityService>();
    final s = AppStrings.of(context);
    final controller = TextEditingController(text: identity.alias);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.t('editAlias')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: InputDecoration(labelText: s.t('aliasLabel')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(s.t('ok')),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await identity.setAlias(result);
    }
  }

  Future<void> _manualConnect() async {
    final s = AppStrings.of(context);
    final ipController = TextEditingController();
    final portController = TextEditingController(
      text: '${context.read<SettingsService>().transferPort}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.t('connectTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipController,
              decoration: InputDecoration(
                labelText: 'IP',
                hintText: s.t('ipHint'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Port',
                hintText: s.t('portHint'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.t('ok')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final ip = ipController.text.trim();
    final port = int.tryParse(portController.text.trim()) ?? 47802;
    if (ip.isEmpty) return;

    final device = LyraDevice(
      id: 'manual-$ip-$port',
      name: '${s.t('manualDevice')} ($ip)',
      os: 'unknown',
      deviceType: 'unknown',
      address: ip,
      port: port,
      publicKeyBase64: '',
      fingerprint: '',
      lastSeen: DateTime.now(),
    );
    final entries = await _pickSelections();
    if (entries == null || entries.isEmpty) return;
    final expanded = expandSelections(entries);
    await _sendEntries(device, expanded);
  }

  Future<String?> _askPin() async {
    final s = AppStrings.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.t('pinCode')),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: s.t('pinHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(s.t('ok')),
          ),
        ],
      ),
    );
  }

  void _showDeviceInfo(LyraDevice device) {
    final s = AppStrings.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(device.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.t('fingerprint')}: ${device.fingerprint}'),
            const SizedBox(height: 6),
            Text('IP: ${device.address}:${device.port}'),
            const SizedBox(height: 6),
            Text('${s.t('lastSeen')}: ${timeAgo(device.lastSeen)}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.t('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _askFavoriteName(LyraDevice device) async {
    final s = AppStrings.of(context);
    final settings = context.read<SettingsService>();
    final controller =
        TextEditingController(
            text: settings.favoriteName(device.fingerprint) ?? device.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.t('favoriteName')),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(s.t('ok')),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await settings.setFavorite(device.fingerprint, true, name: result);
    }
  }

  // ---------- Görünüm ----------

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final transfer = context.watch<TransferService>();
    final identity = context.watch<IdentityService>();
    final settings = context.watch<SettingsService>();
    final devices = transfer.devices;
    final favorites = [
      for (final d in devices)
        if (settings.isFavorite(d.fingerprint)) d,
    ];
    final others = [
      for (final d in devices)
        if (!settings.isFavorite(d.fingerprint)) d,
    ];

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        final selections =
            _selectionsFromPaths([for (final f in detail.files) f.path]);
        if (selections.isEmpty) return;
        await _startSendFlow(preset: selections);
      },
      child: Stack(
        children: [
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: scheme.primary, width: 2.5),
                    color: scheme.primary.withValues(alpha: 0.08),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_upload_rounded,
                            size: 56, color: scheme.primary),
                        const SizedBox(height: 8),
                        Text(
                          s.t('dragHint'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            children: [
              _HeroDeviceCard(
                alias: identity.alias,
                fingerprint: identity.fingerprint,
                discoveryOn: settings.discoveryOn,
                deviceCount: devices.length,
                onEdit: _editAlias,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s.t('tabDevices')} (${devices.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _manualConnect,
                    icon: const Icon(Icons.add_link_rounded, size: 18),
                    label: Text(s.t('connectManually')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const RadarScan(size: 150),
                      const SizedBox(height: 18),
                      Text(
                        s.t('devicesScanning'),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.t('devicesEmpty'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else ...[
                if (favorites.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.star_rounded,
                          size: 18, color: Colors.amber.shade700),
                      const SizedBox(width: 6),
                      Text(
                        s.t('favorites'),
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final device in favorites)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DeviceTile(
                        device: device,
                        displayName:
                            settings.favoriteName(device.fingerprint),
                        isFavorite: true,
                        onToggleFavorite: () =>
                            settings.setFavorite(device.fingerprint, false),
                        onRenameFavorite: () => _askFavoriteName(device),
                        onSendFiles: () => _startSendFlow(),
                        onSendText: () => _sendTextToDevice(device),
                        onInfo: () => _showDeviceInfo(device),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                for (final device in others)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DeviceTile(
                      device: device,
                      isFavorite: false,
                      onToggleFavorite: () async {
                        await settings.setFavorite(device.fingerprint, true,
                            name: device.name);
                        if (mounted) await _askFavoriteName(device);
                      },
                      onSendFiles: () => _startSendFlow(),
                      onSendText: () => _sendTextToDevice(device),
                      onInfo: () => _showDeviceInfo(device),
                    ),
                  ),
              ],
            ],
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: FloatingActionButton.extended(
              onPressed: () => _startSendFlow(),
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(s.t('sendFiles')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendTextToDevice(LyraDevice device) async {
    final s = AppStrings.of(context);
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.t('textTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
          decoration: InputDecoration(hintText: s.t('textHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(s.t('sendAction')),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    if (!mounted) return;

    final transfer = context.read<TransferService>();
    final settings = context.read<SettingsService>();
    await transfer.send(
      target: device,
      files: const [],
      text: text.trim(),
      pin: settings.pin,
    );
    if (!mounted) return;
    widget.onGoToTransfers?.call();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('${device.name}: ${s.t('sendText')}')),
    );
  }
}

/// Kendi cihazımızı gösteren hero kart.
class _HeroDeviceCard extends StatelessWidget {
  final String alias;
  final String fingerprint;
  final bool discoveryOn;
  final int deviceCount;
  final VoidCallback onEdit;

  const _HeroDeviceCard({
    required this.alias,
    required this.fingerprint,
    required this.discoveryOn,
    required this.deviceCount,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.6)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -12,
            bottom: -18,
            child: Opacity(
              opacity: 0.16,
              child: SendLyraLogo(size: 130, glow: false),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            discoveryOn
                                ? Icons.wifi_tethering_rounded
                                : Icons.wifi_off_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            discoveryOn
                                ? s.t('discoveryOn')
                                : s.t('discoveryOff'),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: s.t('editAlias'),
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_rounded),
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  alias,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${s.t('myDevice')} · ${s.t('fingerprint')}: ${fingerprintShort(fingerprint)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatBadge(
                      icon: Icons.devices_rounded,
                      label: '$deviceCount ${s.t('devicesFound')}',
                    ),
                    const SizedBox(width: 10),
                    _StatBadge(
                      icon: Icons.shield_rounded,
                      label: s.t('protocolInfo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
