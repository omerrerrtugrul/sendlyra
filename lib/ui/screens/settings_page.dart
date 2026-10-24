import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/identity_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/transfer_service.dart';
import '../strings.dart';
import '../theme.dart';

/// Tüm ayarların tek ekranda toplandığı sayfa.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final identity = context.watch<IdentityService>();
    final settings = context.watch<SettingsService>();
    final transfer = context.watch<TransferService>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Section(title: s.t('settingsGeneral'), children: [
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(s.t('aliasLabel')),
            subtitle: Text(identity.alias),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final controller = TextEditingController(text: identity.alias);
              final result = await showDialog<String>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(s.t('editAlias')),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 64,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(s.t('cancel')),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(controller.text),
                      child: Text(s.t('ok')),
                    ),
                  ],
                ),
              );
              if (result != null && result.trim().isNotEmpty) {
                await identity.setAlias(result);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(s.t('saveDir')),
            subtitle: Text(
              settings.saveDir.isEmpty ? '—' : settings.saveDir,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              onPressed: () async {
                final dir = await FilePicker.platform.getDirectoryPath();
                if (dir != null && dir.isNotEmpty) {
                  await settings.setSaveDir(dir);
                }
              },
              child: Text(s.t('choose')),
            ),
          ),
        ]),
        _Section(title: s.t('settingsAppearance'), children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                    value: 0,
                    icon: const Icon(Icons.brightness_auto_rounded),
                    label: Text(s.t('themeSystem'))),
                ButtonSegment(
                    value: 1,
                    icon: const Icon(Icons.light_mode_rounded),
                    label: Text(s.t('themeLight'))),
                ButtonSegment(
                    value: 2,
                    icon: const Icon(Icons.dark_mode_rounded),
                    label: Text(s.t('themeDark'))),
              ],
              selected: {
                settings.themeMode == ThemeMode.system
                    ? 0
                    : settings.themeMode == ThemeMode.light
                        ? 1
                        : 2
              },
              onSelectionChanged: (selection) async {
                final mode = switch (selection.first) {
                  0 => ThemeMode.system,
                  1 => ThemeMode.light,
                  _ => ThemeMode.dark,
                };
                await settings.setThemeMode(mode);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Text(s.t('accentColor'),
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(width: 16),
                for (var i = 0; i < SendLyraTheme.accents.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => settings.setAccentIndex(i),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: SendLyraTheme.accent(i),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: settings.accentIndex == i
                                ? scheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: settings.accentIndex == i
                            ? const Icon(Icons.check,
                                size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
        _Section(title: s.t('settingsSecurity'), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('quickSave'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'off', label: Text(s.t('quickSaveOff'))),
                    ButtonSegment(
                        value: 'all', label: Text(s.t('quickSaveAll'))),
                    ButtonSegment(
                        value: 'favorites',
                        label: Text(s.t('quickSaveFav'))),
                  ],
                  selected: {settings.quickSaveMode},
                  onSelectionChanged: (selection) =>
                      settings.setQuickSaveMode(selection.first),
                ),
                const SizedBox(height: 6),
                Text(
                  s.t('quickSaveDesc'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(s.t('requireApproval')),
            subtitle: Text(s.t('requireApprovalDesc')),
            trailing: Switch(
              value: settings.quickSaveMode == 'off',
              onChanged: (v) => settings
                  .setQuickSaveMode(v ? 'off' : 'all'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(s.t('pinCode')),
            subtitle: Text(settings.hasPin ? '••••' : s.t('pinHint')),
            trailing: TextButton(
              onPressed: () async {
                if (settings.hasPin) {
                  await settings.setPin(null);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.t('pinRemoved'))));
                  }
                  return;
                }
                final controller = TextEditingController();
                final result = await showDialog<String>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(s.t('setPin')),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(hintText: s.t('pinHint')),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(s.t('cancel')),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(controller.text),
                        child: Text(s.t('ok')),
                      ),
                    ],
                  ),
                );
                if (result != null && result.length >= 4) {
                  await settings.setPin(result);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.t('pinSet'))));
                  }
                }
              },
              child: Text(settings.hasPin ? s.t('removePin') : s.t('setPin')),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.verified_rounded),
            title: Text(s.t('trustedDevices')),
            subtitle: settings.trustedFingerprints.isEmpty
                ? Text(s.t('trustedEmpty'))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final fp in settings.trustedFingerprints)
                        Chip(
                          label: Text(
                            _deviceName(transfer, fp),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          onDeleted: () => settings.setTrusted(fp, false),
                        ),
                    ],
                  ),
          ),
          ListTile(
            leading: Icon(Icons.star_rounded, color: Colors.amber.shade700),
            title: Text(s.t('favorites')),
            subtitle: settings.favoriteNames.isEmpty
                ? Text(s.t('favoritesEmpty'))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in settings.favoriteNames.entries)
                        Chip(
                          avatar: const Icon(Icons.star_rounded, size: 16),
                          label: Text(
                            '${entry.value} (${_deviceName(transfer, entry.key)})',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          onDeleted: () =>
                              settings.setFavorite(entry.key, false),
                        ),
                    ],
                  ),
          ),
        ]),
        _Section(title: s.t('settingsNetwork'), children: [
          ListTile(
            leading: const Icon(Icons.lan_outlined),
            title: Text(s.t('transferPort')),
            subtitle: Text(
                '${settings.transferPort} · ${s.t('portDesc')}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final controller =
                  TextEditingController(text: '${settings.transferPort}');
              final result = await showDialog<String>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(s.t('transferPort')),
                  content: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(s.t('cancel')),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(controller.text),
                      child: Text(s.t('ok')),
                    ),
                  ],
                ),
              );
              final port = int.tryParse(result ?? '');
              if (port != null && port > 0 && port < 65536) {
                await settings.setTransferPort(port);
                await transfer.restartServices();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.t('restartDone'))));
                }
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.radar_rounded),
            title: Text(s.t('discovery')),
            subtitle: Text(s.t('discoveryDesc')),
            value: settings.discoveryOn,
            onChanged: (v) async {
              await settings.setDiscoveryOn(v);
              await transfer.restartServices();
            },
          ),
        ]),
        _Section(title: s.t('settingsLanguage'), children: [
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: Text(s.t('settingsLanguage')),
            subtitle: Text(s.t('languageDesc')),
            trailing: DropdownButton<String>(
              value: settings.localeCode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (v) {
                if (v != null) settings.setLocaleCode(v);
              },
            ),
          ),
        ]),
        _Section(title: s.t('settingsAbout'), children: [
          ListTile(
            leading: const SizedBox(
              width: 40,
              child: Icon(Icons.auto_awesome_rounded),
            ),
            title: const Text('SendLyra 0.1.0'),
            subtitle: Text(
              '${s.t('aboutDesc')}\n${s.t('protocolInfo')} · ${s.t('fingerprint')}: ${identity.fingerprint}',
            ),
          ),
        ]),
      ],
    );
  }

  /// Parmak izinden okunabilir cihaz adı; bulunamazsa izin kısaltması.
  String _deviceName(TransferService transfer, String fingerprint) {
    for (final d in transfer.devices) {
      if (d.fingerprint == fingerprint) return d.name;
    }
    return fingerprint.length > 12
        ? '${fingerprint.substring(0, 12)}…'
        : fingerprint;
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
          ),
        ),
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
