import 'package:flutter/material.dart';

/// Brand tokens (spec section 8, "Brand"). Change colours here only.
abstract final class Tokens {
  /// Brand orange. Fills that carry only an icon (FAB, send, launcher tile):
  /// white on it is 3.6:1, enough for non-text (WCAG 1.4.11).
  static const flame = Color(0xFFE8590C);

  /// Orange fills that carry text (buttons): white on it is 4.9:1 (AA).
  static const flameDeep = Color(0xFFC8450B);

  /// Small orange text and icons on light surfaces (5.0:1 on white).
  static const flameText = Color(0xFFC2410C);

  /// Orange text and marks on dark surfaces (8:1 on the dark background).
  static const flameLight = Color(0xFFFF8A4C);

  static const cream = Color(0xFFFFFBF8);
  static const ink = Color(0xFF1C1714);
  static const warning = Color(0xFFF2C94C);

  /// Placeholder avatars: muted, warm, no flag or party colours.
  static const avatars = [
    Color(0xFFB85C38), // terracotta
    Color(0xFF9C6644), // clay
    Color(0xFF8E4A6B), // plum
    Color(0xFF5B6C8F), // slate
    Color(0xFF3E7C7A), // teal
    Color(0xFF7B5EA7), // violet
    Color(0xFFA0522D), // sienna
    Color(0xFF6D6A65), // stone
  ];
}

/// Digits that do not jitter (times, counters, badges).
const tabularFigures = [FontFeature.tabularFigures()];

/// App colours that Material's ColorScheme has no slot for.
@immutable
class ChatColors extends ThemeExtension<ChatColors> {
  const ChatColors({
    required this.background,
    required this.mine,
    required this.other,
    required this.bubbleText,
    required this.meta,
    required this.readTick,
    required this.bubbleShadow,
    required this.banner,
    required this.accent,
    required this.tint,
    required this.onTint,
    required this.systemChip,
    required this.notice,
    required this.onNotice,
    required this.raised,
    required this.cardTint,
    required this.photoShade,
    required this.onPhoto,
    required this.onPhotoRead,
  });

  final Color background;
  final Color mine;
  final Color other;
  final Color bubbleText;

  /// Time, ticks and "Editada" on both bubble colours.
  final Color meta;
  final Color readTick;

  /// Light mode only: the hairline shadow under bubbles.
  final Color? bubbleShadow;
  final Color banner;

  /// Orange for small text and icons ("primary deep"): unread times, section
  /// headers, admin labels, "digitando…".
  final Color accent;

  /// Orange at 14% on the surface: selected chip, own reaction, icon circles.
  final Color tint;
  final Color onTint;
  final Color systemChip;

  /// End-to-end encryption notice.
  final Color notice;
  final Color onNotice;

  /// Dialogs, menus and sheets in dark mode sit one step above the surface.
  final Color raised;

  /// Reply quote, file card and composer context banner inside a bubble or bar.
  final Color cardTint;

  /// Dark pill under the time and ticks on a photo, and the marks on it.
  final Color photoShade;
  final Color onPhoto;
  final Color onPhotoRead;

  static const light = ChatColors(
    background: Color(0xFFF4EDE6),
    mine: Color(0xFFFFE9DC),
    other: Color(0xFFFFFFFF),
    bubbleText: Tokens.ink,
    meta: Color(0xFF6F625A),
    readTick: Color(0xFF1E6FD9),
    bubbleShadow: Color(0x14000000),
    banner: Tokens.warning,
    accent: Tokens.flameText,
    tint: Color(0xFFFCE3D6),
    onTint: Color(0xFF9A3412),
    systemChip: Color(0xEBFFFFFF),
    notice: Color(0xFFFFF1E3),
    onNotice: Color(0xFF6B4A33),
    raised: Color(0xFFFFFFFF),
    cardTint: Color(0x0D000000),
    photoShade: Color(0x61000000),
    onPhoto: Color(0xFFFFFFFF),
    onPhotoRead: Color(0xFF53BDEB),
  );

