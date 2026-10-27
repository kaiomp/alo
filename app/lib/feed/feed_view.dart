import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/deps.dart';
import '../common/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';
import 'post_card.dart';
import 'post_screen.dart';

/// Praça: everyone I follow, newest first, never ranked. The label on top
/// says so; a tap explains it.
class FeedView extends StatefulWidget {
  const FeedView({super.key});

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  /// Posts on screen when the tab opened; newer ones slide in.
  Set<String>? _known;

  @override
  Widget build(BuildContext context) {
    final social = Deps.of(context).social!;
    final l = L10n.of(context);
    return ValueListenableBuilder<List<Post>>(
      valueListenable: social.feed,
      builder: (context, posts, _) {
        final known = _known ??= {for (final p in posts) p.id};
        return RefreshIndicator(
          onRefresh: social.refresh,
          child: CustomScrollView(
            key: const Key('feed'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: ChronologicalLabel()),
              SliverList.separated(
                itemCount: posts.length,
                separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                itemBuilder: (context, i) {
                  final post = posts[i];
                  final card = PostCard(
                    key: Key('post_${post.id}'),
                    post: post,
                    onLike: () => social.toggleLike(post.id),
                    onRepost: () => repost(context, social, post),
                    onShare: () => sharePost(context, post),
                    onOpen: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => PostScreen(postId: post.id))),
                  );
                  if (known.contains(post.id)) return card;
                  known.add(post.id);
                  return _SlideIn(key: ValueKey('in_${post.id}'), child: card);
                },
              ),
              SliverToBoxAdapter(
                child: _CaughtUp(title: l.feedUpToDate, body: l.feedUpToDateBody),
              ),
            ],
          ),
        );
      },
    );
  }
}

void repost(BuildContext context, SocialService social, Post post) {
  social.toggleRepost(post.id);
  if (!post.reposted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(L10n.of(context).reposted)));
  }
}

Future<void> sharePost(BuildContext context, Post post) async {
  final l = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final user = post.author.handle.split('@');
  await Clipboard.setData(ClipboardData(text: 'https://${user.last}/@${user.first}/${post.id}'));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l.linkCopied)));
}

/// "Em ordem de chegada · sem algoritmo"; a tap shows what that means.
class ChronologicalLabel extends StatefulWidget {
  const ChronologicalLabel({super.key});

  @override
  State<ChronologicalLabel> createState() => _ChronologicalLabelState();
}

class _ChronologicalLabelState extends State<ChronologicalLabel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final colors = ChatColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: colors.tint,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const Key('chronological'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 17, color: colors.onTint),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.chronological,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colors.onTint),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 260),
                        child: Icon(Icons.expand_more_rounded, size: 20, color: colors.onTint),
                      ),
                    ],
                  ),
                  if (_open)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 25),
                      child: Text(
                        l.chronologicalExplain,
                        style: TextStyle(fontSize: 13.5, height: 19 / 13.5, color: scheme.onSurface),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A new post slides down into place and fades in.
class _SlideIn extends StatefulWidget {
  const _SlideIn({super.key, required this.child});
  final Widget child;

  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..forward();

  /// Opens in the first half second; the highlight fades after that.
  late final _in = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.22, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _in.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = ChatColors.of(context).tint;
    return SizeTransition(
      sizeFactor: _in,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _in,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => ColoredBox(
            color: tint.withValues(alpha: 0.7 * (1 - const Interval(0.5, 1).transform(_c.value))),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The end of the feed: no infinite scroll, no suggestions, no ads.
class _CaughtUp extends StatelessWidget {
  const _CaughtUp({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    return Container(
      key: const Key('feed_end'),
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 120),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 36, color: colors.onTint),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 21 / 15, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
