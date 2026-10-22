import 'dart:math';

import 'package:flutter/material.dart';

/// Boş durum görselleri için yardımcı.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Cihaz arama animasyonu: dönen radar süpürmesi + nabız halkaları.
class RadarScan extends StatefulWidget {
  final double size;

  const RadarScan({super.key, this.size = 160});

  @override
  State<RadarScan> createState() => _RadarScanState();
}

class _RadarScanState extends State<RadarScan>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Cihaz aranıyor',
      image: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _RadarPainter(
            progress: _controller.value,
            primary: scheme.primary,
            surface: scheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color surface;

  _RadarPainter({
    required this.progress,
    required this.primary,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // İç içe daireler
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = primary.withValues(alpha: 0.25);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, ring);
    }

    // Nabız halkası
    final pulse = (sin(progress * 2 * pi) + 1) / 2;
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = primary.withValues(alpha: 0.35 * (1 - pulse));
    canvas.drawCircle(center, radius * (0.35 + 0.6 * pulse), pulsePaint);

    // Süpürme konisi
    final sweep = progress * 2 * pi;
    final cone = Paint()
      ..style = PaintingStyle.fill
      ..shader = SweepGradient(
        startAngle: sweep - 0.9,
        endAngle: sweep,
        colors: [
          primary.withValues(alpha: 0.0),
          primary.withValues(alpha: 0.35),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      sweep - 0.9,
      0.9,
      true,
      cone,
    );

    // Süpürme çizgisi
    final line = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = primary.withValues(alpha: 0.8);
    canvas.drawLine(
      center,
      center + Offset(cos(sweep), sin(sweep)) * radius,
      line,
    );

    // Merkez düğüm
    canvas.drawCircle(center, 5, Paint()..color = primary);

    // Sabit "cihaz" noktaları
    final dot = Paint()..color = primary.withValues(alpha: 0.55);
    const points = [
      Offset(0.62, -0.35),
      Offset(-0.55, 0.42),
      Offset(0.25, 0.68),
    ];
    for (final p in points) {
      canvas.drawCircle(center + Offset(p.dx, p.dy) * radius, 3.2, dot);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