  static const dark = ChatColors(
    background: Color(0xFF0F0C0A),
    mine: Color(0xFF4A2510),
    other: Color(0xFF26211E),
    bubbleText: Color(0xFFF5EDE8),
    meta: Color(0xFFC9B8AD),
    readTick: Color(0xFF53BDEB),
    bubbleShadow: null,
    banner: Color(0xFF8A6D1A),
    accent: Tokens.flameLight,
    tint: Color(0xFF4A2510),
    onTint: Color(0xFFFFB38A),
    systemChip: Color(0xFF1C1917),
    notice: Color(0xFF2A211B),
    onNotice: Color(0xFFE3C9B4),
    raised: Color(0xFF26211E),
    cardTint: Color(0x0FFFFFFF),
    photoShade: Color(0x61000000),
    onPhoto: Color(0xFFFFFFFF),
    onPhotoRead: Color(0xFF53BDEB),
  );

  static ChatColors of(BuildContext context) => Theme.of(context).extension<ChatColors>()!;

  /// Placeholder avatar colour for [seed] (a user or room ID), stable across
  /// platforms. Dark mode dims it to 80%.
  Color avatarFor(String seed, Brightness brightness) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final c = Tokens.avatars[h % Tokens.avatars.length];
    return brightness == Brightness.dark ? Color.lerp(c, const Color(0xFF000000), 0.2)! : c;
  }

  @override
  ChatColors copyWith() => this;

  @override
  ChatColors lerp(ChatColors? other, double t) => t < 0.5 || other == null ? this : other;
}

const _light = ColorScheme(
  brightness: Brightness.light,
  primary: Tokens.flame,
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFFCE3D6),
  onPrimaryContainer: Color(0xFF9A3412),
  secondary: Color(0xFF6F625A),
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFF3EEEA),
  onSecondaryContainer: Color(0xFF3B302A),
  tertiary: Color(0xFF6B4A33),
  onTertiary: Colors.white,
  error: Color(0xFFB3261E),
  onError: Colors.white,
  surface: Color(0xFFFFFFFF),
  onSurface: Tokens.ink,
  onSurfaceVariant: Color(0xFF6F625A),
  surfaceDim: Color(0xFFE6DFD9),
  surfaceBright: Color(0xFFFFFFFF),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFAF7F5),
  surfaceContainer: Color(0xFFF3EEEA),
  surfaceContainerHigh: Color(0xFFECE6E1),
  surfaceContainerHighest: Color(0xFFE6DFD9),
  outline: Color(0xFF9C8F86),
  outlineVariant: Color(0xFFE6DED8),
  inverseSurface: Color(0xFF2F2926),
  onInverseSurface: Color(0xFFF2EBE6),
  inversePrimary: Tokens.flameLight,
  shadow: Colors.black,
  scrim: Colors.black,
  surfaceTint: Colors.transparent,
);

const _dark = ColorScheme(
  brightness: Brightness.dark,
  // Text and accents only; orange fills use Tokens.flame / flameDeep.
  primary: Tokens.flameLight,
  onPrimary: Tokens.ink,
  primaryContainer: Color(0xFF4A2510),
  onPrimaryContainer: Color(0xFFFFB38A),
  secondary: Color(0xFFB3A59C),
  onSecondary: Tokens.ink,
  secondaryContainer: Color(0xFF2F2926),
  onSecondaryContainer: Color(0xFFE6DED8),
  tertiary: Color(0xFFE3C9B4),
  onTertiary: Tokens.ink,
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  surface: Color(0xFF121010),
  onSurface: Color(0xFFF2EBE6),
  onSurfaceVariant: Color(0xFFB3A59C),
  surfaceDim: Color(0xFF121010),
  surfaceBright: Color(0xFF2F2926),
  surfaceContainerLowest: Color(0xFF0D0B0A),
  surfaceContainerLow: Color(0xFF171413),
  surfaceContainer: Color(0xFF1C1917),
  surfaceContainerHigh: Color(0xFF26211E),
  surfaceContainerHighest: Color(0xFF2F2926),
  outline: Color(0xFF85766D),
  outlineVariant: Color(0xFF3A322D),
  inverseSurface: Color(0xFFF2EBE6),
  onInverseSurface: Tokens.ink,
  inversePrimary: Tokens.flame,
  shadow: Colors.black,
  scrim: Colors.black,
  surfaceTint: Colors.transparent,
);

