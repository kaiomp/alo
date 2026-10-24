import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'deps.dart';
import 'theme.dart';

/// Round avatar: the picture when there is one, else the first letter on a
/// colour picked from [seed] (user or room ID). Groups and people without a
/// name get a neutral silhouette.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.seed, this.mxc, this.radius = 24, this.group = false});

  final String name;
  final String? seed;
  final Uri? mxc;
  final double radius;
  final bool group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = radius * 2;
    final Widget fallback;
    if (group || name.trim().isEmpty) {
      fallback = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
        child: CustomPaint(painter: _Silhouette(scheme.onSurfaceVariant, group: group)),
      );
    } else {
      fallback = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ChatColors.of(context).avatarFor(seed ?? name, theme.brightness),
          shape: BoxShape.circle,
        ),
        child: Text(
          name.trim().characters.first.toUpperCase(),
          textScaler: TextScaler.noScaling,
          style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      );
    }
    final mxc = this.mxc;
    final child = mxc == null
        ? fallback
        : FutureBuilder<Uint8List?>(
            future: Deps.of(context).chat.thumbnail(mxc, size: (radius * 4).round()),
            builder: (context, snap) =>
                snap.data == null ? fallback : CircleAvatar(radius: radius, backgroundImage: MemoryImage(snap.data!)),
          );
    return Semantics(label: name, image: true, excludeSemantics: true, child: child);
  }
}

/// One head and shoulders, or two for a group.
class _Silhouette extends CustomPainter {
  _Silhouette(this.color, {required this.group});
  final Color color;
  final bool group;

  void _person(Canvas canvas, Size s, Offset head, double r, Paint paint) {
    canvas.drawCircle(Offset(head.dx * s.width, head.dy * s.height), r * s.width, paint);
    final body = Rect.fromCenter(
      center: Offset(head.dx * s.width, (head.dy + r * 3.4) * s.height),
      width: r * 4.2 * s.width,
      height: r * 3.6 * s.height,
    );
    canvas.drawOval(body, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipPath(Path()..addOval(Offset.zero & size));
    final paint = Paint()..color = color;
    if (!group) {
      _person(canvas, size, const Offset(0.5, 0.4), 0.17, paint);
      return;
    }
    _person(canvas, size, const Offset(0.64, 0.38), 0.13, Paint()..color = color.withValues(alpha: 0.6));
    _person(canvas, size, const Offset(0.4, 0.44), 0.15, paint);
  }

  @override
  bool shouldRepaint(_Silhouette old) => old.color != color || old.group != group;
}
