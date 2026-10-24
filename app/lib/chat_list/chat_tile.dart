import 'package:flutter/material.dart';

import '../chat/tick_icon.dart';
import '../common/avatar.dart';
import '../common/time_format.dart';
import '../l10n/app_localizations.dart';
import '../services/models.dart';

class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.chat,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
  });

  final ChatSummary chat;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;

  static String previewOf(ChatSummary c, L10n l) => switch (c.previewKind) {
    MessageKind.image => (c.preview ?? '').isEmpty ? l.photo : c.preview!,
    MessageKind.voice => l.voiceMessage,
    MessageKind.file => c.preview ?? l.file,
    MessageKind.deleted => c.lastTick != null ? l.youDeleted : l.deletedMessage,
    MessageKind.undecryptable => l.waitingMessage,
    _ => c.preview ?? '',
  };

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = chat.isUnread;
    final sender = chat.lastTick != null ? null : chat.previewSender;
    final kindIcon = switch (chat.previewKind) {
      MessageKind.image => Icons.photo_camera,
      MessageKind.voice => Icons.mic,
      MessageKind.file => Icons.insert_drive_file,
      MessageKind.deleted => Icons.block,
      MessageKind.undecryptable => Icons.schedule,
      _ => null,
    };
    // Right click on wide screens opens the same menu as a long press.
    return GestureDetector(
      onSecondaryTap: onLongPress,
      child: ListTile(
        key: Key('chat_${chat.name}'),
        selected: selected,
        selectedTileColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.onSurface, // the tint marks the open chat; orange text on it is hard to read
        onTap: onTap,
        onLongPress: onLongPress,
        leading: Avatar(name: chat.name, mxc: chat.avatar, group: chat.isGroup),
        title: Row(
          children: [
            Expanded(
              child: Text(
                chat.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w500),
              ),
            ),
            Text(
              listTime(chat.lastTime, DateTime.now(), l),
              style: theme.textTheme.labelSmall?.copyWith(color: unread ? scheme.primary : null),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            if (chat.lastTick != null) ...[TickIcon(chat.lastTick!), const SizedBox(width: 2)],
            if (kindIcon != null) ...[Icon(kindIcon, size: 16), const SizedBox(width: 2)],
            Expanded(
              child: Text(
                sender == null ? previewOf(chat, l) : '$sender: ${previewOf(chat, l)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (chat.isMuted) const Icon(Icons.volume_off, size: 16),
            if (chat.isPinned) const Icon(Icons.push_pin, size: 16),
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  chat.unread > 0 ? '${chat.unread}' : ' ',
                  style: TextStyle(color: scheme.onPrimary, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
