import 'package:flutter/material.dart';

import '../common/theme.dart';
import '../common/time_format.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_session.dart';
import '../services/models.dart';
import '../services/ticks.dart';
import 'tick_icon.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.session,
    required this.onLongPress,
    this.showSender = false,
    this.tail = false,
  });

  final Message message;
  final ChatSession session;
  final VoidCallback onLongPress;
  final bool showSender;
  final bool tail;

  static String systemText(Message m, L10n l) => switch (m.systemKind) {
    SystemKind.created => l.groupCreated(m.senderName),
    SystemKind.joined => l.userJoined(m.senderName),
    SystemKind.left => l.userLeft(m.senderName),
    SystemKind.invited => l.userAdded(m.senderName, m.systemTarget ?? ''),
    SystemKind.removed => l.userRemoved(m.senderName, m.systemTarget ?? ''),
    SystemKind.renamed => l.groupRenamed(m.senderName, m.systemTarget ?? ''),
    null => '',
  };

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final colors = ChatColors.of(context);
    final theme = Theme.of(context);
    final m = message;
    if (m.kind == MessageKind.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(8)),
          child: Text(systemText(m, l), style: theme.textTheme.labelSmall),
        ),
      );
    }
    final radius = Radius.circular(12);
    return Align(
      alignment: m.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        key: Key('msg_${m.id}'),
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        onTap: m.tick == Tick.failed ? () => session.retry(m.id) : null,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75 > 520 ? 520 : MediaQuery.sizeOf(context).width * 0.75,
          ),
          margin: EdgeInsets.fromLTRB(m.isMine ? 48 : 8, tail ? 6 : 1, m.isMine ? 8 : 48, 1),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          decoration: BoxDecoration(
            color: m.isMine ? colors.mine : colors.other,
            borderRadius: BorderRadius.only(
              topLeft: !m.isMine && tail ? Radius.zero : radius,
              topRight: m.isMine && tail ? Radius.zero : radius,
              bottomLeft: radius,
              bottomRight: radius,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSender)
                Text(m.senderName, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
              if (m.reply != null) _ReplyBox(reply: m.reply!),
              _content(context, l),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.edited) Text('${l.edited} ', style: theme.textTheme.labelSmall?.copyWith(color: colors.meta)),
                  Text(clock(m.time, l), style: theme.textTheme.labelSmall?.copyWith(color: colors.meta)),
                  if (m.tick != null) ...[const SizedBox(width: 4), TickIcon(m.tick!)],
                ],
              ),
              if (m.tick == Tick.failed)
                Text(l.notSent, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error)),
              if (m.reactions.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: [
                    for (final r in m.reactions)
                      ActionChip(
                        key: Key('reaction_${m.id}_${r.key}'),
                        visualDensity: VisualDensity.compact,
                        side: r.mine ? BorderSide(color: theme.colorScheme.primary) : null,
                        label: Text(r.count > 1 ? '${r.key} ${r.count}' : r.key),
                        onPressed: () => session.toggleReaction(m.id, r.key),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, L10n l) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: ChatColors.of(context).meta);
    final m = message;
    return switch (m.kind) {
      MessageKind.text => Text(m.body),
      MessageKind.deleted => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block, size: 16),
          const SizedBox(width: 4),
          Text(m.isMine ? l.youDeleted : l.deletedMessage, style: muted),
        ],
      ),
      MessageKind.undecryptable => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(l.waitingMessage, key: const Key('waiting_message'), style: muted),
          ),
        ],
      ),
      // Photos, files and voice notes get their own widgets in the media task.
      MessageKind.image => Text('📷 ${l.photo}'),
      MessageKind.voice => Text('🎤 ${l.voiceMessage}'),
      MessageKind.file => Text('📄 ${m.body}'),
      MessageKind.system => const SizedBox.shrink(),
    };
  }
}

class _ReplyBox extends StatelessWidget {
  const _ReplyBox({required this.reply});
  final ReplyPreview reply;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final body = switch (reply.kind) {
      MessageKind.image => l.photo,
      MessageKind.voice => l.voiceMessage,
      MessageKind.file => reply.body,
      MessageKind.deleted => l.deletedMessage,
      _ => reply.body,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reply.senderName,
            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
          ),
          Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
