import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/motion.dart';
import '../common/net_image.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';

VideoPlayerController _controllerFor(Post post) => VideoPlayerController.networkUrl(
  Uri.base.resolveUri(post.video!),
  videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
);

/// A video that fills its box like `BoxFit.cover`, over its poster.
class _Cover extends StatelessWidget {
  const _Cover({super.key, required this.post, required this.controller});
  final Post post;
  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (post.image != null) NetImage(post.image!),
        if (c != null)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (context, v, _) => !v.isInitialized
                ? const SizedBox.shrink()
                : FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    // The web <video> must not take taps and swipes from the
                    // card and the viewer around it.
                    child: IgnorePointer(
                      child: SizedBox(width: v.size.width, height: v.size.height, child: VideoPlayer(c)),
                    ),
                  ),
          ),
      ],
    );
  }
}

/// A reel in the feed: plays by itself, muted and looping, while at least
/// 60% of it is on screen and its tab and route are showing; pauses
/// otherwise. A tap opens the full-screen viewer.
class ReelInline extends StatefulWidget {
  const ReelInline({super.key, required this.post, required this.onOpen});
  final Post post;
  final VoidCallback onOpen;

  @override
  State<ReelInline> createState() => _ReelInlineState();
}

class _ReelInlineState extends State<ReelInline> {
  VideoPlayerController? _c;
  ScrollPosition? _position;
  ValueListenable<bool>? _autoplay;
  bool _shown = true;
  bool _playing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hidden: another tab (IndexedStack) or a route on top (TickerMode).
    _shown = TickerMode.valuesOf(context).enabled && Visibility.of(context);
    _position?.removeListener(_check);
    _position = Scrollable.maybeOf(context)?.position?..addListener(_check);
    _autoplay?.removeListener(_check);
    _autoplay = Deps.of(context).wellbeing?.autoplay?..addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  double _visibleFraction() {
    final box = context.findRenderObject();
    final viewport = _position?.context.storageContext.findRenderObject();
    if (box is! RenderBox || viewport is! RenderBox || !box.attached || !viewport.attached) return 0;
    final me = box.localToGlobal(Offset.zero) & box.size;
    final view = viewport.localToGlobal(Offset.zero) & viewport.size;
    final overlap = me.intersect(view);
    if (overlap.isEmpty || me.height == 0) return 0;
    return overlap.height / me.height;
  }

  Future<void> _check() async {
    if (!mounted) return;
    final want = _shown && (_autoplay?.value ?? true) && _visibleFraction() >= 0.6;
    if (want == _playing) return;
    _playing = want;
    if (want) {
      final c = _c ??= _controllerFor(widget.post);
      if (!c.value.isInitialized) {
        await c.initialize();
        await c.setVolume(0);
        await c.setLooping(true);
        if (mounted) setState(() {});
      }
      if (_playing && mounted) await c.play();
    } else {
      await _c?.pause();
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _autoplay?.removeListener(_check);
    _c?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    _playing = false;
    await _c?.pause();
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return GestureDetector(
      onTap: _open,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Semantics(
                label: l.videoOf(widget.post.text),
                child: _Cover(key: Key('reel_${widget.post.id}'), post: widget.post, controller: _c),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Semantics(
                  label: l.reel,
                  child: const Icon(
                    Icons.slow_motion_video_rounded,
                    color: Colors.white,
                    size: 22,
                    shadows: [Shadow(color: Tokens.shadeDeep, blurRadius: 8)],
                  ),
                ),
              ),
              if (_c == null || !(_autoplay?.value ?? true))
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Tokens.onPhotoSoft,
                    size: 56,
                    shadows: [Shadow(color: Tokens.shadeDeep, blurRadius: 16)],
                  ),
                ),
              const Positioned(
                right: 10,
                bottom: 10,
                child: Icon(
                  Icons.volume_off_rounded,
                  color: Colors.white,
                  size: 18,
                  shadows: [Shadow(color: Tokens.shadeDeep, blurRadius: 8)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen reels: swipe up for the next one; like, comment and share on
/// the right; the author and caption at the bottom.
class ReelViewer extends StatefulWidget {
  const ReelViewer({super.key, required this.reels, required this.initial});
  final List<Post> reels;
  final int initial;

  static Future<void> open(BuildContext context, List<Post> reels, Post post) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) =>
          ReelViewer(reels: reels, initial: math.max(0, reels.indexWhere((r) => r.id == post.id))),
      transitionsBuilder: (_, a, _, child) {
        final curve = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curve), child: child),
        );
      },
    ),
  );

  @override
  State<ReelViewer> createState() => _ReelViewerState();
}

