import 'package:flutter/material.dart';

/// SendLyra markası: takımyıldızlardan oluşan lir (lyra) motifi.
///
/// Tamamen CustomPainter ile çizilir — hazır görsel asset kullanılmaz.
class SendLyraLogo extends StatelessWidget {
  final double size;
  final bool glow;

  const SendLyraLogo({super.key, this.size = 40, this.glow = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'SendLyra logosu',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _LyraPainter(
          primary: scheme.primary,
          secondary: scheme.tertiary,
          glow: glow,
        ),
      ),
    );
  }
}

/// Logo + yazı birlikte.
class SendLyraWordmark extends StatelessWidget {
  final double logoSize;
  final Color? textColor;

  const SendLyraWordmark({super.key, this.logoSize = 32, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SendLyraLogo(size: logoSize),
        const SizedBox(width: 10),
        Text(
          'SendLyra',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: textColor,
              ),
        ),
      ],
    );
  }
}

class _LyraPainter extends CustomPainter {
  final Color primary;
  final Color secondary;
  final bool glow;

  _LyraPainter({
    required this.primary,
    required this.secondary,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.055
      ..shader = LinearGradient(
        colors: [primary, secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);

    // Lir gövdesi: iki yay (sol ve sağ kol)
    final leftArm = Path()
      ..moveTo(w * 0.28, h * 0.18)
      ..quadraticBezierTo(w * 0.10, h * 0.45, w * 0.22, h * 0.80);
    final rightArm = Path()
      ..moveTo(w * 0.72, h * 0.18)
      ..quadraticBezierTo(w * 0.90, h * 0.45, w * 0.78, h * 0.80);

    // Üst köprü ve alt birleşim
    final bridge = Path()
      ..moveTo(w * 0.28, h * 0.18)
      ..quadraticBezierTo(w * 0.50, h * 0.10, w * 0.72, h * 0.18);
    final base = Path()
      ..moveTo(w * 0.22, h * 0.80)
      ..quadraticBezierTo(w * 0.50, h * 0.92, w * 0.78, h * 0.80);

    for (final path in [leftArm, rightArm, bridge, base]) {
      canvas.drawPath(path, stroke);
    }

    // Teller (dikey ince çizgiler)
    final strings = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.022
      ..strokeCap = StrokeCap.round
      ..color = secondary.withValues(alpha: 0.85);
    for (var i = 0; i < 5; i++) {
      final t = (i + 1) / 6;
      final x = w * (0.30 + 0.40 * t);
      canvas.drawLine(
        Offset(x, h * (0.20 + 0.04 * (1 - (t - 0.5).abs() * 2))),
        Offset(x, h * (0.78 - 0.06 * (1 - (t - 0.5).abs() * 2))),
        strings,
      );
    }

    // Yıldızlar (takımyıldız noktaları)
    final starPaint = Paint()..color = primary;
    final starGlowPaint = Paint()
      ..color = primary.withValues(alpha: glow ? 0.25 : 0.0);
    const stars = [
      Offset(0.28, 0.18),
      Offset(0.72, 0.18),
      Offset(0.50, 0.10),
      Offset(0.22, 0.80),
      Offset(0.78, 0.80),
      Offset(0.50, 0.92),
      Offset(0.50, 0.50),
    ];
    for (final s in stars) {
      final center = Offset(w * s.dx, h * s.dy);
      canvas.drawCircle(center, w * 0.065, starGlowPaint);
      canvas.drawCircle(center, w * 0.028, starPaint);
    }
  }

  @override
  bool shouldRepaint(_LyraPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.glow != glow;
}
