import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../common/theme.dart';

/// Plays a scene by itself on the live app: real pointer events (so the
/// screens react exactly as to a finger), typing into the focused field,
/// and smooth scrolls. Every tap shows as a soft circle for the video.
class Director {
  Director(this.name);
  final String name;
  final taps = ValueNotifier<TapMark?>(null);
  final _clock = Stopwatch();
  var _pointer = 900;
  var _tapCount = 0;

  /// t = 0 of the scene: the first frame the video keeps.
  void start() {
    _clock.start();
    _announce('inicio');
  }

  void end() => _announce('fim');

  /// The page title tells the recorder where the scene is; the log has the
  /// same line with the time.
  void _announce(String state) {
    unawaited(
      SystemChrome.setApplicationSwitcherDescription(
        ApplicationSwitcherDescription(label: 'Chama · cena $name · $state', primaryColor: Tokens.acai.toARGB32()),
      ),
    );
    beat(state);
  }

  void beat(String what) =>
      // ignore: avoid_print
      print('CENA $name ${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(2)} s: $what');

  /// Waits until [seconds] after [start]. Scenes use absolute times so a
  /// slow step never shifts the ones after it.
  Future<void> at(double seconds, [String? what]) async {
    final wait = Duration(milliseconds: (seconds * 1000).round()) - _clock.elapsed;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (what != null) beat(what);
  }

  /// The end hold: from [end] - 2 s the screen stays still until [end].
  /// `cena:fim` goes to the console as the hold starts; the capture script
  /// stops on it.
  Future<void> hold(double end) async {
    await at(end - 2, 'pausa final');
    // ignore: avoid_print
    print('cena:fim');
    await at(end);
  }

  // ---- finding things on screen ----

