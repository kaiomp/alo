import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'theme.dart';

/// "Modo simples": bigger text and buttons, three tabs, a plain chat
/// background and no decorative motion. Offered once on first launch.
class SimpleMode extends ChangeNotifier {
  SimpleMode({this.offered = true});

  bool _on = false;
  bool get on => _on;
  set on(bool v) {
    if (v == _on) return;
    _on = v;
    notifyListeners();
  }

  /// False until the first-launch question has been answered.
  bool offered;

  void answer(bool yes) {
    offered = true;
    _on = yes;
    notifyListeners();
  }

  /// Text grows by this much on top of the system size.
  static const textBoost = 1.25;

  /// True below a [SimpleScope] that is on; rebuilds when it changes.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SimpleScope>()?.notifier?.on ?? false;
}

class SimpleScope extends InheritedNotifier<SimpleMode> {
  const SimpleScope({super.key, required SimpleMode super.notifier, required super.child});
}

/// Applies [mode] to everything below: text size, calm motion, the plain
/// chat background, and the first-launch question on top.
class SimpleLayer extends StatefulWidget {
  const SimpleLayer({super.key, required this.mode, required this.child});
  final SimpleMode mode;
  final Widget child;

  @override
  State<SimpleLayer> createState() => _SimpleLayerState();
}

class _SimpleLayerState extends State<SimpleLayer> {
  /// The question waits for the app's first layout: focus lookups on the
  /// web run then and expect every screen below laid out.
  bool _laidOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _laidOut = true);
    });
  }

  SimpleMode get mode => widget.mode;
  Widget get child => widget.child;

  @override
  Widget build(BuildContext context) => SimpleScope(
    notifier: mode,
    child: ListenableBuilder(
      listenable: mode,
      builder: (context, _) {
        // Same widgets on and off, only their values change: the app below
        // keeps its state (open screens) when the mode flips.
        final mq = MediaQuery.of(context);
        final theme = Theme.of(context);
        final chat = ChatColors.of(context);
        final on = mode.on;
        final content = MediaQuery(
          data: on
              ? mq.copyWith(
                  textScaler: TextScaler.linear(mq.textScaler.scale(16) / 16 * SimpleMode.textBoost),
                  disableAnimations: true,
                )
              : mq,
          child: Theme(
            data: on ? theme.copyWith(extensions: [chat.copyWith(background: theme.colorScheme.surface)]) : theme,
            child: child,
          ),
        );
        return Stack(
          children: [
            content,
            if (_laidOut && !mode.offered) _Offer(mode: mode),
          ],
        );
      },
    ),
  );
}

/// "Prefere letras maiores e menos botões?" with a big Sim and a quiet Não.
class _Offer extends StatelessWidget {
  const _Offer({required this.mode});
  final SimpleMode mode;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ChatColors.of(context);
    return Material(
      key: const Key('simple_offer'),
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(color: colors.tint, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  'Aa',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: 52, fontWeight: FontWeight.w700, color: colors.onTint),
                ),
              ),
              const SizedBox(height: 28),
              Text(l.simpleOffer, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                l.simpleOfferBody,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('simple_yes'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                  onPressed: () => mode.answer(true),
                  child: Text(l.simpleYes, style: const TextStyle(fontSize: 19)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('simple_no'),
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => mode.answer(false),
                child: Text(l.simpleNo, style: const TextStyle(fontSize: 17)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