class _ReelViewerState extends State<ReelViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int by) => _pages.animateToPage(
    _page + by,
    duration: motion(context, const Duration(milliseconds: 320)) + const Duration(milliseconds: 1),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            key: const Key('reel_pages'),
            controller: _pages,
            scrollDirection: Axis.vertical,
            itemCount: widget.reels.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) =>
                _ReelPage(key: ValueKey(widget.reels[i].id), post: widget.reels[i], active: i == _page),
          ),
          // Arrows as well as swipes: nobody has to know the gesture.
          Positioned(
            right: 8,
            top: 0,
            bottom: 240,
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Arrow(
                    key: const Key('reel_prev'),
                    icon: Icons.keyboard_arrow_up_rounded,
                    tooltip: L10n.of(context).storyPrevious,
                    onTap: _page == 0 ? null : () => _go(-1),
                  ),
                  const SizedBox(height: 8),
                  _Arrow(
                    key: const Key('reel_next'),
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: L10n.of(context).storyNext,
                    onTap: _page == widget.reels.length - 1 ? null : () => _go(1),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: IconButton(
                key: const Key('reel_close'),
                tooltip: L10n.of(context).close,
                color: Colors.white,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 28),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReelPage extends StatefulWidget {
  const _ReelPage({super.key, required this.post, required this.active});
  final Post post;
  final bool active;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  late final _c = _controllerFor(widget.post);

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) async {
      await _c.setVolume(0);
      await _c.setLooping(true);
      if (!mounted) return;
      setState(() {});
      if (widget.active) await _c.play();
    });
  }

  @override
  void didUpdateWidget(_ReelPage old) {
    super.didUpdateWidget(old);
    if (!_c.value.isInitialized || widget.active == old.active) return;
    widget.active ? _c.play() : _c.pause();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final social = Deps.of(context).social!;
    final p = widget.post;
    return ValueListenableBuilder<List<Post>>(
      valueListenable: social.forYou,
      builder: (context, posts, _) {
        final post = posts.where((x) => x.id == p.id).firstOrNull ?? p;
        return Stack(
          fit: StackFit.expand,
          children: [
            _Cover(post: post, controller: _c),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.2, 0.6, 1],
                    colors: [Tokens.shade, Tokens.shadeClear, Tokens.shadeClear, Tokens.shadeDeeper],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 96,
              child: Column(
                children: [
                  _Side(
                    key: Key('reel_like_${post.id}'),
                    icon: post.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: post.liked ? Tokens.likeLight : Colors.white,
                    label: count(post.likes, l),
                    tooltip: l.like,
                    onTap: () => social.toggleLike(post.id),
                  ),
                  _Side(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: count(post.replies, l),
                    tooltip: l.reply,
                    onTap: () {},
                  ),
                  _Side(icon: Icons.ios_share_rounded, label: l.share, tooltip: l.share, onTap: () {}),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 80,
              bottom: 28,
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Avatar(name: post.author.name, seed: post.author.id, mxc: post.author.avatar, radius: 17),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            post.author.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(post.author.at, style: const TextStyle(color: Tokens.onPhotoMuted, fontSize: 13.5)),
                      ],
                    ),
                    if (post.paidPartner != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          l.paidPartnership(post.paidPartner!.handle.split('@').first),
                          style: const TextStyle(
                            color: Tokens.onPhotoSoft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (post.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          post.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            height: 20 / 14.5,
                            shadows: [Shadow(color: Tokens.shadeDeep, blurRadius: 8)],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.color = Colors.white,
  });
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      children: [
        IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(
            icon,
            size: 32,
            color: color,
            shadows: const [Shadow(color: Tokens.shadeDeep, blurRadius: 10)],
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Tokens.shadeDeep, blurRadius: 8)],
          ),
        ),
      ],
    ),
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow({super.key, required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    style: IconButton.styleFrom(
      backgroundColor: Tokens.shade,
      foregroundColor: Colors.white,
      disabledBackgroundColor: Tokens.shadeLight,
      disabledForegroundColor: Tokens.onPhotoTrack,
      fixedSize: const Size.square(48),
    ),
    icon: Icon(icon, size: 30),
  );
}
