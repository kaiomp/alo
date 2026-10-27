import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../common/actions.dart';
import '../common/deps.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../common/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_session.dart';
import '../services/models.dart';
import '../services/ticks.dart';
import 'tick_icon.dart';
import 'voice/voice_player.dart';

/// One message, WhatsApp style: time and ticks inline at the bottom right,
/// a tail on the first bubble of a run, reactions overlapping the bottom edge.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.session,
    required this.onActions,
    required this.maxWidth,
    this.inset = 8,
    this.showSender = false,
    this.tail = false,
    this.highlighted = false,
  });

  final Message message;
  final ChatSession session;

  /// Long press or right click; [anchor] is the bubble's global rect.
  final void Function(Rect anchor, bool pointer) onActions;
  final double maxWidth;

  /// Space between the bubble and the pane edge on its side.
  final double inset;
  final bool showSender;
  final bool tail;

  /// Row highlight while its action sheet is open.
  final bool highlighted;

  static String systemText(Message m, L10n l, {required String myUserId}) {
    final target = m.systemTarget ?? '';
    final aboutMe = m.systemTargetId == myUserId;
    return switch (m.systemKind) {
      SystemKind.created when m.isMine => target.isEmpty ? l.youCreatedGroup : l.youCreatedGroupNamed(target),
      SystemKind.created => target.isEmpty ? l.groupCreated(m.senderName) : l.groupCreatedNamed(m.senderName, target),
      SystemKind.joined => m.isMine ? l.youJoined : l.userJoined(m.senderName),
      SystemKind.left => m.isMine ? l.youLeft : l.userLeft(m.senderName),
      SystemKind.invited when m.isMine => l.youAdded(target),
      SystemKind.invited => aboutMe ? l.addedYou(m.senderName) : l.userAdded(m.senderName, target),
      SystemKind.removed when m.isMine => l.youRemoved(target),
      SystemKind.removed => aboutMe ? l.removedYou(m.senderName) : l.userRemoved(m.senderName, target),
      SystemKind.renamed => m.isMine ? l.youRenamed(target) : l.groupRenamed(m.senderName, target),
      SystemKind.securityCodeChanged => l.securityCodeChanged(m.senderName),
      SystemKind.numberMoved => l.numberMoved(m.senderName),
      null => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final m = message;
    if (m.kind == MessageKind.system) {
      return SystemChip(text: systemText(m, l, myUserId: Deps.of(context).chat.myUserId));
    }
    final colors = ChatColors.of(context);
    final theme = Theme.of(context);
    final mine = m.isMine;
    final fill = mine ? colors.mine : colors.other;
    final textStyle = theme.textTheme.bodyLarge!.copyWith(
      color: colors.bubbleText,
      fontSize: kIsWeb ? 15 : 16,
      height: kIsWeb ? 20 / 15 : 22 / 16,
    );
    const r = Radius.circular(8);
    // Photos fill the bubble up to a 3 px frame; their sender and reply sit inset.
    final photo = m.kind == MessageKind.image;
    final pad = photo ? const EdgeInsets.all(3) : const EdgeInsets.fromLTRB(9, 6, 9, 6);
    final inner = photo ? const EdgeInsets.fromLTRB(6, 3, 6, 0) : EdgeInsets.zero;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: pad,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.only(
          topLeft: !mine && tail ? Radius.zero : r,
          topRight: mine && tail ? Radius.zero : r,
          bottomLeft: r,
          bottomRight: r,
        ),
        boxShadow: [
          if (colors.bubbleShadow != null)
            BoxShadow(color: colors.bubbleShadow!, blurRadius: 0.5, offset: const Offset(0, 1)),
        ],
      ),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSender)
              Padding(
                padding: inner.add(const EdgeInsets.only(bottom: 2)),
                child: Text(
                  m.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.accent),
                ),
              ),
            if (m.reply != null)
              Padding(
                padding: inner,
                child: _ReplyBox(reply: m.reply!),
              ),
            _contentWithMeta(context, l, textStyle, maxWidth - pad.horizontal),
            if (m.tick == Tick.failed)
              Padding(
                padding: inner.add(const EdgeInsets.only(top: 2)),
                child: Text(l.notSent, style: TextStyle(fontSize: 12.5, color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
    );

    final reactions = m.reactions;
    final body = Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: reactions.isEmpty ? 0 : 18),
          child: bubble,
        ),
        if (tail)
          Positioned(
            top: 0,
            left: mine ? null : -8,
            right: mine ? -8 : null,
            child: CustomPaint(
              size: const Size(8, 10),
              painter: _TailPainter(fill, mine: mine),
            ),
          ),
        if (reactions.isNotEmpty)
          Positioned(
            bottom: 0, // 6 px over the bubble edge, 18 below it
            left: mine ? null : 10,
            right: mine ? 10 : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in reactions)
                  _ReactionPill(
                    key: Key('reaction_${m.id}_${r.key}'),
                    reaction: r,
                    onTap: () => runOrSnack(context, () => session.toggleReaction(m.id, r.key)),
                  ),
              ],
            ),
          ),
      ],
    );

    return Container(
      color: highlighted ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
      padding: EdgeInsets.fromLTRB(mine ? 48 : inset, tail ? 8 : 2, mine ? inset : 48, 0),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Builder(
          builder: (context) => GestureDetector(
            key: Key('msg_${m.id}'),
            onLongPress: () => onActions(rectOf(context), false),
            onSecondaryTapDown: (_) => onActions(rectOf(context), true),
            onTap: m.tick == Tick.failed ? () => runOrSnack(context, () => session.retry(m.id)) : null,
            child: body,
          ),
        ),
      ),
    );
  }

  /// The content with the time (and ticks) on its last line when they fit
  /// there, else on a line of their own.
  Widget _contentWithMeta(BuildContext context, L10n l, TextStyle textStyle, double maxContent) {
    final colors = ChatColors.of(context);
    final m = message;
    // Measured and drawn with the same resolved style (the theme's font), so
    // the gap before the time is the real 8 px.
    final metaStyle = DefaultTextStyle.of(context).style
        .merge(TextStyle(fontSize: 11, height: 16 / 11, color: colors.meta, fontFeatures: tabularFigures));
    final metaText = '${m.edited ? '${l.edited}  ' : ''}${clock(m.time, l)}';
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final metaPainter = TextPainter(
      text: TextSpan(text: metaText, style: metaStyle),
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    final tickWidth = m.tick == null ? 0.0 : 3 + 16.0;
    final metaWidth = metaPainter.width + tickWidth;
    final metaHeight = math.max(metaPainter.height, m.tick == null ? 0.0 : 16.0);
    metaPainter.dispose();
    const gap = 8.0;

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(metaText, style: metaStyle),
        if (m.tick != null) ...[const SizedBox(width: 3), TickIcon(m.tick!)],
      ],
    );

    switch (m.kind) {
      case MessageKind.image:
        // Time and ticks in white on a shade at the photo's bottom right.
        return _Picture(
          message: m,
          session: session,
          width: math.min(maxContent, 280),
          meta: Container(
            padding: const EdgeInsets.fromLTRB(6, 1, 5, 1),
            decoration: BoxDecoration(color: colors.photoShade, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(metaText, style: metaStyle.copyWith(color: colors.onPhoto)),
                if (m.tick != null) ...[const SizedBox(width: 3), TickIcon(m.tick!, onPhoto: true)],
              ],
            ),
          ),
        );
      case MessageKind.voice:
        return Stack(
          children: [
            VoicePlayer(message: m, load: () => session.download(m.id), color: colors.accent),
            Positioned(right: 0, bottom: 0, child: meta),
          ],
        );
      case MessageKind.file:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _FileCard(message: m, session: session, width: math.min(maxContent, 280)),
            const SizedBox(height: 3),
            meta,
          ],
        );
      default:
    }

    // Text, and the deleted / waiting placeholder (icon and italic text):
    // the time goes on the last line when it fits there.
    final (icon, text, style) = switch (m.kind) {
      MessageKind.text => (null, m.body, textStyle),
      MessageKind.deleted => (Icons.block, m.isMine ? l.youDeleted : l.deletedMessage, null),
      _ => (Icons.schedule, l.waitingMessage, null),
    };
    final bodyStyle = style ?? textStyle.copyWith(fontStyle: FontStyle.italic, color: colors.meta);
    final lead = icon == null ? 0.0 : 18.0 + 6;
    final painter = TextPainter(
      text: TextSpan(text: text, style: bodyStyle),
      textDirection: direction,
      textScaler: scaler,
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: maxContent - lead);
    final lines = painter.computeLineMetrics();
    final lastLine = lead + (lines.isEmpty ? 0.0 : lines.last.width);
    final inline = lastLine + gap + metaWidth <= maxContent;
    final textWidth = painter.width.ceilToDouble();
    final width = math.max(lead + painter.width, inline ? lastLine + gap + metaWidth : metaWidth).ceilToDouble();
    final height = painter.height + (inline ? 0 : metaHeight);
    painter.dispose();
    final body = Text(
      text,
      key: m.kind == MessageKind.undecryptable ? const Key('waiting_message') : null,
      style: bodyStyle,
      textWidthBasis: TextWidthBasis.longestLine,
    );
    return SizedBox(
      width: math.min(width, maxContent),
      height: height,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: lead + textWidth,
            child: icon == null
                ? body
                : Row(
                    children: [
                      Icon(icon, size: 18, color: colors.meta),
                      const SizedBox(width: 6),
                      Expanded(child: body),
                    ],
                  ),
          ),
          Positioned(right: 0, bottom: 0, child: meta),
        ],
      ),
    );
  }
}

