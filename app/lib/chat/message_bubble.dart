import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
    const pad = EdgeInsets.fromLTRB(9, 6, 9, 6);

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
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  m.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.accent),
                ),
              ),
            if (m.reply != null) _ReplyBox(reply: m.reply!),
            _contentWithMeta(context, l, textStyle, maxWidth - pad.horizontal),
            if (m.tick == Tick.failed)
              Padding(
                padding: const EdgeInsets.only(top: 2),
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
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _ReactionPill(
                      key: Key('reaction_${m.id}_${r.key}'),
                      reaction: r,
                      onTap: () => session.toggleReaction(m.id, r.key),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    return Container(
      color: highlighted ? Tokens.flame.withValues(alpha: 0.12) : null,
      padding: EdgeInsets.fromLTRB(mine ? 48 : inset, tail ? 8 : 2, mine ? inset : 48, 0),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Builder(
          builder: (context) => GestureDetector(
            key: Key('msg_${m.id}'),
            onLongPress: () => onActions(rectOf(context), false),
            onSecondaryTapDown: (_) => onActions(rectOf(context), true),
            onTap: m.tick == Tick.failed ? () => session.retry(m.id) : null,
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
    final metaStyle = TextStyle(fontSize: 11, height: 16 / 11, color: colors.meta, fontFeatures: tabularFigures);
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

    if (m.kind == MessageKind.text) {
      final painter = TextPainter(
        text: TextSpan(text: m.body, style: textStyle),
        textDirection: direction,
        textScaler: scaler,
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: maxContent);
      final lines = painter.computeLineMetrics();
      final lastLine = lines.isEmpty ? 0.0 : lines.last.width;
      final inline = lastLine + gap + metaWidth <= maxContent;
      final width = math.max(painter.width, inline ? lastLine + gap + metaWidth : metaWidth).ceilToDouble();
      final height = painter.height + (inline ? 0 : metaHeight);
      final textWidth = painter.width.ceilToDouble();
      painter.dispose();
      return SizedBox(
        width: math.min(width, maxContent),
        height: height,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: textWidth,
              child: Text(m.body, style: textStyle, textWidthBasis: TextWidthBasis.longestLine),
            ),
            Positioned(right: 0, bottom: 0, child: meta),
          ],
        ),
      );
    }
    // Deleted, waiting, media placeholders: one row with room for the meta.
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(right: metaWidth + gap),
          child: DefaultTextStyle.merge(style: textStyle, child: _placeholder(context, l)),
        ),
        Positioned(right: 0, bottom: 0, child: meta),
      ],
    );
  }

  Widget _placeholder(BuildContext context, L10n l) {
    final colors = ChatColors.of(context);
    final muted = TextStyle(fontStyle: FontStyle.italic, color: colors.meta);
    final m = message;
    final (icon, text, style) = switch (m.kind) {
      MessageKind.deleted => (Icons.block, m.isMine ? l.youDeleted : l.deletedMessage, muted),
      MessageKind.undecryptable => (Icons.schedule, l.waitingMessage, muted),
      // Photos, files and voice notes get their own widgets in the media task.
      MessageKind.image => (Icons.photo_camera, l.photo, null),
      MessageKind.voice => (Icons.mic, l.voiceMessage, null),
      _ => (Icons.insert_drive_file_outlined, m.body, null),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: colors.meta),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            key: m.kind == MessageKind.undecryptable ? const Key('waiting_message') : null,
            style: style,
          ),
        ),
      ],
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
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => showSheetOrDialog<void>(
        context,
        title: '${r.key}  ${L10n.of(context).reactions}',
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final name in r.senders) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(name)),
          ],
        ),
        action: L10n.of(context).close,
      ),
      child: Container(
        height: 24,
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
    final theme = Theme.of(context);
    final colors = ChatColors.of(context);
    final dark = theme.brightness == Brightness.dark;
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
      decoration: BoxDecoration(
        color: (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.06 : 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: Tokens.flame),
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
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.accent),
                    ),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, height: 18 / 13, color: theme.colorScheme.onSurfaceVariant),
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
