import 'package:flutter/material.dart';

import '../common/theme.dart';
import '../services/ticks.dart';

/// Clock, ✓, ✓✓, blue ✓✓ or a red mark.
class TickIcon extends StatelessWidget {
  const TickIcon(this.tick, {super.key, this.size = 16, this.onPhoto = false});
  final Tick tick;
  final double size;

  /// White marks (blue once read) over a photo's dark shade.
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final meta = onPhoto ? Colors.white : colors.meta;
    final (icon, color) = switch (tick) {
      Tick.pending => (Icons.schedule, meta),
      Tick.failed => (Icons.error_outline, Theme.of(context).colorScheme.error),
      Tick.sent => (Icons.done, meta),
      Tick.delivered => (Icons.done_all, meta),
      Tick.read => (Icons.done_all, onPhoto ? ChatColors.dark.readTick : colors.readTick),
    };
    return Icon(icon, size: size, color: color, key: Key('tick_${tick.name}'), semanticLabel: tick.name);
  }
}
