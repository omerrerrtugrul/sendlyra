import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/transfer_job.dart';
import '../../core/services/history_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/transfer_service.dart';
import '../../core/utils/format.dart';
import '../strings.dart';
import '../widgets/empty_state.dart';
import '../widgets/transfer_card.dart';

/// Aktif transferler ve tamamlanan işlerin geçmişi.
class TransfersPage extends StatelessWidget {
  const TransfersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final transfer = context.watch<TransferService>();
    final settings = context.watch<SettingsService>();
    final history = context.watch<HistoryService>();
    final active = transfer.activeJobs;
    final finished = transfer.jobs.where((j) => j.isFinished).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _SectionHeader(
          title: s.t('activeTransfers'),
          badge: active.isEmpty ? null : '${active.length}',
        ),
        const SizedBox(height: 12),
        if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: EmptyState(
              icon: Icons.swap_vert_circle_outlined,
              title: s.t('activeEmpty'),
            ),
          )
        else
          for (final job in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TransferCard(
                job: job,
                onCancel: () => transfer.cancelJob(job),
              ),
            ),
        const SizedBox(height: 16),
        _SectionHeader(
          title: s.t('history'),
          action: history.entries.isEmpty && finished.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(s.t('clearHistory')),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: Text(s.t('cancel')),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: Text(s.t('ok')),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) await history.clear();
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(s.t('clearHistory')),
                ),
        ),
        const SizedBox(height: 12),
        if (history.entries.isEmpty && finished.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: EmptyState(
              icon: Icons.history_rounded,
              title: s.t('historyEmpty'),
            ),
          )
        else ...[
          for (final job in finished)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TransferCard(
                job: job,
                onOpenFolder: () async {
                  final path = job.files.isNotEmpty
                      ? (job.files.first.savedPath ?? settings.saveDir)
                      : settings.saveDir;
                  await openInFileExplorer(path);
                },
              ),
            ),
          for (final entry in history.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (entry.success
                              ? scheme.primary
                              : scheme.error)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      entry.direction == JobDirection.send
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: entry.success ? scheme.primary : scheme.error,
                    ),
                  ),
                  title: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${entry.peerName} · ${formatBytes(entry.bytes)} · ${timeAgo(entry.time)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    entry.success
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    color: entry.success ? scheme.tertiary : scheme.error,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? badge;
  final Widget? action;

  const _SectionHeader({required this.title, this.badge, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              badge!,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.primary),
            ),
          ),
        ],
        const Spacer(),
        if (action != null) action!,
      ],
    );
  }
}
