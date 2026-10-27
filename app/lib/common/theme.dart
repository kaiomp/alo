import 'package:flutter/material.dart';

/// Brand tokens (spec section 8, "Brand"). Change colours here only.
/// Açaí purple is the primary, ipê yellow the accent; surfaces stay warm
/// neutrals (a faint açaí cast in dark mode).
abstract final class Tokens {
  /// Açaí, the brand primary. Fills that carry text or icons in light mode:
  /// white on it is 12:1, ipê on it 6.9:1.
  static const acai = Color(0xFF4A1D6E);

  /// Açaí for text and marks on dark surfaces (9:1 on the dark background),
  /// and dark-mode fills with [acaiInk] on them.
  static const acaiLight = Color(0xFFC9A7F5);

  /// Deepest açaí: text on ipê (9:1) and on [acaiLight] (8:1).
  static const acaiInk = Color(0xFF2B1240);

  /// Ipê yellow: unread badges, story rings, the mark on an açaí tile and
  /// small accents in dark mode (10:1 on the dark background).
  static const ipe = Color(0xFFF5B700);

  /// A liked heart: 4.5:1 on white, 7:1 ([likeLight]) on the dark background.
  static const like = Color(0xFFD63384);
  static const likeLight = Color(0xFFFF6B9E);

  /// The two other stops of the ipê ring around new moments.
  static const ipeLight = Color(0xFFFFD34D);
  static const ipeDeep = Color(0xFFE9A000);

  /// The dark end of the açaí gradient ("Seus dados são seus").
  static const acaiDeep = Color(0xFF34124F);

  /// Over photos and the açaí card, in both modes: white text at three
  /// levels, the empty progress track, and the shades that keep it readable.
  static const onPhotoSoft = Color(0xE6FFFFFF);
  static const onPhotoMuted = Color(0xCCFFFFFF);
  static const onPhotoFaint = Color(0x99FFFFFF);
  static const onPhotoTrack = Color(0x59FFFFFF);
  static const shadeClear = Color(0x00000000);
  static const shadeLight = Color(0x26000000);
  static const shade = Color(0x80000000);
  static const shadeDeep = Color(0x99000000);
  static const shadeDeeper = Color(0xB3000000);

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
    required this.onBanner,
    required this.accent,
    required this.tint,
    required this.onTint,
    required this.systemChip,
    required this.notice,
    required this.onNotice,
    required this.raised,
    required this.cardTint,
    required this.quoteName,
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

  /// "Conectando…" text on [banner].
  final Color onBanner;

  /// Brand colour for small text and icons: unread times, section headers,
  /// admin labels, "digitando…". Açaí in light mode, ipê in dark.
  final Color accent;

  /// Light açaí on the surface: selected chip, own reaction, icon circles.
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

  /// Author name in a reply quote or the composer banner, on [cardTint].
  final Color quoteName;

  /// Dark pill under the time and ticks on a photo, and the marks on it.
  final Color photoShade;
  final Color onPhoto;
  final Color onPhotoRead;

  static const light = ChatColors(
    background: Color(0xFFF3EEEA),
    mine: Color(0xFFECE1F5),
    other: Color(0xFFFFFFFF),
    bubbleText: Tokens.ink,
    meta: Color(0xFF5F5466),
    readTick: Color(0xFF1E6FD9),
    bubbleShadow: Color(0x14000000),
    banner: Tokens.warning,
    onBanner: Tokens.ink,
    accent: Tokens.acai,
    tint: Color(0xFFEFE6F7),
    onTint: Tokens.acai,
    systemChip: Color(0xEBFFFFFF),
    notice: Color(0xFFFFF4CC),
    onNotice: Color(0xFF5C4300),
    raised: Color(0xFFFFFFFF),
    cardTint: Color(0x0D000000),
    quoteName: Tokens.acai,
    photoShade: Color(0x61000000),
    onPhoto: Color(0xFFFFFFFF),
    onPhotoRead: Color(0xFF53BDEB),
  );

