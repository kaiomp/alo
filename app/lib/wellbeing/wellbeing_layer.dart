import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/wellbeing_service.dart';

/// Over the whole app: grey mode, and the pause card once the daily limit
/// is reached.
class WellbeingLayer extends StatelessWidget {
  const WellbeingLayer({super.key, required this.service, required this.child});
  final WellbeingService service;
  final Widget child;

  /// Rec. 709 luma: the screen in shades of grey.
  static const _greyscale = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: service.grey,
    builder: (context, grey, _) {
      final content = Stack(
        children: [
          child,
          ValueListenableBuilder<bool>(
            valueListenable: service.pauseDue,
            builder: (context, due, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              child: due ? _PauseCard(service: service) : const SizedBox.shrink(),
            ),
          ),
        ],
      );
      return grey ? ColorFiltered(colorFilter: _greyscale, child: content) : content;
    },
  );
}

/// "Hora de uma pausa": closing is the main button, five more minutes the
/// quiet one.
class _PauseCard extends StatelessWidget {
  const _PauseCard({required this.service});
  final WellbeingService service;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ChatColors.of(context);
    return Material(
      key: const Key('pause_card'),
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(color: colors.tint, shape: BoxShape.circle),
                child: Icon(Icons.park_outlined, size: 56, color: colors.onTint),
              ),
              const SizedBox(height: 28),
              Text(l.pauseTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                l.pauseBody(service.dailyLimit.value ?? service.todayMinutes.value),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16.5, height: 24 / 16.5, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('pause_close'),
                  onPressed: () {
                    SystemNavigator.pop();
                    // On the web the tab stays open: let it go on.
                    service.snooze();
                  },
                  child: Text(l.pauseClose),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(key: const Key('pause_more'), onPressed: service.snooze, child: Text(l.pauseMore)),
            ],
          ),
        ),
      ),
    );
  }
}
