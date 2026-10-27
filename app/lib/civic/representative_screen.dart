import 'package:flutter/material.dart';

import '../common/avatar.dart';
import '../common/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/civic_service.dart';
import 'civic_widgets.dart';

/// One representative's record: attendance, spending, votes and bills,
/// each with where the fact comes from.
class RepresentativeScreen extends StatelessWidget {
  const RepresentativeScreen({super.key, required this.representative});
  final Representative representative;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final r = representative;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final biggest = r.spendingItems.fold(0, (m, i) => i.$2 > m ? i.$2 : m);
    return Scaffold(
      appBar: AppBar(title: Text(r.name)),
      body: ListView(
        key: const Key('rep_page'),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Row(
              children: [
                Avatar(name: r.name, seed: r.id, radius: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SampleTag(),
                      const SizedBox(height: 6),
                      Text(r.name, style: theme.textTheme.titleLarge),
                      Text(r.role, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          CivicCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CivicLabel(l.attendance),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      percent(r.present / r.sessions),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l.attendanceValue(r.present, r.sessions),
                      style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ShareBar(share: r.present / r.sessions),
                SourceLabel(r.source),
              ],
            ),
          ),
          CivicCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CivicLabel(l.spending(r.spendingYear)),
                const SizedBox(height: 8),
                Text(
                  reais(r.spending, l),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
                ),
                const SizedBox(height: 10),
                for (final (what, value) in r.spendingItems)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(what, style: const TextStyle(fontSize: 14))),
                            Text(
                              reais(value, l),
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.onSurfaceVariant,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ShareBar(share: value / biggest, height: 6),
                      ],
                    ),
                  ),
                SourceLabel(r.source),
              ],
            ),
          ),
          CivicCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CivicLabel(l.recentVotes),
                for (final v in r.votes)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                              Text(v.bill, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        _ChoicePill(choice: v.choice),
                      ],
                    ),
                  ),
                SourceLabel(r.source),
              ],
            ),
          ),
          CivicCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CivicLabel(l.billsAuthored),
                for (final b in r.bills)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined, size: 18, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(child: Text(b, style: const TextStyle(fontSize: 14.5))),
                      ],
                    ),
                  ),
                SourceLabel(r.source),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sim / Não / Abstenção in neutral tones: no colour says which is right.
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({required this.choice});
  final Choice choice;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final yes = choice == Choice.yes;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: yes ? colors.tint : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        choiceLabel(choice, L10n.of(context)),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: yes ? colors.onTint : scheme.onSurface),
      ),
    );
  }
}
