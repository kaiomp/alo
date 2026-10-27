import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/motion.dart';
import '../common/simple_mode.dart';
import '../common/net_image.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../l10n/app_localizations.dart';
import '../profile/person_screen.dart';
import '../services/social_service.dart';
import 'reel.dart';
import 'why_sheet.dart';

/// One post: author, text, photo and the like / reply / repost / share row.
/// A double tap on the photo likes it with a heart that pops over it.
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onRepost,
    required this.onShare,
    this.onOpen,
    this.onOpenReel,
    this.large = false,
    this.showReason = false,
  });

  final Post post;
  final VoidCallback onLike;
  final VoidCallback onRepost;
  final VoidCallback onShare;

  /// Opens the post with its replies; null on the post's own page.
  final VoidCallback? onOpen;

  /// Opens the full-screen reel viewer at this post.
  final VoidCallback? onOpenReel;

  /// The post's own page: bigger text.
  final bool large;

  /// "Para você": the reason line and the "Por que estou vendo isto?" menu.
  final bool showReason;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late final _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _doubleTap() {
    HapticFeedback.lightImpact();
    if (!reduceMotion(context)) _burst.forward(from: 0);
    if (!widget.post.liked) widget.onLike();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final post = widget.post;
    final muted = scheme.onSurfaceVariant;
    final image = post.image;
    return InkWell(
      onTap: widget.onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.sponsored) _SponsoredLine(post: post),
            if (widget.showReason && post.reason != null) _ReasonLine(post: post),
            if (post.repostedBy != null)
              Padding(
                padding: const EdgeInsets.only(left: 30, bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.repeat_rounded, size: 15, color: muted),
                    const SizedBox(width: 6),
                    Text(
                      l.repostedBy(post.repostedBy!.name.split(' ').first),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: muted),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => PersonScreen.open(context, post.author),
                  child: _Avatars(post: post),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Byline(
                        post: post,
                        onMore: widget.showReason && !post.sponsored ? () => showWhySheet(context, post) : null,
                      ),
                      if (post.paidPartner != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            l.paidPartnership(post.paidPartner!.handle.split('@').first),
                            key: Key('paid_${post.id}'),
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: muted),
                          ),
                        ),
                      if (post.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 4),
                          child: Text(
                            post.text,
                            style: TextStyle(
                              fontSize: widget.large ? 18 : 16,
                              height: widget.large ? 25 / 18 : 23 / 16,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      if (post.isReel)
                        Padding(
                          padding: const EdgeInsets.only(top: 10, right: 4),
                          child: ReelInline(post: post, onOpen: widget.onOpenReel ?? () {}),
                        )
                      else if (image != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10, right: 4),
                          child: GestureDetector(
                            onDoubleTap: _doubleTap,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: AspectRatio(
                                aspectRatio: post.imageRatio.clamp(0.8, 1.8),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    DecoratedBox(
                                      position: DecorationPosition.foreground,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      // Alt text: the post's own words.
                                      child: Semantics(
                                        label: l.photoOf(post.text),
                                        image: true,
                                        child: NetImage(image, key: Key('post_image_${post.id}')),
                                      ),
                                    ),
                                    _HeartBurst(animation: _burst),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      _Actions(widget: widget),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Byline extends StatelessWidget {
  const _Byline({required this.post, this.onMore});
  final Post post;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final l = L10n.of(context);
    final co = post.coAuthor;
    final name = co == null ? post.author.name : l.collabNames(post.author.name, co.name);
    final line = Row(
      children: [
        Flexible(
          flex: 5,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
        ),
        if (post.author.business != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.storefront_outlined, size: 15, color: ChatColors.of(context).accent),
        ],
        const SizedBox(width: 6),
        Flexible(
          flex: 3,
          child: Text(
            co == null ? '${ago(post.time, DateTime.now(), l)} · ${post.author.at}' : ago(post.time, DateTime.now(), l),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: muted, fontFeatures: tabularFigures),
          ),
        ),
      ],
    );
    if (onMore == null) return line;
    return Row(
      children: [
        Expanded(child: line),
        SizedBox(
          width: 48,
          height: 40,
          child: IconButton(
            key: Key('why_${post.id}'),
            tooltip: l.whyThis,
            padding: EdgeInsets.zero,
            iconSize: 20,
            color: muted,
            onPressed: onMore,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ),
      ],
    );
  }
}

/// The author's photo; a collab adds the second author's, overlapping.
class _Avatars extends StatelessWidget {
  const _Avatars({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final a = post.author;
    final co = post.coAuthor;
    final main = Avatar(name: a.name, seed: a.id, mxc: a.avatar, radius: 21);
    if (co == null) return main;
    return SizedBox(
      width: 42,
      height: 46,
      child: Stack(
        children: [
          main,
          Positioned(
            right: -4,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
              child: Avatar(name: co.name, seed: co.id, mxc: co.avatar, radius: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Porque você segue @ju.ferreira": tap it for the reasons sheet.
class _ReasonLine extends StatelessWidget {
  const _ReasonLine({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final r = post.reason!;
    // Plain text: the "⋯" button next to the name opens the reasons.
    return KeyedSubtree(
      key: Key('reason_${post.id}'),
      child: Padding(
        padding: const EdgeInsets.only(left: 30, bottom: 6),
        child: Row(
          children: [
            Icon(reasonIcon(r.kind), size: 15, color: muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                reasonText(r, L10n.of(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Patrocinado · Por que este anúncio?", always on top of an ad.
class _SponsoredLine extends StatelessWidget {
  const _SponsoredLine({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final colors = ChatColors.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      key: Key('why_ad_${post.id}'),
      onTap: () => showAdSheet(context, post),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.only(left: 30),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(6)),
              child: Text(
                l.sponsored,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.onTint),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l.whyThisAd,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: muted,
                  decoration: TextDecoration.underline,
                  decorationColor: muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.widget});
  final PostCard widget;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final post = widget.post;
    final colors = ChatColors.of(context);
    // Calm option: the heart stays, the number goes.
    final hide = Deps.of(context).wellbeing?.hideLikes;
    final simple = SimpleMode.of(context);
    Widget row(bool hideLikes) => Wrap(
      children: [
        _ActionButton(
          key: Key('like_${post.id}'),
          showLabel: simple,
          tooltip: l.like,
          count: hideLikes ? null : post.likes,
          active: post.liked,
          activeColor: Theme.of(context).brightness == Brightness.dark ? Tokens.likeLight : Tokens.like,
          icon: Icons.favorite_border_rounded,
          activeIcon: Icons.favorite_rounded,
          pop: true,
          onTap: widget.onLike,
        ),
        _ActionButton(
          key: Key('reply_${post.id}'),
          showLabel: simple,
          tooltip: l.reply,
          count: post.replies,
          icon: Icons.chat_bubble_outline_rounded,
          onTap: widget.onOpen ?? () {},
        ),
        _ActionButton(
          key: Key('repost_${post.id}'),
          showLabel: simple,
          tooltip: l.repost,
          count: post.reposts,
          active: post.reposted,
          activeColor: colors.accent,
          icon: Icons.repeat_rounded,
          onTap: widget.onRepost,
        ),
        _ActionButton(
          key: Key('share_${post.id}'),
          showLabel: simple,
          tooltip: l.share,
          icon: Icons.ios_share_rounded,
          onTap: widget.onShare,
        ),
      ],
    );
    return hide == null ? row(false) : ValueListenableBuilder(valueListenable: hide, builder: (_, h, _) => row(h));
  }
}

/// Icon and count; [pop] gives the like its springy scale.
class _ActionButton extends StatefulWidget {
  const _ActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.activeIcon,
    this.count,
    this.active = false,
    this.activeColor,
    this.pop = false,
    this.showLabel = false,
  });
  final String tooltip;

  /// Modo simples: the word next to the icon.
  final bool showLabel;
  final IconData icon;
  final IconData? activeIcon;
  final int? count;
  final bool active;
  final Color? activeColor;
  final bool pop;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> with SingleTickerProviderStateMixin {
  /// Up to 1.35x, then a springy settle back.
  static final _pop = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 70),
  ]);

  late final _scale = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void didUpdateWidget(_ActionButton old) {
    super.didUpdateWidget(old);
    if (widget.pop && widget.active && !old.active && !reduceMotion(context)) {
      HapticFeedback.selectionClick();
      _scale.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = widget.active ? widget.activeColor ?? muted : muted;
    final n = widget.count;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Semantics(
        button: true,
        selected: widget.active,
        label: n == null || n == 0 ? widget.tooltip : '${widget.tooltip}, ${count(n, l)}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: widget.onTap,
          // 48 px tall at least: easy to hit.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _scale.drive(_pop),
                    child: Icon(widget.active ? widget.activeIcon ?? widget.icon : widget.icon, size: 22, color: color),
                  ),
                  if (widget.showLabel) ...[
                    const SizedBox(width: 5),
                    Text(
                      widget.tooltip,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
                    ),
                  ],
                  if (n != null && n > 0) ...[
                    const SizedBox(width: 5),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, a) => SlideTransition(
                        position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(a),
                        child: FadeTransition(opacity: a, child: child),
                      ),
                      child: Text(
                        count(n, l),
                        key: ValueKey(n),
                        style: TextStyle(fontSize: 14.5, color: color, fontFeatures: tabularFigures),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The white heart over a photo after a double tap.
class _HeartBurst extends StatelessWidget {
  const _HeartBurst({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        if (t == 0 || t == 1) return const SizedBox.shrink();
        final scale = Curves.elasticOut.transform((t / 0.55).clamp(0, 1));
        final opacity = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
        return Center(
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: const Icon(
                Icons.favorite_rounded,
                size: 96,
                color: Colors.white,
                shadows: [Shadow(color: Tokens.shade, blurRadius: 24)],
              ),
            ),
          ),
        );
      },
    ),
  );
}