  static const dark = ChatColors(
    background: Color(0xFF0F0C11),
    mine: Color(0xFF3A2152),
    other: Color(0xFF26222A),
    bubbleText: Color(0xFFF3ECF7),
    meta: Color(0xFFC9B8CF),
    readTick: Color(0xFF53BDEB),
    bubbleShadow: null,
    banner: Color(0xFF8A6D1A),
    onBanner: Color(0xFFFFFFFF),
    accent: Tokens.ipe,
    tint: Color(0xFF3A2152),
    onTint: Color(0xFFE9D9FA),
    systemChip: Color(0xFF1D1A20),
    notice: Color(0xFF2A2418),
    onNotice: Color(0xFFEBD9A6),
    raised: Color(0xFF27232A),
    cardTint: Color(0x0FFFFFFF),
    quoteName: Tokens.ipe,
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

  /// Only the background changes today (Modo simples: a plain one).
  @override
  ChatColors copyWith({Color? background}) => ChatColors(
    background: background ?? this.background,
    mine: mine,
    other: other,
    bubbleText: bubbleText,
    meta: meta,
    readTick: readTick,
    bubbleShadow: bubbleShadow,
    banner: banner,
    onBanner: onBanner,
    accent: accent,
    tint: tint,
    onTint: onTint,
    systemChip: systemChip,
    notice: notice,
    onNotice: onNotice,
    raised: raised,
    cardTint: cardTint,
    quoteName: quoteName,
    photoShade: photoShade,
    onPhoto: onPhoto,
    onPhotoRead: onPhotoRead,
  );

  @override
  ChatColors lerp(ChatColors? other, double t) => t < 0.5 || other == null ? this : other;
}

const _light = ColorScheme(
  brightness: Brightness.light,
  primary: Tokens.acai,
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFEFE6F7),
  onPrimaryContainer: Tokens.acai,
  secondary: Color(0xFF6F625A),
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFF3EEEA),
  onSecondaryContainer: Color(0xFF3B302A),
  tertiary: Color(0xFF5C4300),
  onTertiary: Colors.white,
  tertiaryContainer: Color(0xFFFFF4CC),
  onTertiaryContainer: Color(0xFF5C4300),
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
  inverseSurface: Color(0xFF2B2530),
  onInverseSurface: Color(0xFFF2EDF3),
  inversePrimary: Tokens.acaiLight,
  shadow: Colors.black,
  scrim: Colors.black,
  surfaceTint: Colors.transparent,
);

const _dark = ColorScheme(
  brightness: Brightness.dark,
  // Light açaí for text, accents and fills (with açaí ink on them).
  primary: Tokens.acaiLight,
  onPrimary: Tokens.acaiInk,
  primaryContainer: Color(0xFF3A2152),
  onPrimaryContainer: Color(0xFFE9D9FA),
  secondary: Color(0xFFB5A9B9),
  onSecondary: Tokens.ink,
  secondaryContainer: Color(0xFF312C35),
  onSecondaryContainer: Color(0xFFE6DEE8),
  tertiary: Tokens.ipe,
  onTertiary: Tokens.acaiInk,
  tertiaryContainer: Color(0xFF2A2418),
  onTertiaryContainer: Color(0xFFEBD9A6),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  surface: Color(0xFF121014),
  onSurface: Color(0xFFF2EDF3),
  onSurfaceVariant: Color(0xFFB5A9B9),
  surfaceDim: Color(0xFF121014),
  surfaceBright: Color(0xFF312C35),
  surfaceContainerLowest: Color(0xFF0D0B0E),
  surfaceContainerLow: Color(0xFF17141A),
  surfaceContainer: Color(0xFF1D1A20),
  surfaceContainerHigh: Color(0xFF27232A),
  surfaceContainerHighest: Color(0xFF312C35),
  outline: Color(0xFF877C8C),
  outlineVariant: Color(0xFF3A343E),
  inverseSurface: Color(0xFFF2EDF3),
  onInverseSurface: Tokens.ink,
  inversePrimary: Tokens.acai,
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
          (s) => s.contains(WidgetState.disabled) ? overlay.withValues(alpha: 0.12) : scheme.primary,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? overlay.withValues(alpha: 0.38) : scheme.onPrimary,
        ),
        overlayColor: WidgetStatePropertyAll(scheme.onPrimary.withValues(alpha: 0.12)),
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
    // Açaí with an ipê icon (the app icon's colours); light açaí in dark mode.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: dark ? Tokens.acaiInk : Tokens.ipe,
      shape: const CircleBorder(),
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? scheme.primary : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : scheme.outline,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
      checkColor: WidgetStatePropertyAll(scheme.onPrimary),
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
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.3),
      selectionHandleColor: scheme.primary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: dark ? 0.18 : 0.12),
      elevation: 0,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium?.copyWith(
          fontSize: 12,
          letterSpacing: -0.2,
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
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}
