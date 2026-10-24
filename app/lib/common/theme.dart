import 'package:flutter/material.dart';

/// Brand tokens (spec section 8, "Brand"). Change colours here only.
abstract final class Tokens {
  static const flame = Color(0xFFE8590C);
  static const flameLight = Color(0xFFFF8A4C);
  static const readTick = Color(0xFF3D8BFD);
  static const warning = Color(0xFFF2C94C);

  /// Text and icons on flame orange: white there is only 3.6:1, this is 5:1 (WCAG AA).
  static const ink = Color(0xFF1C1714);
}

/// Chat-specific colours that Material's ColorScheme has no slot for.
@immutable
class ChatColors extends ThemeExtension<ChatColors> {
  const ChatColors({
    required this.background,
    required this.mine,
    required this.other,
    required this.meta,
    required this.readTick,
    required this.banner,
  });

  final Color background;
  final Color mine;
  final Color other;
  final Color meta;
  final Color readTick;
  final Color banner;

  static const light = ChatColors(
    background: Color(0xFFF4EDE6),
    mine: Color(0xFFFDE3D2),
    other: Color(0xFFFFFFFF),
    meta: Color(0xFF8A7B72),
    readTick: Tokens.readTick,
    banner: Tokens.warning,
  );

  static const dark = ChatColors(
    background: Color(0xFF120E0C),
    mine: Color(0xFF6B2A08),
    other: Color(0xFF2A2320),
    meta: Color(0xFFB3A59C),
    readTick: Tokens.readTick,
    banner: Color(0xFF8A6D1A),
  );

  static ChatColors of(BuildContext context) => Theme.of(context).extension<ChatColors>()!;

  @override
  ChatColors copyWith() => this;

  @override
  ChatColors lerp(ChatColors? other, double t) => t < 0.5 || other == null ? this : other;
}

ThemeData chamaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Tokens.flame,
    brightness: brightness,
    primary: dark ? Tokens.flameLight : Tokens.flame,
    onPrimary: dark ? null : Tokens.ink,
    surface: dark ? Tokens.ink : const Color(0xFFFFFBF8),
  );
  return ThemeData(
    colorScheme: scheme,
    extensions: [dark ? ChatColors.dark : ChatColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
  );
}
