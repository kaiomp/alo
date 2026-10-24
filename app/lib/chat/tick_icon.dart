import 'package:flutter/material.dart';

import '../common/theme.dart';
import '../l10n/app_localizations.dart';
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
    final l = L10n.of(context);
    final meta = onPhoto ? colors.onPhoto : colors.meta;
    final (icon, color, label) = switch (tick) {
      Tick.pending => (Icons.schedule, meta, l.tickPending),
      Tick.failed => (Icons.error_outline, Theme.of(context).colorScheme.error, l.tickFailed),
      Tick.sent => (Icons.done, meta, l.tickSent),
      Tick.delivered => (Icons.done_all, meta, l.tickDelivered),
      Tick.read => (Icons.done_all, onPhoto ? colors.onPhotoRead : colors.readTick, l.tickRead),
    };
    return Icon(icon, size: size, color: color, key: Key('tick_${tick.name}'), semanticLabel: label);
  }
}