  /// Elements matching [test] whose render box is hit at its centre, i.e.
  /// what a finger would touch now (routes below the top one do not count).
  List<Element> _visible(bool Function(Widget) test) {
    final found = <Element>[];
    void visit(Element e) {
      if (test(e.widget) && _hittable(e)) found.add(e);
      e.visitChildElements(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    return found;
  }

  bool _hittable(Element e) {
    final box = e.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      center,
      WidgetsBinding.instance.platformDispatcher.implicitView!.viewId,
    );
    return result.path.any((entry) => entry.target == box);
  }

  Rect _rect(Element e) {
    final box = e.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Element _one(String what, bool Function(Widget) test) {
    final all = _visible(test);
    if (all.isEmpty) throw StateError('Scene $name: nothing on screen for $what');
    return all.first;
  }

  Rect key(String k) => _rect(_one(k, (w) => w.key == Key(k)));
  Rect text(String t) => _rect(_one(t, (w) => w is Text && w.data == t));
  Rect type<T extends Widget>() => _rect(_one('$T', (w) => w is T));

  /// The [index]th tab of the bottom bar.
  Rect tab(int index) {
    final all = _visible((w) => w is NavigationDestination).map(_rect).toList()
      ..sort((a, b) => a.left.compareTo(b.left));
    return all[index];
  }

  // ---- acting ----

  Future<void> tap(Rect target, {Offset at = const Offset(0.5, 0.5)}) async {
    final p = target.topLeft + Offset(target.width * at.dx, target.height * at.dy);
    taps.value = TapMark(p, _tapCount++);
    final id = _pointer++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(PointerDownEvent(pointer: id, position: p, timeStamp: _clock.elapsed));
    await Future<void>.delayed(const Duration(milliseconds: 70));
    binding.handlePointerEvent(PointerUpEvent(pointer: id, position: p, timeStamp: _clock.elapsed));
    // Focus and route changes land a frame later.
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  Future<void> doubleTap(Rect target) async {
    await tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await tap(target);
  }

  Future<void> longPress(Rect target) async {
    final p = target.center;
    taps.value = TapMark(p, _tapCount++, hold: true);
    final id = _pointer++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(PointerDownEvent(pointer: id, position: p, timeStamp: _clock.elapsed));
    await Future<void>.delayed(const Duration(milliseconds: 650));
    binding.handlePointerEvent(PointerUpEvent(pointer: id, position: p, timeStamp: _clock.elapsed));
  }

  /// A finger drag from [from] by [by] over [duration] (swipes, pull to refresh).
  Future<void> drag(Offset from, Offset by, {Duration duration = const Duration(milliseconds: 350)}) async {
    taps.value = TapMark(from, _tapCount++, by: by, duration: duration);
    final id = _pointer++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(PointerDownEvent(pointer: id, position: from, timeStamp: _clock.elapsed));
    const steps = 20;
    var last = from;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(duration ~/ steps);
      final t = Curves.easeInOut.transform(i / steps);
      final p = from + by * t;
      binding.handlePointerEvent(
        PointerMoveEvent(pointer: id, position: p, delta: p - last, timeStamp: _clock.elapsed),
      );
      last = p;
    }
    binding.handlePointerEvent(PointerUpEvent(pointer: id, position: last, timeStamp: _clock.elapsed));
  }

  /// Types [text] into the focused field, one character at a time.
  Future<void> typeText(String text, {Duration perChar = const Duration(milliseconds: 55)}) async {
    final field = FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>();
    if (field == null) throw StateError('Scene $name: no text field has focus');
    final start = field.textEditingValue.text;
    final chars = text.characters.toList();
    for (var i = 1; i <= chars.length; i++) {
      final value = start + chars.take(i).join();
      field.userUpdateTextEditingValue(
        TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        ),
        SelectionChangedCause.keyboard,
      );
      await Future<void>.delayed(perChar);
    }
  }

  /// Scrolls the scrollable under the widget keyed [k] to [offset].
  Future<void> scrollTo(String k, double offset, {Duration duration = const Duration(milliseconds: 1600)}) =>
      _scrollable(k).position.animateTo(offset, duration: duration, curve: Curves.easeInOutCubic);

  /// The first scrollable at or under the widget keyed [k].
  ScrollableState _scrollable(String k) {
    final e = _one(k, (w) => w.key == Key(k));
    ScrollableState? state;
    void find(Element x) {
      if (state != null) return;
      if (x is StatefulElement && x.state is ScrollableState) {
        state = x.state as ScrollableState;
        return;
      }
      x.visitChildElements(find);
    }

    find(e);
    return state!;
  }

  /// Scrolls the scrollable under [k] to its end. The end of a lazy list is
  /// an estimate until it is built, so a short second pass lands on it.
  Future<void> scrollToEnd(String k, {Duration duration = const Duration(milliseconds: 2400)}) async {
    final position = _scrollable(k).position;
    await position.animateTo(position.maxScrollExtent, duration: duration, curve: Curves.easeInOutCubic);
    if (position.pixels < position.maxScrollExtent) {
      await position.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Scrolls the widget keyed [k] into view, [alignment] down the viewport.
  /// It only has to be built (within the list's cache), not on screen.
  Future<void> reveal(
    String k, {
    double alignment = 0.3,
    Duration duration = const Duration(milliseconds: 1800),
  }) async {
    Element? found;
    void visit(Element e) {
      if (found != null) return;
      if (e.widget.key == Key(k)) {
        found = e;
        return;
      }
      e.visitChildElements(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    if (found == null) throw StateError('Scene $name: $k is not built');
    await Scrollable.ensureVisible(found!, alignment: alignment, duration: duration, curve: Curves.easeInOutCubic);
  }

  void unfocus() => FocusManager.instance.primaryFocus?.unfocus();
}

/// One tap (or hold, or drag) to draw.
class TapMark {
  const TapMark(this.at, this.id, {this.hold = false, this.by, this.duration = Duration.zero});
  final Offset at;
  final int id;
  final bool hold;
  final Offset? by;
  final Duration duration;
}

/// The soft circles over the app while a scene plays. Ignores pointers.
class TapOverlay extends StatelessWidget {
  const TapOverlay({super.key, required this.taps});
  final ValueListenable<TapMark?> taps;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ValueListenableBuilder<TapMark?>(
      valueListenable: taps,
      builder: (context, mark, _) =>
          mark == null ? const SizedBox.expand() : _Ripple(key: ValueKey(mark.id), mark: mark),
    ),
  );
}

class _Ripple extends StatefulWidget {
  const _Ripple({super.key, required this.mark});
  final TapMark mark;

  @override
  State<_Ripple> createState() => _RippleState();
}

class _RippleState extends State<_Ripple> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: widget.mark.duration + Duration(milliseconds: widget.mark.hold ? 1100 : 650),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final m = widget.mark;
      final total = _c.duration!.inMilliseconds;
      final ms = _c.value * total;
      // Press in, follow a drag, then grow and fade.
      final moveMs = m.duration.inMilliseconds;
      final follow = moveMs == 0 ? 1.0 : (ms / moveMs).clamp(0.0, 1.0);
      final at = m.at + (m.by ?? Offset.zero) * Curves.easeInOut.transform(follow);
      final holdMs = m.hold ? 650 : 0;
      final fadeStart = moveMs + holdMs + 120;
      final fade = ((ms - fadeStart) / (total - fadeStart)).clamp(0.0, 1.0);
      final press = (ms / 120).clamp(0.0, 1.0);
      final size = 30 + 14 * Curves.easeOut.transform(press) + 22 * fade;
      final opacity = (1 - fade) * (0.4 + 0.6 * press);
      return Stack(
        children: [
          Positioned(
            left: at.dx - size / 2,
            top: at.dy - size / 2,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Tokens.acai.withValues(alpha: 0.28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10)],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
