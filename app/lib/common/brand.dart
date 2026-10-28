import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'theme.dart';

/// The Alô mark: one continuous line that draws the arches of the Pampulha
/// church and closes into a speech bubble. Same geometry as
/// assets/brand/alo-mark.svg (100-unit grid, stroke 6, round ends).
class AloMark extends StatelessWidget {
  const AloMark({super.key, this.size = 56, this.color, this.tile = false});
  final double size;

  /// The line colour. Defaults to açaí on light surfaces and ipê on dark;
  /// on a [tile] it is always ipê.
  final Color? color;

  /// The app icon: the line in ipê on a rounded açaí square.
  final bool tile;

  static Path path() => Path()
    ..moveTo(22, 86)
    ..lineTo(30, 68)
    ..cubicTo(14, 56, 13, 38, 24, 29)
    ..quadraticBezierTo(37, 13, 50, 28)
    ..quadraticBezierTo(63, 13, 76, 29)
    ..cubicTo(87, 38, 86, 57, 72, 66)
    ..quadraticBezierTo(52, 77, 30, 68);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = tile ? Tokens.ipe : color ?? (dark ? Tokens.ipe : Tokens.acai);
    return Semantics(
      label: L10n.of(context).appName,
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(line, tile: tile),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color, {required this.tile});
  final Color color;
  final bool tile;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (tile) {
      // alo-icon.svg: the whole 100 grid, corners 23.
      canvas.scale(size.width / 100);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(23)),
        Paint()..color = Tokens.acai,
      );
      canvas.drawPath(AloMark.path(), stroke);
      return;
    }
    // alo-mark.svg crops the grid to 10..90.
    canvas.scale(size.width / 80);
    canvas.translate(-10, -10);
    canvas.drawPath(AloMark.path(), stroke);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color || old.tile != tile;
}

/// Mark + "alo" wordmark (onboarding).
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const AloMark(size: 56, tile: true),
      const SizedBox(width: 14),
      Text(
        L10n.of(context).wordmark,
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ],
  );
}
