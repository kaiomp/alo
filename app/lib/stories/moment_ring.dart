import 'package:flutter/material.dart';

import '../common/avatar.dart';
import '../common/theme.dart';
import '../services/social_service.dart';

/// An avatar inside a ring: ipê while there is something new, a hairline
/// once seen.
class MomentRing extends StatelessWidget {
  const MomentRing({super.key, required this.person, required this.seen, this.radius = 30, this.badge});
  final Person person;
  final bool seen;
  final double radius;

  /// A small "+" on my own ring.
  final bool? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = radius < 24 ? 2.0 : 3.0;
    final size = (radius + ring + 3) * 2;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: seen
                  ? null
                  : const SweepGradient(
                      colors: [Tokens.ipe, Tokens.ipeLight, Tokens.ipeDeep, Tokens.ipe],
                      transform: GradientRotation(-1.2),
                    ),
              border: seen ? Border.all(color: scheme.outlineVariant, width: 1.5) : null,
            ),
          ),
          Container(
            width: size - ring * 2,
            height: size - ring * 2,
            decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
          ),
          Avatar(name: person.name, seed: person.id, mxc: person.avatar, radius: radius),
          if (badge == true)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(Icons.add, size: 14, color: scheme.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}
