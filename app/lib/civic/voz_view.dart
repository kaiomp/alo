import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../l10n/app_localizations.dart';
import '../services/civic_service.dart';
import 'civic_widgets.dart';
import 'consulta_screen.dart';
import 'representative_screen.dart';

/// Voz: society taking part in politics, for every side. Acompanhe (facts
/// with sources), Vote (consultations), Proponha (petitions), Mobilize
/// (open channels). Nothing is ranked.
class VozView extends StatefulWidget {
  const VozView({super.key});

  @override
  State<VozView> createState() => _VozViewState();
}

class _VozViewState extends State<VozView> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final sections = [l.civicFollow, l.civicVote, l.civicPropose, l.civicMobilize];
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Row(
            children: [
              for (final (i, label) in sections.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('voz_section_$i'),
                    label: Text(label),
                    selected: _section == i,
                    showCheckmark: false,
                    shape: const StadiumBorder(),
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    labelPadding: EdgeInsets.zero,
                    backgroundColor: scheme.surfaceContainer,
                    selectedColor: colors.tint,
                    labelStyle: TextStyle(
                      fontSize: 14,
                      fontWeight: _section == i ? FontWeight.w600 : FontWeight.w500,
                      color: _section == i ? colors.onTint : scheme.onSurfaceVariant,
                    ),
                    onSelected: (_) => setState(() => _section = i),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (_section) {
              0 => const _Follow(key: Key('voz_follow')),
              1 => const _Vote(key: Key('voz_vote')),
              2 => const _Propose(key: Key('voz_propose')),
              _ => const _Mobilize(key: Key('voz_mobilize')),
            },
          ),
        ),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13.5, height: 19 / 13.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        const SampleTag(),
      ],
    ),
  );
}

class _Follow extends StatelessWidget {
  const _Follow({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final civic = Deps.of(context).civic!;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Intro(l.civicIntro),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: CivicLabel(l.yourRepresentatives(civic.place)),
        ),
        for (final r in civic.representatives)
          CivicCard(
            key: Key('rep_${r.id}'),
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => RepresentativeScreen(representative: r))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Avatar(name: r.name, seed: r.id, radius: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          Text(r.role, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(label: l.attendance, value: percent(r.present / r.sessions)),
                    ),
                    Expanded(
                      child: _Stat(label: l.spending(r.spendingYear), value: reais(r.spending, l)),
                    ),
                  ],
                ),
                SourceLabel(r.source),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            fontFeatures: tabularFigures,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Vote extends StatelessWidget {
  const _Vote({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final civic = Deps.of(context).civic!;
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    return ValueListenableBuilder<List<Consulta>>(
      valueListenable: civic.consultas,
      builder: (context, consultas, _) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Intro(l.oneVote),
          for (final c in consultas)
            CivicCard(
              key: Key('consulta_${c.id}'),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ConsultaScreen(consultaId: c.id))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          c.bill,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onTint),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        l.openUntil(DateFormat.Md(l.localeName).format(c.closes)),
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(c.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    c.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, height: 20 / 14, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.how_to_vote_outlined, size: 17, color: colors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          c.myVote == null
                              ? '${l.howWouldYouVote} · ${l.votesCount(compact(c.total, l))}'
                              : l.youVoted(choiceLabel(c.myVote!, l)),
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colors.accent),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Propose extends StatelessWidget {
  const _Propose({super.key});

  Future<void> _sign(BuildContext context, CivicService civic, Petition p) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = L10n.of(context);
    if (!civic.verified.value) await civic.verify();
    await civic.sign(p.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.signedSnack)));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final civic = Deps.of(context).civic!;
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    return ValueListenableBuilder<List<Petition>>(
      valueListenable: civic.petitions,
      builder: (context, petitions, _) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Intro(l.petitionRule),
          for (final p in petitions)
            CivicCard(
              key: Key('petition_${p.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    p.summary,
                    style: TextStyle(fontSize: 14, height: 20 / 14, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  ShareBar(share: p.signatures / p.goal, height: 10),
                  const SizedBox(height: 8),
                  Text(
                    l.signatures(count(p.signatures, l), count(p.goal, l)),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
                  ),
                  Text(
                    p.signatures >= p.goal && p.statesReached >= 5 ? l.goalReached : l.petitionStates(p.statesReached),
                    style: TextStyle(
                      fontSize: 13,
                      color: p.signatures >= p.goal ? colors.accent : scheme.onSurfaceVariant,
                      fontWeight: p.signatures >= p.goal ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: p.signed
                            ? FilledButton.tonalIcon(
                                key: Key('signed_${p.id}'),
                                onPressed: () {},
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: Text(l.signedDone),
                              )
                            : FilledButton.icon(
                                key: Key('sign_${p.id}'),
                                onPressed: () => _sign(context, civic, p),
                                icon: const Icon(Icons.draw_outlined, size: 18),
                                label: Text(l.sign),
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        key: Key('share_petition_${p.id}'),
                        tooltip: l.share,
                        onPressed: () => ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(l.linkCopied))),
                        icon: const Icon(Icons.ios_share_rounded, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(l.comingSoon))),
              icon: const Icon(Icons.lightbulb_outline_rounded),
              label: Text(l.proposeIdea),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mobilize extends StatelessWidget {
  const _Mobilize({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final civic = Deps.of(context).civic!;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<Channel>>(
      valueListenable: civic.channels,
      builder: (context, channels, _) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Intro(l.mobilizeIntro),
          for (final c in channels)
            CivicCard(
              key: Key('channel_${c.id}'),
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Avatar(name: c.name, seed: c.id, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                        Text(
                          c.about,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.channelMembers(compact(c.members, l)),
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  c.joined
                      ? OutlinedButton(
                          key: Key('join_${c.id}'),
                          onPressed: () => civic.toggleJoin(c.id),
                          child: Text(l.joined),
                        )
                      : FilledButton(
                          key: Key('join_${c.id}'),
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                          onPressed: () => civic.toggleJoin(c.id),
                          child: Text(l.join),
                        ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
