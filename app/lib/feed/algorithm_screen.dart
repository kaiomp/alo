import 'package:flutter/material.dart';

import '../common/deps.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../common/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';

/// "Escolha seu algoritmo": Chama's own feeds, feeds made by the community,
/// and the topics to leave out. The choice applies to "Para você" at once.
class AlgorithmScreen extends StatelessWidget {
  const AlgorithmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final social = Deps.of(context).social!;
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final own = social.algorithms.where((a) => a.by == null);
    final community = social.algorithms.where((a) => a.by != null);
    return Scaffold(
      appBar: AppBar(title: Text(l.chooseAlgorithm)),
      body: ListenableBuilder(
        listenable: Listenable.merge([social.algorithm, social.hiddenTopics]),
        builder: (context, _) => ListView(
          key: const Key('algorithm_page'),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.code_rounded, color: colors.onTint),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.algorithmOpen,
                      style: TextStyle(fontSize: 14.5, height: 20 / 14.5, color: colors.onTint),
                    ),
                  ),
                ],
              ),
            ),
            SectionHeader(l.algorithmsChama),
            for (final a in own) _Choice(choice: a, selected: social.algorithm.value == a.id),
            SectionHeader(l.communityFeeds),
            for (final a in community) _Choice(choice: a, selected: social.algorithm.value == a.id),
            SectionHeader(l.topicsTitle),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in social.topics)
                    FilterChip(
                      key: Key('topic_$t'),
                      label: Text(t),
                      selected: !social.hiddenTopics.value.contains(t),
                      showCheckmark: true,
                      checkmarkColor: colors.onTint,
                      selectedColor: colors.tint,
                      backgroundColor: scheme.surfaceContainer,
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                      labelStyle: TextStyle(
                        fontSize: 14,
                        color: social.hiddenTopics.value.contains(t) ? scheme.onSurfaceVariant : colors.onTint,
                        decoration: social.hiddenTopics.value.contains(t) ? TextDecoration.lineThrough : null,
                      ),
                      onSelected: (on) => social.setTopic(t, on),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.choice, required this.selected});
  final FeedChoice choice;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final c = choice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: selected ? colors.tint : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: InkWell(
          key: Key('algorithm_${c.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => Deps.of(context).social!.chooseAlgorithm(c.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(c.about, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
                      if (c.by != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l.communityBy(c.by!, count(c.users ?? 0, l)),
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.accent),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