/// Centred grey line for group events and day dividers.
class SystemChip extends StatelessWidget {
  const SystemChip({super.key, required this.text, this.weight = FontWeight.w400, this.margin = 2});
  final String text;
  final FontWeight weight;
  final double margin;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: margin, horizontal: 16),
      child: Center(
        child: LayoutBuilder(
          builder: (context, c) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth * 0.85),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: colors.systemChip,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  if (colors.bubbleShadow != null)
                    BoxShadow(color: colors.bubbleShadow!, blurRadius: 0.5, offset: const Offset(0, 0.5)),
                ],
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 17 / 12.5, fontWeight: weight, color: scheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.color, {required this.mine});
  final Color color;
  final bool mine;

  @override
  void paint(Canvas canvas, Size size) {
    if (mine) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    // Triangle from the bubble's top corner out to a 2 px rounded tip.
    final path = Path()
      ..moveTo(size.width + 0.5, 0)
      ..lineTo(2, 0)
      ..quadraticBezierTo(0, 0, 1.2, 1.6)
      ..lineTo(size.width + 0.5, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color || old.mine != mine;
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({super.key, required this.reaction, required this.onTap});
  final Reaction reaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final r = reaction;
    void who() => showSheetOrDialog<void>(
      context,
      title: '${r.key}  ${L10n.of(context).reactions}',
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final name in r.senders) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(name)),
        ],
      ),
      action: L10n.of(context).close,
    );
    return Semantics(
      button: true,
      selected: r.mine,
      label: '${r.key} ${r.count}',
      onTap: onTap,
      onLongPress: who,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: who,
        // A 40 px target: the gap to the next pill and 16 px over the bubble.
        child: Padding(padding: const EdgeInsets.only(top: 16, right: 4), child: _pill(colors, scheme)),
      ),
    );
  }

  Widget _pill(ChatColors colors, ColorScheme scheme) {
    final r = reaction;
    return Container(
      height: 24,
      constraints: const BoxConstraints(minWidth: 36),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: ShapeDecoration(
        color: r.mine ? colors.tint : colors.other,
        shape: StadiumBorder(side: r.mine ? BorderSide.none : BorderSide(color: colors.background, width: 2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(r.key, style: const TextStyle(fontSize: 14, height: 1)),
          if (r.count > 1) ...[
            const SizedBox(width: 3),
            Text(
              '${r.count}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReplyBox extends StatelessWidget {
  const _ReplyBox({required this.reply});
  final ReplyPreview reply;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final colors = ChatColors.of(context);
    final body = switch (reply.kind) {
      MessageKind.image => l.photo,
      MessageKind.voice => l.voiceMessage,
      MessageKind.file => reply.body,
      MessageKind.deleted => l.deletedMessage,
      _ => reply.body,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: colors.cardTint, borderRadius: BorderRadius.circular(6)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: colors.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reply.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.quoteName),
                    ),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, height: 18 / 13, color: colors.meta),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1,5 MB" in Portuguese, "1.5 MB" in English.
String fileSize(int bytes, String locale) => switch (bytes) {
  < 1024 => '$bytes B',
  < 1024 * 1024 => '${(bytes / 1024).ceil()} KB',
  _ => '${NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 1).format(bytes / (1024 * 1024))} MB',
};

/// Encrypted photo: the thumbnail fills the bubble, a tap opens it full size.
class _Picture extends StatefulWidget {
  const _Picture({required this.message, required this.session, required this.width, required this.meta});
  final Message message;
  final ChatSession session;
  final double width;
  final Widget meta;

  @override
  State<_Picture> createState() => _PictureState();
}

class _PictureState extends State<_Picture> {
  late final Future<Uint8List> _thumb = widget.session.download(widget.message.id, thumbnail: true);

  void _open(Uint8List thumb) {
    final full = widget.session.download(widget.message.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: Center(
            child: FutureBuilder<Uint8List>(
              future: full,
              builder: (context, snap) =>
                  InteractiveViewer(child: Image.memory(snap.data ?? thumb, gaplessPlayback: true)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final colors = ChatColors.of(context);
    final ratio = (m.width != null && m.height != null && m.height! > 0) ? m.width! / m.height! : 4 / 3;
    final width = widget.width;
    return SizedBox(
      width: width,
      height: width / ratio.clamp(0.75, 2.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List>(
              future: _thumb,
              builder: (context, snap) => switch (snap) {
                AsyncSnapshot(:final data?) => GestureDetector(
                  onTap: () => _open(data),
                  child: Image.memory(data, key: Key('image_${m.id}'), fit: BoxFit.cover),
                ),
                AsyncSnapshot(hasError: true) => ColoredBox(
                  color: colors.meta.withValues(alpha: 0.15),
                  child: Icon(Icons.broken_image_outlined, color: colors.meta),
                ),
                _ => ColoredBox(
                  color: colors.meta.withValues(alpha: 0.15),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colors.meta),
                    ),
                  ),
                ),
              },
            ),
            Positioned(right: 4, bottom: 4, child: widget.meta),
          ],
        ),
      ),
    );
  }
}

/// A file: icon, name, size and type, and a button that decrypts and saves it.
class _FileCard extends StatefulWidget {
  const _FileCard({required this.message, required this.session, required this.width});
  final Message message;
  final ChatSession session;
  final double width;

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> {
  bool _busy = false;

  Future<void> _save() async {
    final m = widget.message;
    final failed = L10n.of(context).downloadFailed;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await widget.session.download(m.id);
      await FilePicker.saveFile(fileName: m.body, bytes: bytes, mimeType: m.mimeType ?? 'application/octet-stream');
    } catch (e) {
      debugPrint('File save failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final colors = ChatColors.of(context);
    final dot = m.body.lastIndexOf('.');
    final type = dot > 0 && dot < m.body.length - 1 ? m.body.substring(dot + 1).toUpperCase() : null;
    final details = [if (m.size != null) fileSize(m.size!, L10n.of(context).localeName), ?type].join(' · ');
    return Container(
      width: widget.width,
      // The 48 px button fills the vertical and right padding: same card size.
      padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
      decoration: BoxDecoration(color: colors.cardTint, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: colors.tint, borderRadius: BorderRadius.circular(6)),
            child: Icon(Icons.insert_drive_file_outlined, size: 20, color: colors.onTint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 18 / 14,
                    fontWeight: FontWeight.w500,
                    color: colors.bubbleText,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: TextStyle(fontSize: 12, height: 16 / 12, color: colors.meta, fontFeatures: tabularFigures),
                  ),
              ],
            ),
          ),
          SizedBox.square(
            dimension: 48,
            child: _busy
                ? Padding(
                    padding: const EdgeInsets.all(15),
                    child: CircularProgressIndicator(strokeWidth: 2, color: colors.meta),
                  )
                : IconButton(
                    key: Key('download_${m.id}'),
                    tooltip: L10n.of(context).download,
                    color: colors.meta,
                    onPressed: _save,
                    icon: const Icon(Icons.download_rounded),
                  ),
          ),
        ],
      ),
    );
  }
}
