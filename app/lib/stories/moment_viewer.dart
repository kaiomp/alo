import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/motion.dart';
import '../common/net_image.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';

/// Full-screen moments, one person per page (a cube turn between people).
/// Tap right or left to skip, hold to pause, swipe down to close, type to
/// reply in the 1:1 chat.
class MomentViewer extends StatefulWidget {
  const MomentViewer({super.key, required this.groups, required this.initial});
  final List<MomentGroup> groups;
  final int initial;

  static const perMoment = Duration(seconds: 5);

  @override
  State<MomentViewer> createState() => _MomentViewerState();
}

class _MomentViewerState extends State<MomentViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page + 1 >= widget.groups.length) return Navigator.of(context).pop();
    _pages.nextPage(
      duration: motion(context, const Duration(milliseconds: 420)) + const Duration(milliseconds: 1),
      curve: Curves.easeInOutCubic,
    );
  }

  void _previous() {
    if (_page == 0) return;
    _pages.previousPage(
      duration: motion(context, const Duration(milliseconds: 420)) + const Duration(milliseconds: 1),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: PageView.builder(
        key: const Key('moment_pages'),
        controller: _pages,
        itemCount: widget.groups.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (context, i) => AnimatedBuilder(
          animation: _pages,
          builder: (context, child) {
            if (reduceMotion(context)) return child!;
            // Cube: each page turns around its edge shared with the next.
            final pos = _pages.hasClients && _pages.position.haveDimensions ? _pages.page! - i : (_page - i).toDouble();
            final angle = (-pos * math.pi / 2).clamp(-math.pi / 2, math.pi / 2);
            return Transform(
              alignment: pos > 0 ? Alignment.centerRight : Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(angle),
              child: child,
            );
          },
          child: _GroupPage(
            key: ValueKey(widget.groups[i].person.id),
            group: widget.groups[i],
            active: i == _page,
            onDone: _next,
            onBack: _previous,
          ),
        ),
      ),
    ),
  );
}

class _GroupPage extends StatefulWidget {
  const _GroupPage({super.key, required this.group, required this.active, required this.onDone, required this.onBack});
  final MomentGroup group;
  final bool active;
  final VoidCallback onDone;
  final VoidCallback onBack;

  @override
  State<_GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<_GroupPage> with SingleTickerProviderStateMixin {
  late final _progress = AnimationController(vsync: this, duration: MomentViewer.perMoment)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _forward();
    });
  final _reply = TextEditingController();
  final _focus = FocusNode();
  int _index = 0;
  bool _held = false;
  double _drag = 0;
  bool _sent = false;

  List<Moment> get _moments => widget.group.moments;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_sync);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_GroupPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
    if (!widget.active && old.active) _progress.stop();
  }

  void _start() {
    Deps.of(context).social!.markSeen(widget.group.person.id);
    _progress.forward(from: 0);
  }

  /// Paused while held or while the reply box has the keyboard.
  void _sync() {
    if (!widget.active) return;
    final paused = _held || _focus.hasFocus;
    paused ? _progress.stop() : _progress.forward();
    setState(() {});
  }

  void _forward() {
    if (_index + 1 < _moments.length) {
      setState(() => _index++);
      _progress.forward(from: 0);
    } else {
      widget.onDone();
    }
  }

  void _back() {
    if (_index > 0) {
      setState(() => _index--);
      _progress.forward(from: 0);
    } else {
      widget.onBack();
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final social = Deps.of(context).social!;
    _reply.clear();
    _focus.unfocus();
    setState(() => _sent = true);
    await social.replyToMoment(widget.group.person, _moments[_index], text);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _sent = false);
  }

  @override
  void dispose() {
    _progress.dispose();
    _reply.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final moment = _moments[_index];
    final person = widget.group.person;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => d.localPosition.dx < context.size!.width * 0.3 ? _back() : _forward(),
      onLongPressStart: (_) {
        _held = true;
        _sync();
      },
      onLongPressEnd: (_) {
        _held = false;
        _sync();
      },
      onVerticalDragUpdate: (d) => setState(() => _drag = math.max(0, _drag + d.delta.dy)),
      onVerticalDragEnd: (d) {
        if (_drag > 120 || d.primaryVelocity! > 700) return Navigator.of(context).pop();
        setState(() => _drag = 0);
      },
      child: Transform.translate(
        offset: Offset(0, _drag),
        child: Transform.scale(
          scale: 1 - math.min(_drag, 300) / 1500,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_drag > 0 ? 24 : 0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                  child: Semantics(
                    key: ValueKey(moment.id),
                    label: L10n.of(context).photoOf(moment.caption),
                    image: true,
                    child: NetImage(moment.image),
                  ),
                ),
                const _Shade(),
                // Buttons as well as taps: nobody has to know the gesture.
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _SideButton(
                      key: const Key('moment_prev'),
                      icon: Icons.chevron_left_rounded,
                      tooltip: L10n.of(context).storyPrevious,
                      onTap: _back,
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _SideButton(
                      key: const Key('moment_next'),
                      icon: Icons.chevron_right_rounded,
                      tooltip: L10n.of(context).storyNext,
                      onTap: _forward,
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: _Bars(count: _moments.length, index: _index, progress: _progress),
                      ),
                      _Header(person: person, time: moment.time),
                      const Spacer(),
                      if (moment.caption.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: Text(
                            moment.caption,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              shadows: [Shadow(color: Tokens.shadeDeep, blurRadius: 12)],
                            ),
                          ),
                        ),
                      AnimatedOpacity(
                        opacity: _sent ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: Tokens.onPhotoSoft, borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_rounded, size: 14, color: Tokens.acai),
                              const SizedBox(width: 6),
                              Text(
                                l.momentReplySent,
                                style: const TextStyle(
                                  color: Tokens.acaiInk,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(12, 0, 8, 10 + inset),
                        child: _ReplyBox(
                          controller: _reply,
                          focus: _focus,
                          hint: l.momentReplyHint(person.name.split(' ').first),
                          onSend: _send,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Darkens the top and bottom so the white text reads on any photo.
class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.18, 0.6, 1],
          colors: [Tokens.shade, Tokens.shadeClear, Tokens.shadeClear, Tokens.shadeDeep],
        ),
      ),
    ),
  );
}

