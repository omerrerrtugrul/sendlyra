import 'package:flutter/material.dart';

import '../../core/models/transfer_job.dart';
import '../../core/utils/format.dart';
import '../strings.dart';

/// Bir transfer işinin kartı: ilerleme, hız, kalan süre.
class TransferCard extends StatelessWidget {
  final TransferJob job;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenFolder;

  const TransferCard({
    super.key,
    required this.job,
    this.onCancel,
    this.onOpenFolder,
  });

  String _stateLabel(AppStrings s) {
    switch (job.state) {
      case JobState.connecting:
        return s.t('stateConnecting');
      case JobState.waitingApproval:
        return s.t('stateWaiting');
      case JobState.transferring:
        return s.t('stateTransferring');
      case JobState.completed:
        return s.t('stateCompleted');
      case JobState.failed:
        return s.t('stateFailed');
      case JobState.cancelled:
        return s.t('stateCancelled');
    }
  }

  IconData get _directionIcon => job.direction == JobDirection.send
      ? Icons.arrow_upward_rounded
      : Icons.arrow_downward_rounded;

  String _remaining(AppStrings s) {
    if (job.speedBps <= 0 || job.isFinished) return '';
    final left = (job.totalBytes - job.transferred) / job.speedBps;
    if (left.isInfinite || left.isNaN || left < 0) return '';
    return '${s.t('remaining')} ${formatDuration(Duration(seconds: left.round()))}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final progress = job.progress;
    final isError = job.state == JobState.failed;
    final isDone = job.state == JobState.completed;
    final accent = isError ? scheme.error : (isDone ? scheme.tertiary : scheme.primary);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_directionIcon, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${job.direction == JobDirection.send ? s.t('send') : s.t('receive')} · ${job.peerName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(label: _stateLabel(s), job: job),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Stack(
                children: [
                  Container(
                    height: 8,
                    color: scheme.surfaceContainerHighest,
                  ),
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 250),
                    widthFactor: job.totalBytes > 0
                        ? progress
                        : (job.isFinished ? 1 : 0),
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accent,
                            Color.lerp(accent, scheme.tertiary, 0.5)!,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      '${formatBytes(job.transferred)} / ${formatBytes(job.totalBytes)}',
                      if (job.speedBps > 0 && !job.isFinished)
                        formatSpeed(job.speedBps),
                      if (_remaining(s).isNotEmpty) _remaining(s),
                    ].join('  ·  '),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                if (onOpenFolder != null && isDone)
                  IconButton(
                    tooltip: s.t('openFolder'),
                    onPressed: onOpenFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                if (onCancel != null && !job.isFinished)
                  IconButton(
                    tooltip: s.t('cancelJob'),
                    onPressed: onCancel,
                    icon: Icon(Icons.close_rounded, color: scheme.error),
                  ),
              ],
            ),
            if (isError && job.error != null) ...[
              const SizedBox(height: 6),
              Text(
                s.errorText(job.error),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final TransferJob job;

  const _StatusChip({required this.label, required this.job});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    switch (job.state) {
      case JobState.completed:
        bg = scheme.tertiaryContainer;
        fg = scheme.onTertiaryContainer;
      case JobState.failed:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
      case JobState.cancelled:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
      default:
        bg = scheme.primaryContainer;
        fg = scheme.onPrimaryContainer;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
