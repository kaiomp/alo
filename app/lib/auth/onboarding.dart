import 'package:flutter/material.dart';

import '../common/brand.dart';
import '../l10n/app_localizations.dart';

/// Shared layout of the first-run screens (sign-in, SMS code, recovery key,
/// profile): brand at the top, content top-aligned, the main button pinned
/// to the bottom above the keyboard, and the trust line under it.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({super.key, required this.children, this.cta, this.below = const []});

  final List<Widget> children;
  final Widget? cta;

  /// Secondary buttons under the main one.
  final List<Widget> below;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget column(List<Widget> children, {bool stretch = false}) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
                child: column([const BrandLockup(), const SizedBox(height: 40), ...children]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: column(stretch: true, [
                ?cta,
                ...below,
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: muted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(l.trustLine, style: TextStyle(fontSize: 13, color: muted)),
                    ),
                  ],
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Title and explanation at the top of an onboarding step.
class OnboardingTitle extends StatelessWidget {
  const OnboardingTitle({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          body,
          style: theme.textTheme.bodyLarge?.copyWith(height: 24 / 16, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