/// One bar per moment: past ones full, the current one filling.
class _Bars extends StatelessWidget {
  const _Bars({required this.count, required this.index, required this.progress});
  final int count;
  final int index;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    builder: (context, _) => Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Container(
              height: 2.5,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(color: Tokens.onPhotoTrack, borderRadius: BorderRadius.circular(2)),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: i < index ? 1 : (i == index ? progress.value : 0),
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.person, required this.time});
  final Person person;
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
      child: Row(
        children: [
          Avatar(name: person.name, seed: person.id, mxc: person.avatar, radius: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(ago(time, DateTime.now(), l), style: const TextStyle(color: Tokens.onPhotoMuted, fontSize: 14)),
          const Spacer(),
          IconButton(
            key: const Key('moment_close'),
            tooltip: l.close,
            color: Colors.white,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 28),
          ),
        ],
      ),
    );
  }
}

class _ReplyBox extends StatelessWidget {
  const _ReplyBox({required this.controller, required this.focus, required this.hint, required this.onSend});
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(26)),
      borderSide: BorderSide(color: Tokens.onPhotoFaint),
    );
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('moment_reply'),
            controller: controller,
            focusNode: focus,
            cursorColor: Tokens.ipe,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(color: Colors.white, fontSize: 15.5),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Tokens.onPhotoMuted, fontSize: 15.5),
              filled: true,
              fillColor: Tokens.shadeLight,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(borderSide: const BorderSide(color: Colors.white, width: 1.5)),
            ),
            onSubmitted: (_) => onSend(),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, v, _) => IconButton(
            key: const Key('moment_send'),
            tooltip: L10n.of(context).send,
            color: v.text.trim().isEmpty ? Colors.white : Tokens.ipe,
            onPressed: v.text.trim().isEmpty ? null : onSend,
            disabledColor: Colors.white,
            icon: Icon(v.text.trim().isEmpty ? Icons.favorite_border_rounded : Icons.send_rounded, size: 28),
          ),
        ),
      ],
    );
  }
}

/// A round, see-through button over the photo (next / previous).
class _SideButton extends StatelessWidget {
  const _SideButton({super.key, required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    style: IconButton.styleFrom(
      backgroundColor: Tokens.shade,
      foregroundColor: Colors.white,
      fixedSize: const Size.square(48),
    ),
    icon: Icon(icon, size: 30),
  );
}
