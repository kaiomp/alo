import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'theme.dart';

/// The Chama mark: a flame whose counter is a speech bubble. Same geometry as
/// assets/brand/chama-mark.svg (24-unit grid).
class ChamaMark extends StatelessWidget {
  const ChamaMark({super.key, this.size = 56, this.color});
  final double size;

  /// Defaults to flame orange on light surfaces and the light orange on dark.
  final Color? color;

  static Path path() => Path()
    ..fillType = PathFillType.evenOdd
    // Flame.
    ..moveTo(14.6, 1.8)
    ..cubicTo(10.6, 4.8, 5, 9.4, 5, 15)
    ..arcToPoint(const Offset(19, 15), radius: const Radius.circular(7), clockwise: false)
    ..cubicTo(19, 11.4, 17.3, 9.4, 16.3, 7.6)
    ..cubicTo(15.4, 6, 14.9, 4.2, 14.6, 1.8)
    ..close()
    // Counter: a speech bubble with its tail at the lower left.
    ..moveTo(12.9, 10.4)
    ..cubicTo(14.6, 12, 16, 13.5, 16, 15.5)
    ..cubicTo(16, 17.5, 14.4, 19.1, 12.4, 19.1)
    ..cubicTo(11.7, 19.1, 11.1, 18.9, 10.6, 18.6)
    ..lineTo(8.5, 19.4)
    ..lineTo(9.1, 17.3)
    ..cubicTo(8.9, 16.8, 8.8, 16.2, 8.8, 15.6)
    ..cubicTo(8.8, 13.6, 11.1, 12, 12.9, 10.4)
    ..close();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: L10n.of(context).appName,
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(color ?? (dark ? Tokens.flameLight : Tokens.flame)),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas.drawPath(ChamaMark.path(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

/// Mark + "chama" wordmark (onboarding).
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const ChamaMark(size: 56),
      const SizedBox(width: 12),
      Text(
        L10n.of(context).wordmark,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ],
  );
}
