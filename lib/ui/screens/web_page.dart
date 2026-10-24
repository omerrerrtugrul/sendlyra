import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/settings_service.dart';
import '../../core/services/web_share_service.dart';
import '../strings.dart';

/// W-01…W-05: web paylaşımı sekmesi.
///
/// Sunucu açma/kapama, erişim linki + QR, web PIN'i, paylaşılacak
/// dosyaların listesi, gelen yüklemeler ve HTTP/TLS ayarları.
class WebSharePage extends StatefulWidget {
  const WebSharePage({super.key});

  @override
  State<WebSharePage> createState() => _WebSharePageState();
}

class _WebSharePageState extends State<WebSharePage> {
  final _pinController = TextEditingController();
  final _portController = TextEditingController();
  final _certController = TextEditingController();
  final _keyController = TextEditingController();
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _portController.text = '${settings.webPort}';
    _certController.text = settings.webTlsCert;
    _keyController.text = settings.webTlsKey;
    _pinController.text = settings.webPin ?? '';
  }

  @override
  void dispose() {
    _pinController.dispose();
    _portController.dispose();
    _certController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _toggleServer(WebShareService web) async {
    try {
      if (web.running) {
        await web.stop();
      } else {
        await web.start();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStrings.of(context).t('webStartError')}: $e')),
      );
    }
  }

  Future<void> _copyLink(WebShareService web) async {
    await Clipboard.setData(ClipboardData(text: web.url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.of(context).t('copied'))),
    );
  }

  Future<void> _showQr(WebShareService web) async {
    final s = AppStrings.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('webQrTitle')),
        content: SizedBox(
          width: 240,
          height: 240,
          child: QrImageView(data: web.url, backgroundColor: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.t('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _addFiles(WebShareService web, {required bool folder}) async {
    if (folder) {
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir != null) web.addPaths([dir]);
    } else {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      final paths = [
        for (final p in result?.paths ?? const <String?>[])
          if (p != null) p,
      ];
      if (paths.isNotEmpty) web.addPaths(paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final web = context.watch<WebShareService>();
    final settings = context.watch<SettingsService>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Durum + link ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      web.running
                          ? Icons.public_rounded
                          : Icons.public_off_rounded,
                      color: web.running ? Colors.green : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.t('webTitle'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Switch(
                      value: web.running,
                      onChanged: (_) => _toggleServer(web),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!web.running)
                  Text(s.t('webOffHint'),
                      style: Theme.of(context).textTheme.bodySmall),
                if (web.running) ...[
                  if (!web.tlsEnabled)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 18, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(s.t('webHttpWarn'),
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          web.url,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13),
                        ),
                      ),
                      IconButton(
                        tooltip: s.t('webCopyLink'),
                        onPressed: () => _copyLink(web),
                        icon: const Icon(Icons.copy_rounded),
                      ),
                      IconButton(
                        tooltip: s.t('webQrTitle'),
                        onPressed: () => _showQr(web),
                        icon: const Icon(Icons.qr_code_2_rounded),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // ---- PIN (W-04) ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('webPinTitle'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pinController,
                        obscureText: true,
                        maxLength: 12,
                        decoration: InputDecoration(
                          counterText: '',
                          labelText: s.t('webPinLabel'),
                          hintText: s.t('webPinHint'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        await settings.setWebPin(_pinController.text.trim());
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.t('webPinSaved'))),
                        );
                      },
                      child: Text(s.t('webPinSave')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ---- Paylaşılan dosyalar (W-02) ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.t('webSharedTitle'),
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    TextButton.icon(
                      onPressed: () => _addFiles(web, folder: false),
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                      label: Text(s.t('addFiles')),
                    ),
                    TextButton.icon(
                      onPressed: () => _addFiles(web, folder: true),
                      icon: const Icon(Icons.drive_folder_upload_outlined,
                          size: 18),
                      label: Text(s.t('addFolder')),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (web.shared.isEmpty)
                  Text(s.t('webSharedEmpty'),
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  for (final entry in web.shared)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(entry.name, maxLines: 1),
                      trailing: IconButton(
                        tooltip: s.t('webRemove'),
                        onPressed: () => web.removeShared(entry),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
              ],
            ),
          ),
        ),

        // ---- Gelen yüklemeler (W-03) ----
        if (web.uploads.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('webUploadsTitle'),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final name in web.uploads.take(10))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.download_done_rounded, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

        // ---- Gelişmiş (port + TLS, W-01/W-05) ----
        Card(
          child: ExpansionTile(
            title: Text(s.t('webAdvanced')),
            initiallyExpanded: _advanced,
            onExpansionChanged: (v) => setState(() => _advanced = v),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: s.t('webPortLabel')),
                      onSubmitted: (v) async {
                        final port = int.tryParse(v.trim());
                        if (port == null || port < 1 || port > 65535) return;
                        await settings.setWebPort(port);
                        if (web.running) await web.restart();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _certController,
                      decoration:
                          InputDecoration(labelText: s.t('webTlsCert')),
                      onSubmitted: (v) async {
                        await settings.setWebTls(cert: v.trim());
                        if (web.running) await web.restart();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _keyController,
                      decoration: InputDecoration(labelText: s.t('webTlsKey')),
                      onSubmitted: (v) async {
                        await settings.setWebTls(key: v.trim());
                        if (web.running) await web.restart();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
