import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'widgets.dart';

class MenuAction<T> {
  const MenuAction(this.value, this.icon, this.label, {this.destructive = false, this.key});
  final T value;
  final IconData icon;
  final String label;
  final bool destructive;
  final Key? key;
}

/// The global rect of [context]'s widget: where a menu for it opens.
Rect rectOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Actions for a message or a chat. Phones get a bottom sheet (WhatsApp
/// Android); wide screens and right clicks get a menu next to [anchor], with
/// the [emojis] as a floating pill above it (WhatsApp Web). Picking an emoji
/// returns `onEmoji(emoji)`.
Future<T?> showActions<T>(
  BuildContext context, {
  required Rect anchor,
  required List<MenuAction<T>> actions,
  bool pointer = false,
  bool alignEnd = false,
  List<String> emojis = const [],
  T Function(String emoji)? onEmoji,
}) {
  if (isWide(context) || pointer) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      transitionBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
      ),
      pageBuilder: (context, _, _) =>
          _AnchoredMenu<T>(anchor: anchor, actions: actions, alignEnd: alignEnd, emojis: emojis, onEmoji: onEmoji),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        key: const Key('actions'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emojis.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in emojis) _EmojiButton(e, size: 48, onTap: () => Navigator.pop(context, onEmoji!(e))),
                ],
              ),
            ),
          for (final a in actions) _ActionTile(a, height: 52),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _ActionTile<T> extends StatelessWidget {
  const _ActionTile(this.action, {required this.height});
  final MenuAction<T> action;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = action.destructive ? scheme.error : null;
    final menu = height < 52;
    return ListTile(
      key: action.key,
      minTileHeight: height,
      minVerticalPadding: 0,
      horizontalTitleGap: menu ? 12 : 16,
      contentPadding: EdgeInsets.symmetric(horizontal: menu ? 14 : 24),
      leading: Icon(action.icon, size: menu ? 20 : 24, color: color ?? scheme.onSurfaceVariant),
      title: Text(
        action.label,
        style: TextStyle(fontSize: menu ? 15 : 16, color: color ?? scheme.onSurface),
      ),
      onTap: () => Navigator.pop(context, action.value),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton(this.emoji, {required this.size, required this.onTap});
  final String emoji;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      key: Key('react_$emoji'),
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: size * 0.56)),
        ),
      ),
    ),
  );
}

class _AnchoredMenu<T> extends StatelessWidget {
  const _AnchoredMenu({
    required this.anchor,
    required this.actions,
    required this.alignEnd,
    required this.emojis,
    required this.onEmoji,
  });

  final Rect anchor;
  final List<MenuAction<T>> actions;
  final bool alignEnd;
  final List<String> emojis;
  final T Function(String emoji)? onEmoji;

  static const _width = 220.0;
  static const _item = 40.0;
  static const _pill = 44.0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final surface = Theme.of(context).popupMenuTheme.color;
    const gap = 6.0;
    final menuHeight = actions.length * _item + 12;
    final pillWidth = emojis.length * 40.0 + 8;

    double clampX(double x, double w) => x.clamp(8.0, math.max(8.0, screen.width - w - 8));
    double clampY(double y, double h) => y.clamp(8.0, math.max(8.0, screen.height - h - 8));

    final menuX = clampX(alignEnd ? anchor.right - _width : anchor.left, _width);
    // Below the item when it fits, else above it, else over its lower part.
    var menuY = anchor.bottom + gap;
    if (menuY + menuHeight > screen.height - 8) {
      menuY = anchor.top - gap - menuHeight - (emojis.isEmpty ? 0 : _pill + gap);
      if (menuY < 8) menuY = screen.height - menuHeight - 8;
    }
    final pillX = clampX(alignEnd ? anchor.right - pillWidth : anchor.left, pillWidth);
    final pillY = menuY > anchor.top ? anchor.top - gap - _pill : menuY + menuHeight + gap;

    return Stack(
      key: const Key('actions'),
      children: [
        if (emojis.isNotEmpty)
          Positioned(
            left: pillX,
            top: clampY(pillY, _pill),
            child: Material(
              color: surface,
              elevation: 3,
              borderRadius: BorderRadius.circular(_pill / 2),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in emojis) _EmojiButton(e, size: 40, onTap: () => Navigator.pop(context, onEmoji!(e))),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: menuX,
          top: clampY(menuY, menuHeight),
          width: _width,
          child: Material(
            color: surface,
            elevation: 3,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final a in actions) _ActionTile(a, height: _item)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
