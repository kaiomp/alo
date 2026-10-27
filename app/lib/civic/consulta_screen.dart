import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../common/deps.dart';
import '../common/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/civic_service.dart';
import 'civic_widgets.dart';

/// One consultation. Results show only after I vote, so nobody follows the
/// crowd; then the people's answer sits next to the Chamber's.
class ConsultaScreen extends StatefulWidget {
  const ConsultaScreen({super.key, required this.consultaId});
  final String consultaId;

  @override
  State<ConsultaScreen> createState() => _ConsultaScreenState();
}

class _ConsultaScreenState extends State<ConsultaScreen> {
  Choice? _choice;
  bool _verifying = false;

  Future<void> _verify(CivicService civic) async {
    setState(() => _verifying = true);
    await civic.verify();
    if (mounted) setState(() => _verifying = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final civic = Deps.of(context).civic!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([civic.consultas, civic.verified]),
      builder: (context, _) {
        final c = civic.consultas.value.firstWhere((c) => c.id == widget.consultaId);
        return Scaffold(
          appBar: AppBar(title: Text(c.bill), actions: const [SampleTag()]),
          body: ListView(
            key: const Key('consulta_page'),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      c.summary,
                      style: TextStyle(fontSize: 15.5, height: 22 / 15.5, color: scheme.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.openUntil(DateFormat.yMd(l.localeName).format(c.closes)),
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: c.myVote == null
                    ? _Ballot(
                        key: const ValueKey('ballot'),
                        verified: civic.verified.value,
                        verifying: _verifying,
                        choice: _choice,
                        onVerify: () => _verify(civic),
                        onChoice: (v) => setState(() => _choice = v),
                        onConfirm: () => civic.vote(c.id, _choice!),
                      )
                    : _Results(key: const ValueKey('results'), consulta: c),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Ballot extends StatelessWidget {
  const _Ballot({
    super.key,
    required this.verified,
    required this.verifying,
    required this.choice,
    required this.onVerify,
    required this.onChoice,
    required this.onConfirm,
  });
  final bool verified;
  final bool verifying;
  final Choice? choice;
  final VoidCallback onVerify;
  final ValueChanged<Choice> onChoice;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    return CivicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.howWouldYouVote, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: verified
                ? Container(
                    key: const Key('verified_badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user_rounded, size: 20, color: colors.onTint),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l.verifiedBadge,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colors.onTint),
                          ),
                        ),
                      ],
                    ),
                  )
                : FilledButton.icon(
                    key: const Key('verify'),
                    onPressed: verifying ? null : onVerify,
                    icon: verifying
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSurfaceVariant),
                          )
                        : const Icon(Icons.badge_outlined),
                    label: Text(verifying ? l.verifying : l.verifyIdentity),
                  ),
          ),
          const SizedBox(height: 14),
          for (final c in Choice.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Option(
                key: Key('choice_${c.name}'),
                label: choiceLabel(c, l),
                selected: choice == c,
                enabled: verified,
                onTap: () => onChoice(c),
              ),
            ),
          const SizedBox(height: 6),
          FilledButton(
            key: const Key('confirm_vote'),
            onPressed: verified && choice != null ? onConfirm : null,
            child: Text(l.confirmVote),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l.oneVote, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({super.key, required this.label, required this.selected, required this.enabled, required this.onTap});
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: selected ? colors.tint : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
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

class _Results extends StatelessWidget {
  const _Results({super.key, required this.consulta});
  final Consulta consulta;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = consulta;
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final chamber = c.chamberYes == null ? null : c.chamberYes! / c.chamberTotal;
    final states = c.byState.keys.toList()..sort();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: colors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                l.youVoted(choiceLabel(c.myVote!, l)),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.accent),
              ),
            ],
          ),
        ),
        CivicCard(
          key: const Key('people_vs_chamber'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Side(
                        title: l.thePeople,
                        share: c.yesShare,
                        note: l.votesCount(compact(c.total, l)),
                        color: scheme.primary,
                      ),
                    ),
                    VerticalDivider(width: 24, color: scheme.outlineVariant),
                    Expanded(
                      child: _Side(
                        title: l.theChamber,
                        share: chamber ?? 0,
                        note: c.chamberYes == null ? '' : l.chamberVotes(c.chamberYes!, c.chamberTotal),
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (chamber != null) ...[
                const SizedBox(height: 14),
                Text(
                  l.peopleGap(((c.yesShare - chamber).abs() * 100).round()),
                  style: const TextStyle(fontSize: 15, height: 21 / 15, fontWeight: FontWeight.w600),
                ),
              ],
              const SourceLabel('Câmara dos Deputados'),
            ],
          ),
        ),
        CivicCard(
          key: const Key('by_state'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CivicLabel(l.byState),
              const SizedBox(height: 6),
              for (final s in states)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(s, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(child: ShareBar(share: c.byState[s]!, height: 10)),
                      SizedBox(
                        width: 46,
                        child: Text(
                          percent(c.byState[s]!),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "O povo · 78% sim" with its bar.
class _Side extends StatelessWidget {
  const _Side({required this.title, required this.share, required this.note, required this.color});
  final String title;
  final double share;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: share),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Text(
            l.yesShare(percent(v)),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ShareBar(share: share, height: 12, color: color),
        const SizedBox(height: 6),
        Text(note, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
