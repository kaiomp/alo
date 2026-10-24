import 'package:flutter/material.dart';

import '../common/theme.dart';
import '../services/ticks.dart';

/// Clock, ✓, ✓✓, blue ✓✓ or a red mark.
class TickIcon extends StatelessWidget {
  const TickIcon(this.tick, {super.key, this.size = 16});
  final Tick tick;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final (icon, color) = switch (tick) {
      Tick.pending => (Icons.schedule, colors.meta),
      Tick.failed => (Icons.error_outline, Theme.of(context).colorScheme.error),
      Tick.sent => (Icons.done, colors.meta),
      Tick.delivered => (Icons.done_all, colors.meta),
      Tick.read => (Icons.done_all, colors.readTick),
    };
    return Icon(icon, size: size, color: color, key: Key('tick_${tick.name}'), semanticLabel: tick.name);
  }
}