TextStyle _t(double size, double lineHeight, FontWeight weight, [double spacing = 0]) =>
    TextStyle(fontSize: size, height: lineHeight / size, fontWeight: weight, letterSpacing: spacing);

/// Type scale (Inter, bundled in assets/fonts).
final _textTheme = TextTheme(
  displaySmall: _t(28, 34, FontWeight.w300),
  headlineMedium: _t(28, 34, FontWeight.w600, -0.5),
  headlineSmall: _t(24, 30, FontWeight.w600, -0.3),
  titleLarge: _t(20, 26, FontWeight.w600, -0.2),
  titleMedium: _t(16, 22, FontWeight.w600),
  titleSmall: _t(14, 20, FontWeight.w600),
  bodyLarge: _t(16, 22, FontWeight.w400),
  bodyMedium: _t(14, 20, FontWeight.w400),
  bodySmall: _t(12.5, 18, FontWeight.w400),
  labelLarge: _t(14, 20, FontWeight.w600),
  labelMedium: _t(12.5, 16, FontWeight.w500),
  labelSmall: _t(11, 14, FontWeight.w500),
);

const fontFamily = 'Inter';
const monoFontFamily = 'JetBrainsMono';

ThemeData chamaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _dark : _light;
  final chat = dark ? ChatColors.dark : ChatColors.light;
  final raised = chat.raised;
  final overlay = scheme.onSurface;
  final base = ThemeData(colorScheme: scheme, fontFamily: fontFamily, textTheme: _textTheme);
  final text = base.textTheme;
  final input = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none);
  return base.copyWith(
    extensions: [chat],
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    splashFactory: InkRipple.splashFactory,
    highlightColor: overlay.withValues(alpha: 0.06),
    splashColor: overlay.withValues(alpha: dark ? 0.12 : 0.10),
    hoverColor: overlay.withValues(alpha: 0.04),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 0.5, space: 0.5),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // A hairline instead of a tinted shadow once content scrolls under.
      scrolledUnderElevation: 0.5,
      shadowColor: scheme.outline,
      centerTitle: false,
      toolbarHeight: 60,
      titleSpacing: 16,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? overlay.withValues(alpha: 0.12) : Tokens.flameDeep,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? overlay.withValues(alpha: 0.38) : Colors.white,
        ),
        overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.12)),
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 24)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: WidgetStatePropertyAll(text.titleMedium),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: chat.accent,
        // Disabled text stays readable (5:1), not 38% grey.
        disabledForegroundColor: scheme.onSurfaceVariant,
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
        minimumSize: const Size(48, 44),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Tokens.flame,
      foregroundColor: Colors.white,
      shape: CircleBorder(),
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Tokens.flame : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : scheme.outline,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Tokens.flameDeep : null),
      checkColor: const WidgetStatePropertyAll(Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: input,
      enabledBorder: input,
      disabledBorder: input,
      focusedBorder: input.copyWith(borderSide: BorderSide(color: scheme.primary, width: 2)),
      errorBorder: input.copyWith(borderSide: BorderSide(color: scheme.error, width: 2)),
      focusedErrorBorder: input.copyWith(borderSide: BorderSide(color: scheme.error, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      floatingLabelStyle: text.labelMedium?.copyWith(fontSize: 13, color: chat.accent),
      hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Tokens.flame,
      selectionColor: Tokens.flame.withValues(alpha: 0.3),
      selectionHandleColor: Tokens.flame,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Tokens.flame.withValues(alpha: 0.14),
      elevation: 0,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium?.copyWith(
          color: s.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? chat.accent : scheme.onSurfaceVariant),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? scheme.surfaceContainer : scheme.surface,
      modalBackgroundColor: dark ? scheme.surfaceContainer : scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      dragHandleSize: const Size(32, 4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      contentTextStyle: text.bodyLarge?.copyWith(fontSize: 15, color: scheme.onSurfaceVariant),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: raised,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: text.bodyLarge?.copyWith(fontSize: 15, color: scheme.onSurface),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
      subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minTileHeight: 56,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Tokens.flame),
  );
}
