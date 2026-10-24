import 'package:flutter/material.dart';

import '../config.dart';
import '../l10n/app_localizations.dart';
import 'brand.dart';
import 'theme.dart';

/// Runs a tapped action whose result the screen does not wait on (react,
/// retry, delete, group changes). A failure shows the generic error in a
/// snackbar instead of vanishing. Returns whether it worked.
Future<bool> runOrSnack(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  final text = L10n.of(context).errUnknown;
  try {
    await action();
    return true;
  } catch (e) {
    debugPrint('Action failed: $e');
    messenger.showSnackBar(SnackBar(content: Text(text)));
    return false;
  }
}

/// True at WhatsApp Web widths (two panes).
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideLayoutMinWidth;

/// Marks a side pane with its own Navigator (wide layout): pages pushed from
/// inside it slide in from the left instead of covering the window.
class InPane extends InheritedWidget {
  const InPane({super.key, required super.child});

  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<InPane>() != null;

  @override
  bool updateShouldNotify(InPane oldWidget) => false;
}

/// A page that slides in from the left over its pane.
Route<T> paneRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 220),
  reverseTransitionDuration: const Duration(milliseconds: 180),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, animation, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  ),
);

/// [paneRoute] inside a pane, else a normal full-screen page.
Route<T> pageRoute<T>(BuildContext context, Widget page) =>
    InPane.of(context) ? paneRoute<T>(page) : MaterialPageRoute<T>(builder: (_) => page);

/// Shows a field's counter only near the limit ("80/100").
Widget? counterNearLimit(
  BuildContext context, {
  required int currentLength,
  required int? maxLength,
  required bool isFocused,
}) => maxLength == null || currentLength <= maxLength * 0.8
    ? null
    : Text('$currentLength/$maxLength', style: const TextStyle(fontFeatures: tabularFigures));

/// "Conta", "Privacidade"…: small orange label above a group of rows.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? ChatColors.of(context).accent),
    ),
  );
}

/// Thick band between sections (contact and group info).
class SectionBand extends StatelessWidget {
  const SectionBand({super.key});

  @override
  Widget build(BuildContext context) => Container(height: 8, color: Theme.of(context).colorScheme.surfaceContainerLow);
}

/// Icon in a tinted circle, title, body and an optional button.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.icon, this.body, this.action, this.onAction});
  final IconData? icon;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(color: Tokens.flame.withValues(alpha: 0.10), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: icon == null ? const ChamaMark(size: 56) : Icon(icon, size: 56, color: colors.accent),
              ),
              const SizedBox(height: 20),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontSize: 18)),
              if (body != null) ...[
                const SizedBox(height: 8),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 20),
                FilledButton.tonal(style: tonalButton(context), onPressed: onAction, child: Text(action!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Orange-tinted secondary button ("Copiar", "Iniciar conversa").
ButtonStyle tonalButton(BuildContext context) {
  final colors = ChatColors.of(context);
  return FilledButton.styleFrom(
    backgroundColor: colors.tint,
    foregroundColor: colors.onTint,
    minimumSize: const Size(64, 44),
  );
}

/// The end-to-end encryption notice: top of every chat and the empty pane.
/// Tap explains it.
class E2eNotice extends StatelessWidget {
  const E2eNotice({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final style = TextStyle(fontSize: 12.5, height: 18 / 12.5, color: colors.onNotice);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: colors.notice,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const Key('e2e_notice'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => showE2eExplainer(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.lock, size: 12, color: colors.onNotice),
                        ),
                      ),
                      TextSpan(text: text),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: style,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What end-to-end encryption means, in plain words.
Future<void> showE2eExplainer(BuildContext context) {
  final l = L10n.of(context);
  return showSheetOrDialog<void>(
    context,
    title: l.e2eTitle,
    icon: Icons.lock_outline,
    builder: (context) => Text(l.e2eExplain),
    action: l.gotIt,
  );
}

/// Phone: a bottom sheet. Wide: a small dialog (a 640 px sheet in the middle
/// of a desktop window looks lost).
Future<T?> showSheetOrDialog<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  IconData? icon,
  String? action,
}) {
  final theme = Theme.of(context);
  Widget body(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (icon != null) ...[Icon(icon, size: 32, color: ChatColors.of(context).accent), const SizedBox(height: 12)],
      Text(title, style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      DefaultTextStyle.merge(
        style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15, color: theme.colorScheme.onSurfaceVariant),
        child: builder(context),
      ),
      if (action != null) ...[
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => Navigator.pop(context), child: Text(action)),
        ),
      ],
    ],
  );
  if (isWide(context)) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(padding: const EdgeInsets.fromLTRB(24, 24, 24, 12), child: body(context)),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 12), child: body(context)),
    ),
  );
}

/// Yes/no question. [destructive] paints the confirm button red.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? body,
  required String action,
  bool destructive = false,
}) async {
  final l = L10n.of(context);
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        TextButton(
          key: const Key('confirm'),
          style: destructive ? TextButton.styleFrom(foregroundColor: scheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Keeps forms and lists at a readable width on big screens (480, centred).
class FormWidth extends StatelessWidget {
  const FormWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: child),
  );
}
