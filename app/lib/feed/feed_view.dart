import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/deps.dart';
import '../common/motion.dart';
import '../common/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';
import 'algorithm_screen.dart';
import 'post_card.dart';
import 'post_screen.dart';
import 'reel.dart';

/// The feed tab: "Para você" (recommended, each post says why) and
/// "Seguindo" (people I follow, newest first, with an end). The tune button
/// opens "Escolha seu algoritmo".
class FeedView extends StatefulWidget {
  const FeedView({super.key});

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TabBar(
                controller: _tabs,
                labelColor: scheme.onSurface,
                unselectedLabelColor: scheme.onSurfaceVariant,
                labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                indicatorColor: scheme.primary,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: scheme.outlineVariant,
                tabs: [
                  Tab(key: const Key('tab_for_you'), text: l.forYou),
                  Tab(key: const Key('tab_following'), text: l.followingTab),
                ],
              ),
            ),
            IconButton(
              key: const Key('choose_algorithm'),
              tooltip: l.chooseAlgorithm,
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AlgorithmScreen())),
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        Expanded(
          child: IndexedStack(index: _tabs.index, children: const [_ForYou(), _Following()]),
        ),
      ],
    );
  }
}

PostCard _card(BuildContext context, SocialService social, Post post, List<Post> all, {bool reasons = false}) =>
    PostCard(
      key: Key('post_${post.id}'),
      post: post,
      showReason: reasons,
      onLike: () => social.toggleLike(post.id),
      onRepost: () => repost(context, social, post),
      onShare: () => sharePost(context, post),
      onOpen: post.isReel
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PostScreen(postId: post.id))),
      onOpenReel: () => ReelViewer.open(context, [
        for (final p in all)
          if (p.isReel) p,
      ], post),
    );

/// "Para você": the chosen algorithm's picks, ending honestly too.
class _ForYou extends StatelessWidget {
  const _ForYou();

  @override
  Widget build(BuildContext context) {
    final social = Deps.of(context).social!;
    final l = L10n.of(context);
    return ValueListenableBuilder<List<Post>>(
      valueListenable: social.forYou,
      builder: (context, posts, _) => RefreshIndicator(
        onRefresh: social.refresh,
        child: CustomScrollView(
          key: const Key('feed_for_you'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverList.separated(
              itemCount: posts.length,
              separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
              itemBuilder: (context, i) => _card(context, social, posts[i], posts, reasons: true),
            ),
            SliverToBoxAdapter(
              child: _CaughtUp(
                key: const Key('for_you_end'),
                title: l.forYouEnd,
                body: l.forYouEndBody,
                action: l.chooseAlgorithm,
                onAction: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AlgorithmScreen())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Seguindo": everyone I follow, newest first, and then it ends.
class _Following extends StatefulWidget {
  const _Following();

  @override
  State<_Following> createState() => _FollowingState();
}

class _FollowingState extends State<_Following> {
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
                  final card = _card(context, social, post, posts);
                  if (known.contains(post.id)) return card;
                  known.add(post.id);
                  return _SlideIn(key: ValueKey('in_${post.id}'), child: card);
                },
              ),
              SliverToBoxAdapter(
                child: _CaughtUp(key: const Key('feed_end'), title: l.feedUpToDate, body: l.feedUpToDateBody),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Reposts (or takes it back), with "Desfazer" instead of a question.
void repost(BuildContext context, SocialService social, Post post) {
  final l = L10n.of(context);
  social.toggleRepost(post.id);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(post.reposted ? l.repostUndone : l.reposted),
        action: SnackBarAction(label: l.undo, onPressed: () => social.toggleRepost(post.id)),
      ),
    );
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
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
    ..forward(from: reduceMotion(context) ? 1 : 0);

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

/// The end of a feed: no infinite scroll, no filler.
class _CaughtUp extends StatelessWidget {
  const _CaughtUp({super.key, required this.title, required this.body, this.action, this.onAction});
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 120),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 36, color: colors.onTint),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 21 / 15, color: scheme.onSurfaceVariant),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(onPressed: onAction, icon: const Icon(Icons.tune_rounded, size: 18), label: Text(action!)),
          ],
        ],
      ),
    );
  }
}
