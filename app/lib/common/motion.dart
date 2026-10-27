import 'package:flutter/widgets.dart';

/// The system's "reduce motion" setting (also on when animations are off).
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [d], or no animation at all when the person asked for less motion.
Duration motion(BuildContext context, Duration d) => reduceMotion(context) ? Duration.zero : d;
