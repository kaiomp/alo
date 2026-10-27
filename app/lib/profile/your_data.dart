import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../common/deps.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../l10n/app_localizations.dart';
import '../services/social_service.dart';

/// "Seus dados são seus": export everything, or take my followers to any
/// server on the open standard.
class YourDataCard extends StatelessWidget {
  const YourDataCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Container(
      key: const Key('your_data'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Tokens.acai, Tokens.acaiDeep],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Tokens.ipe.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: const Icon(Icons.key_rounded, size: 20, color: Tokens.ipe),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.yourDataTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l.yourDataBody,
            style: const TextStyle(color: Tokens.onPhotoSoft, fontSize: 16, height: 22 / 16),
          ),
          TextButton(
            key: const Key('your_data_more'),
            style: TextButton.styleFrom(
              foregroundColor: Tokens.ipe,
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 44),
              alignment: Alignment.centerLeft,
            ),
            onPressed: () => showLearnMore(context, l.yourDataTitle, l.yourDataMore(l.appName)),
            child: Text(l.learnMore),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('export_all'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Tokens.ipe,
                    foregroundColor: Tokens.acaiInk,
                    minimumSize: const Size(0, 44),
                    textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => showExportSheet(context),
                  child: Text(l.exportAll),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('move_followers'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Tokens.onPhotoFaint),
                    minimumSize: const Size(0, 44),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MoveFollowersScreen())),
                  child: Text(l.moveFollowers),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showExportSheet(BuildContext context) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _ExportSheet());

/// Choose → working → done, in one sheet.
class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  double? _progress;
  DataExport? _done;

  Future<void> _start() async {
    setState(() => _progress = 0);
    final result = await Deps.of(context).social!.exportAll(
      progress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (mounted) setState(() => _done = result);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ChatColors.of(context);
    final done = _done;
    final progress = _progress;
    Widget row(IconData icon, String title, [String? note]) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: colors.tint, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: colors.onTint),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
      subtitle: note == null ? null : Text(note),
      trailing: Icon(Icons.check_circle_rounded, color: scheme.primary),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.exportTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (done != null) ...[
                const SizedBox(height: 8),
                Center(child: _Check(color: scheme.primary)),
                const SizedBox(height: 14),
                Center(child: Text(l.exportDone, style: theme.textTheme.titleMedium)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Icon(Icons.folder_zip_outlined, color: colors.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(done.fileName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            Text(
                              '${fileSizeGb(done.bytes, l)} · ${l.exportFormat}',
                              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('export_close'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.save),
                  ),
                ),
              ] else if (progress != null) ...[
                const SizedBox(height: 18),
                Text(l.exportWorking, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: progress, minHeight: 8),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, fontFeatures: tabularFigures),
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                row(Icons.lock_outline_rounded, l.exportChats, l.exportChatsNote),
                row(Icons.photo_library_outlined, l.exportMedia),
                row(Icons.article_outlined, l.exportPosts),
                row(Icons.people_outline_rounded, l.exportNetwork),
                const SizedBox(height: 8),
                Text(l.exportFormat, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(key: const Key('export_start'), onPressed: _start, child: Text(l.exportStart)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "1,2 GB" in Portuguese, "1.2 GB" in English.
String fileSizeGb(int bytes, L10n l) =>
    '${NumberFormat.decimalPatternDigits(locale: l.localeName, decimalDigits: 1).format(bytes / (1 << 30))} GB';

/// A check that pops in.
class _Check extends StatelessWidget {
  const _Check({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 600),
    curve: Curves.elasticOut,
    builder: (context, t, child) => Transform.scale(scale: t, child: child),
    child: Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(Icons.check_rounded, size: 38, color: Theme.of(context).colorScheme.onPrimary),
    ),
  );
}

/// Move my account and followers to another server on the open standard.
class MoveFollowersScreen extends StatefulWidget {
  const MoveFollowersScreen({super.key});

  @override
  State<MoveFollowersScreen> createState() => _MoveFollowersScreenState();
}

class _MoveFollowersScreenState extends State<MoveFollowersScreen> {
  final _address = TextEditingController();
  int? _told;
  bool _done = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  bool get _valid => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_address.text.trim());

  Future<void> _move() async {
    FocusScope.of(context).unfocus();
    setState(() => _told = 0);
    await Deps.of(context).social!.moveTo(
      _address.text.trim(),
      progress: (n) {
        if (mounted) setState(() => _told = n);
      },
    );
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ChatColors.of(context);
    final total = Deps.of(context).social!.me.followers;
    final told = _told;
    return Scaffold(
      appBar: AppBar(title: Text(l.moveTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: colors.tint, shape: BoxShape.circle),
              child: Icon(Icons.diversity_3_rounded, size: 44, color: colors.onTint),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l.moveBody(count(total, l)),
            style: TextStyle(fontSize: 15.5, height: 22 / 15.5, color: scheme.onSurface),
          ),
          const SizedBox(height: 24),
          if (_done) ...[
            Center(child: _Check(color: scheme.primary)),
            const SizedBox(height: 16),
            Text(
              l.moveDone(count(total, l), '@${_address.text.trim()}'),
              key: const Key('move_done'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(l.moveChatsStay, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.done)),
          ] else if (told != null) ...[
            Text(
              l.moveWorking(count(told, l), count(total, l)),
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant, fontFeatures: tabularFigures),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: told / total, minHeight: 8),
            ),
          ] else ...[
            TextField(
              key: const Key('move_address'),
              controller: _address,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.moveAddress,
                hintText: l.moveHint,
                prefixIcon: const Icon(Icons.alternate_email_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            FilledButton(key: const Key('move_start'), onPressed: _valid ? _move : null, child: Text(l.moveStart)),
          ],
        ],
      ),
    );
  }
}

/// "Saiba mais": the longer explanation, out of the way until asked for.
Future<void> showLearnMore(BuildContext context, String title, String body) => showModalBottomSheet<void>(
  context: context,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(fontSize: 16, height: 23 / 16)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(context), child: Text(L10n.of(context).gotIt)),
          ),
        ],
      ),
    ),
  ),
);
