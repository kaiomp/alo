import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../common/deps.dart';
import '../common/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/civic_service.dart';

/// "1,5 mi" / "1.5M".
String compact(int n, L10n l) => NumberFormat.compact(locale: l.localeName).format(n);

String reais(int n, L10n l) =>
    NumberFormat.currency(locale: l.localeName == 'pt' ? 'pt_BR' : 'en', symbol: r'R$ ', decimalDigits: 0).format(n);

String percent(double share) => '${(share * 100).round()}%';

String choiceLabel(Choice c, L10n l) => switch (c) {
  Choice.yes => l.choiceYes,
  Choice.no => l.choiceNo,
  Choice.abstain => l.choiceAbstain,
};

/// "Dados de exemplo", on every Voz screen while the data is invented.
class SampleTag extends StatelessWidget {
  const SampleTag({super.key});

  @override
  Widget build(BuildContext context) {
    if (Deps.of(context).civic?.sampleData != true) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('sample_tag'),
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(
        L10n.of(context).sampleData,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer),
      ),
    );
  }
}

/// "Fonte: dados abertos · Câmara dos Deputados" under every fact.
class SourceLabel extends StatelessWidget {
  const SourceLabel(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.open_in_new_rounded, size: 13, color: muted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              L10n.of(context).source(source),
              style: TextStyle(
                fontSize: 12,
                color: muted,
                decoration: TextDecoration.underline,
                decorationColor: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded bar that grows to [share] (0..1) when it first shows.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.share, this.height = 8, this.color});
  final double share;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      value: percent(share),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: share.clamp(0, 1)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: scheme.surfaceContainerHighest),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: ColoredBox(color: color ?? scheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A white card with a hairline, used for every Voz block.
class CivicCard extends StatelessWidget {
  const CivicCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Small caps-free label above a block ("Presença nas votações").
class CivicLabel extends StatelessWidget {
  const CivicLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChatColors.of(context).accent),
  );
}
