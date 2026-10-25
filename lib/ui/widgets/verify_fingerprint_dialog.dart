import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/identity_service.dart';
import '../../core/utils/fingerprint_matcher.dart';
import '../strings.dart';

/// Parmak izi doğrulama diyaloğu (R-1).
///
/// Kullanıcı, karşı cihazın ekranında (QR paneli veya cihaz bilgisi) gördüğü
/// parmak iziyle buradaki izi karşılaştırır. İsterse karşı cihazın izini
/// yapıştırarak otomatik eşleşme kontrolü de yapabilir. Doğrulama yalnızca
/// kullanıcı onayıyla kaydedilir; iz değişirse doğrulama anlamsızlaşacağı için
/// TOFU kontrolleri bağlantı seviyesinde reddetmeye devam eder.
class VerifyFingerprintDialog extends StatefulWidget {
  final String deviceName;
  final String fingerprint;

  const VerifyFingerprintDialog({
    super.key,
    required this.deviceName,
    required this.fingerprint,
  });

  /// Diyaloğu açar; doğrulama kaydedildiyse `true` döner.
  static Future<bool> show(
    BuildContext context, {
    required String deviceName,
    required String fingerprint,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => VerifyFingerprintDialog(
        deviceName: deviceName,
        fingerprint: fingerprint,
      ),
    );
    return result ?? false;
  }

  @override
  State<VerifyFingerprintDialog> createState() =>
      _VerifyFingerprintDialogState();
}

class _VerifyFingerprintDialogState extends State<VerifyFingerprintDialog> {
  final _inputController = TextEditingController();
  bool _confirmed = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  /// Girilen iz boşsa görsel karşılaştırma yeterli; doluysa eşleşmek zorunda.
  bool get _inputOk {
    final text = _inputController.text.trim();
    return text.isEmpty || fingerprintsMatch(text, widget.fingerprint);
  }

  bool get _canSave => _confirmed && _inputOk;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final identity = context.read<IdentityService>();

    return AlertDialog(
      title: Text(s.t('verifyTitle')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('verifyIntro'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            _FingerprintBox(
              label: s.t('verifyMyFingerprint'),
              fingerprint: identity.fingerprint,
              color: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 10),
            _FingerprintBox(
              label: '${s.t('verifyPeerFingerprint')} — ${widget.deviceName}',
              fingerprint: widget.fingerprint,
              color: scheme.primaryContainer.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _inputController,
              decoration: InputDecoration(
                labelText: s.t('verifyPasteLabel'),
                helperText:
                    _inputController.text.trim().isEmpty ? null : _matchText(s),
                helperStyle: TextStyle(
                  color: _inputOk ? scheme.primary : scheme.error,
                  fontWeight: FontWeight.w600,
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _confirmed,
              onChanged: (v) => setState(() => _confirmed = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('verifyConfirmCheck')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.t('close')),
        ),
        FilledButton(
          onPressed:
              _canSave ? () => Navigator.of(context).pop(true) : null,
          child: Text(s.t('verifySave')),
        ),
      ],
    );
  }

  String _matchText(AppStrings s) =>
      _inputOk ? s.t('verifyMatch') : s.t('verifyMismatch');
}

class _FingerprintBox extends StatelessWidget {
  final String label;
  final String fingerprint;
  final Color color;

  const _FingerprintBox({
    required this.label,
    required this.fingerprint,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            groupFingerprint(fingerprint),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontFeatures: const [],
                ),
          ),
        ],
      ),
    );
  }
}
