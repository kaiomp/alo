import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/motion.dart';
import '../common/net_image.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../l10n/app_localizations.dart';
import '../services/civic_service.dart';
import 'civic_widgets.dart';
import 'consulta_screen.dart';
import 'representative_screen.dart';

IconData levelIcon(CivicLevel l) => switch (l) {
  CivicLevel.country => Icons.public_rounded,
  CivicLevel.state => Icons.map_outlined,
  CivicLevel.city => Icons.location_city_rounded,
  CivicLevel.neighbourhood => Icons.home_outlined,
};

/// Voz: society taking part in politics, from Brasil down to my bairro.
/// A place bar on top picks the level; the four sections (Acompanhe, Vote,
/// Proponha, Mobilize) then show that level's people, questions and causes.
/// Nothing is ranked.
class VozView extends StatefulWidget {
  const VozView({super.key});

  @override
  State<VozView> createState() => _VozViewState();
}

class _VozViewState extends State<VozView> {
  int _section = 0;
  CivicLevel _level = CivicLevel.country;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final civic = Deps.of(context).civic!;
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final sections = [l.civicFollow, l.civicVote, l.civicPropose, l.civicMobilize];
    final key = ValueKey('${_level.name}_$_section');
    return Column(
      children: [
        _PlaceBar(places: civic.places, selected: _level, onSelect: (v) => setState(() => _level = v)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          child: Row(
            children: [
              Icon(Icons.bookmark_border_rounded, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l.followingPlaces(civic.followedPlaces.join(', ')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                ),
              ),
              IconButton(
                tooltip: l.editPlaces,
                onPressed: () => ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(l.comingSoon))),
                icon: Icon(Icons.edit_outlined, size: 20, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    labelPadding: EdgeInsets.zero,
                    backgroundColor: scheme.surfaceContainer,
                    selectedColor: colors.tint,
                    labelStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: _section == i ? FontWeight.w700 : FontWeight.w500,
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
            duration: motion(context, const Duration(milliseconds: 260)),
            switchInCurve: Curves.easeOutCubic,
            // Changing place zooms in a little; changing section just fades.
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child),
            ),
            child: KeyedSubtree(
              key: key,
              child: switch (_section) {
                0 => _Follow(level: _level),
                1 => _Vote(level: _level),
                2 => _Propose(level: _level),
                _ => _Mobilize(level: _level),
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Brasil · Pernambuco · Recife · Casa Amarela.
class _PlaceBar extends StatelessWidget {
  const _PlaceBar({required this.places, required this.selected, required this.onSelect});
  final List<Place> places;
  final CivicLevel selected;
  final ValueChanged<CivicLevel> onSelect;

  @override
  Widget build(BuildContext context) {
    // All four always in view (they wrap), from the country to the bairro.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in places) _PlaceButton(place: p, selected: p.level == selected, onTap: () => onSelect(p.level)),
        ],
      ),
    );
  }
}

class _PlaceButton extends StatelessWidget {
  const _PlaceButton({required this.place, required this.selected, required this.onTap});
  final Place place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainer,
        shape: const StadiumBorder(),
        child: InkWell(
          key: Key('level_${place.level.name}'),
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(levelIcon(place.level), size: 18, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    place.name,
                    style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: fg),
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

class _Intro extends StatelessWidget {
  const _Intro(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(text, style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SampleTag(),
      ],
    ),
  );
}

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

class _Follow extends StatelessWidget {
  const _Follow({required this.level});
  final CivicLevel level;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final civic = Deps.of(context).civic!;
    final scheme = Theme.of(context).colorScheme;
    final reps = civic.representatives.where((r) => r.level == level);
    final hearings = civic.hearings.where((h) => h.level == level);
    return ListView(
      key: const Key('voz_follow'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Intro(l.civicIntro),
        if (level == CivicLevel.neighbourhood) ...[
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: CivicLabel(l.neighbourhoodProblems)),
          ValueListenableBuilder<List<LocalIssue>>(
            valueListenable: civic.issues,
            builder: (context, issues, _) => Column(children: [for (final i in issues) _IssueCard(issue: i)]),
          ),
          const _ReportButton(),
          const SizedBox(height: 12),
        ],
        for (final h in hearings) _HearingCard(hearing: h),
        for (final r in reps)
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
                    Avatar(name: r.name, seed: r.id, radius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                          Text(r.role, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _Stat(label: l.attendance, value: percent(r.present / r.sessions)),
                    _Stat(label: l.spending(r.spendingYear), value: reais(r.spending, l)),
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
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            fontFeatures: tabularFigures,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

/// A reported problem: photo, place, how many neighbours support it, and
/// the city's answer once there is one.
class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.issue});
  final LocalIssue issue;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final civic = Deps.of(context).civic!;
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final i = issue;
    return CivicCard(
      key: Key('issue_${i.id}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 84,
                  child: Semantics(label: l.photoOf(i.title), image: true, child: NetImage(i.photo)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(i.street, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                    if (i.status != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mark_chat_read_outlined, size: 14, color: colors.onTint),
                            const SizedBox(width: 5),
                            Text(
                              i.status!,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onTint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: motion(context, const Duration(milliseconds: 220)),
                  child: Text(
                    l.neighboursSupport(count(i.supporters, l)),
                    key: ValueKey(i.supporters),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
                  ),
                ),
              ),
              i.supported
                  ? FilledButton.tonalIcon(
                      key: Key('support_${i.id}'),
                      onPressed: () => civic.toggleSupport(i.id),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(l.supported),
                    )
                  : FilledButton.icon(
                      key: Key('support_${i.id}'),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: () => civic.toggleSupport(i.id),
                      icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                      label: Text(l.support),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportButton extends StatelessWidget {
  const _ReportButton();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        key: const Key('report_problem'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: () => _snack(context, l.comingSoon),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(l.reportProblem, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

/// The next public hearing, or the council's next session.
class _HearingCard extends StatelessWidget {
  const _HearingCard({required this.hearing});
  final Hearing hearing;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final h = hearing;
    return CivicCard(
      key: Key('hearing_${h.level.name}'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.event_outlined, color: colors.onTint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CivicLabel(h.level == CivicLevel.neighbourhood ? l.hearing : l.cityAgenda),
                const SizedBox(height: 2),
                Text(h.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text('${h.when} · ${h.where}', style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: Key('remind_${h.level.name}'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => _snack(context, l.reminderSet),
            child: Text(l.remindMe),
          ),
        ],
      ),
    );
  }
}

class _Vote extends StatelessWidget {
  const _Vote({required this.level});
  final CivicLevel level;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final civic = Deps.of(context).civic!;
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    return ValueListenableBuilder<List<Consulta>>(
      valueListenable: civic.consultas,
      builder: (context, all, _) => ListView(
        key: const Key('voz_vote'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Intro(l.oneVote),
          for (final c in all.where((c) => c.level == level))
            CivicCard(
              key: Key('consulta_${c.id}'),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ConsultaScreen(consultaId: c.id))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          c.bill,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onTint),
                        ),
                      ),
                      Text(
                        l.openUntil(DateFormat.Md(l.localeName).format(c.closes)),
                        style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(c.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    c.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, height: 21 / 15, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.how_to_vote_outlined, size: 18, color: colors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          c.myVote != null
                              ? l.youVoted(choiceLabel(c.myVote!, l))
                              : c.myOption != null
                              ? l.youVoted(c.options[c.myOption!])
                              : l.votesAt(c.place, count(c.total, l)),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.accent),
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
  const _Propose({required this.level});
  final CivicLevel level;

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
      builder: (context, all, _) => ListView(
        key: const Key('voz_propose'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Intro(level == CivicLevel.country ? l.petitionRule : l.civicIntro),
          if (level == CivicLevel.neighbourhood) const _ReportButton(),
          for (final p in all.where((p) => p.level == level))
            CivicCard(
              key: Key('petition_${p.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    p.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, height: 21 / 15, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  ShareBar(share: p.signatures / p.goal, height: 12),
                  const SizedBox(height: 8),
                  Text(
                    l.signatures(count(p.signatures, l), count(p.goal, l)),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
                  ),
                  Text(
                    p.signatures >= p.goal && p.statesReached >= 5
                        ? l.goalReached
                        : p.rule ?? l.petitionStates(p.statesReached),
                    style: TextStyle(
                      fontSize: 14,
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
                      OutlinedButton.icon(
                        key: Key('share_petition_${p.id}'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                        onPressed: () => _snack(context, l.linkCopied),
                        icon: const Icon(Icons.ios_share_rounded, size: 20),
                        label: Text(l.share),
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

class _Mobilize extends StatelessWidget {
  const _Mobilize({required this.level});
  final CivicLevel level;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final civic = Deps.of(context).civic!;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<Channel>>(
      valueListenable: civic.channels,
      builder: (context, all, _) => ListView(
        key: const Key('voz_mobilize'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Intro(l.mobilizeIntro),
          for (final c in all.where((c) => c.level == level))
            CivicCard(
              key: Key('channel_${c.id}'),
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Avatar(name: c.name, seed: c.id, radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(
                          c.about,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.channelMembers(compact(c.members, l)),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  c.joined
                      ? OutlinedButton(
                          key: Key('join_${c.id}'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: () => civic.toggleJoin(c.id),
                          child: Text(l.joined),
                        )
                      : FilledButton(
                          key: Key('join_${c.id}'),
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
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
