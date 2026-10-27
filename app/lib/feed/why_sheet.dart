import 'package:flutter/material.dart';

import '../common/deps.dart';
import '../common/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';
import 'algorithm_screen.dart';

String reasonText(Reason r, L10n l) => switch (r.kind) {
  ReasonKind.follows => l.reasonFollows(r.value),
  ReasonKind.popular => l.reasonPopular(r.value),
  ReasonKind.near => l.reasonNear(r.value),
  ReasonKind.topic => l.topicLabel(r.value),
  ReasonKind.community => l.reasonCommunity(r.value),
};

IconData reasonIcon(ReasonKind k) => switch (k) {
  ReasonKind.follows => Icons.person_outline_rounded,
  ReasonKind.popular => Icons.trending_up_rounded,
  ReasonKind.near => Icons.place_outlined,
  ReasonKind.topic => Icons.tag_rounded,
  ReasonKind.community => Icons.groups_outlined,
};

/// "Por que estou vendo isto?": the reason, more or less of it, the topic
/// switch, and the way to the algorithm choice.
Future<void> showWhySheet(BuildContext context, Post post) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _WhySheet(post: post, messenger: ScaffoldMessenger.of(context)),
);

class _WhySheet extends StatelessWidget {
  const _WhySheet({required this.post, required this.messenger});
  final Post post;
  final ScaffoldMessengerState messenger;

  void _answer(BuildContext context, bool more) {
    final l = L10n.of(context);
    final social = Deps.of(context).social!;
    more ? social.moreLike(post.id) : social.lessLike(post.id);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(more ? l.moreLikeThisDone : l.lessLikeThisDone)));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ChatColors.of(context);
    final social = Deps.of(context).social!;
    final reason = post.reason;
    final topic = post.topic;
    return SafeArea(
      child: Padding(
        key: const Key('why_sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.whyThis, style: theme.textTheme.titleLarge),
            const SizedBox(height: 14),
            if (reason != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(reasonIcon(reason.kind), size: 20, color: colors.onTint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        reasonText(reason, l),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.onTint),
                      ),
                    ),
                  ],
                ),
              ),
            if (topic != null)
              ValueListenableBuilder<Set<String>>(
                valueListenable: social.hiddenTopics,
                builder: (context, hidden, _) => SwitchListTile(
                  key: const Key('why_topic_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.topicLabel(topic)),
                  subtitle: Text(l.topicOn),
                  value: !hidden.contains(topic),
                  onChanged: (on) => social.setTopic(topic, on),
                ),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              key: const Key('more_like_this'),
              onPressed: () => _answer(context, true),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l.moreLikeThis),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('less_like_this'),
              onPressed: () => _answer(context, false),
              icon: const Icon(Icons.remove_rounded, size: 18),
              label: Text(l.lessLikeThis),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              key: const Key('why_algorithm'),
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute<void>(builder: (_) => const AlgorithmScreen()));
              },
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(l.chooseAlgorithm),
            ),
            Row(
              children: [
                Icon(Icons.code_rounded, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(l.algorithmOpen, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Por que este anúncio?": topic only, never chats, no tracking.
Future<void> showAdSheet(BuildContext context, Post post) {
  final l = L10n.of(context);
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final colors = ChatColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        key: const Key('ad_sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_outlined, color: colors.accent),
                const SizedBox(width: 10),
                Text(l.whyThisAd, style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l.whyThisAdBody(post.topic ?? ''),
              style: TextStyle(fontSize: 15.5, height: 22 / 15.5, color: scheme.onSurface),
            ),
            const SizedBox(height: 12),
            Text(l.adsRule, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('ad_sheet_close'),
                onPressed: () => Navigator.pop(context),
                child: Text(l.gotIt),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
