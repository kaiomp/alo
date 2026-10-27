import 'package:flutter/material.dart';

import '../chat/tick_icon.dart';
import '../common/actions.dart';
import '../common/avatar.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../l10n/app_localizations.dart';
import '../services/models.dart';

/// One chat in the list: 72 px row, avatar, name and time, preview and badges.
class ChatTile extends StatelessWidget {
  const ChatTile({super.key, required this.chat, required this.onTap, required this.onActions, this.selected = false});

  final ChatSummary chat;
  final VoidCallback onTap;

  /// Long press or right click; [anchor] is where the menu opens.
  final void Function(Rect anchor, bool pointer) onActions;
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
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
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
    final muted = scheme.onSurfaceVariant;
    final faint = muted.withValues(alpha: 0.7);
    return Material(
      color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
      child: Builder(
        builder: (context) => InkWell(
          key: Key('chat_${chat.name}'),
          onTap: onTap,
          onLongPress: () => onActions(rectOf(context), false),
          onSecondaryTapDown: (d) => onActions(d.globalPosition & Size.zero, true),
          child: SizedBox(
            height: 72,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Avatar(name: chat.name, seed: chat.id, mxc: chat.avatar, group: chat.isGroup),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                chat.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 22 / 16,
                                  fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              listTime(chat.lastTime, DateTime.now(), l),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                                fontFeatures: tabularFigures,
                                color: unread && !chat.isMuted ? colors.accent : muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (!chat.encrypted) ...[
                              Icon(
                                Icons.lock_open,
                                key: const Key('not_encrypted_icon'),
                                size: 16,
                                color: muted,
                                semanticLabel: l.notEncryptedNotice,
                              ),
                              const SizedBox(width: 3),
                            ],
                            if (chat.lastTick != null) ...[TickIcon(chat.lastTick!), const SizedBox(width: 3)],
                            if (kindIcon != null) ...[Icon(kindIcon, size: 16, color: muted), const SizedBox(width: 3)],
                            Expanded(
                              child: Text(
                                sender == null ? previewOf(chat, l) : '$sender: ${previewOf(chat, l)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 20 / 14,
                                  color: unread ? scheme.onSurface : muted,
                                ),
                              ),
                            ),
                            if (chat.isMuted) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.volume_off, size: 18, color: faint),
                            ],
                            if (chat.isPinned) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.push_pin, size: 18, color: faint),
                            ],
                            if (unread) ...[
                              const SizedBox(width: 6),
                              // Muted: grey, and a dot (the server counts nothing that does not notify).
                              _Badge(
                                count: chat.unread,
                                color: chat.isMuted ? muted : Tokens.ipe,
                                onColor: chat.isMuted ? scheme.surface : Tokens.acaiInk,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.color, required this.onColor});
  final int count;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('unread_badge'),
    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    child: count > 0
        ? Text(
            '$count',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: onColor,
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          )
        : null,
  );
}
