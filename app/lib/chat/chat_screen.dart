import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../group/group_info_screen.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_session.dart';
import '../services/models.dart';
import 'composer.dart';
import 'message_bubble.dart';
import 'timeline_items.dart';

/// Group header subtitle: the other members, then [you] (WhatsApp shows "Você").
String memberNames(List<Member> members, {required String me, required String you}) => [
  for (final m in members)
    if (m.userId != me) m.name,
  if (members.any((m) => m.userId == me)) you,
].join(', ');

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.roomId, this.onClose});

  final String roomId;

  /// Wide layout: closes the right pane instead of popping a route.
  final VoidCallback? onClose;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late final ChatSession _session;
  final _composer = GlobalKey<ComposerState>();

  @override
  void initState() {
    super.initState();
    _session = Deps.of(context).chat.openChat(widget.roomId)..open();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _session.visible = state == AppLifecycleState.resumed;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    super.dispose();
  }

  String _subtitle(L10n l) {
    final typing = _session.typing;
    if (typing.isNotEmpty) return _session.isGroup ? l.userTyping(typing.first) : l.typing;
    if (_session.isGroup) return memberNames(_session.members, me: Deps.of(context).chat.myUserId, you: l.you);
    final p = _session.presence;
    if (p == null) return '';
    if (p.online) return l.online;
    final seen = p.lastSeen;
    if (seen == null) return '';
    final now = DateTime.now();
    if (sameDay(seen, now)) return l.lastSeenToday(clock(seen, l));
    if (sameDay(seen, now.subtract(const Duration(days: 1)))) return l.lastSeenYesterday(clock(seen, l));
    return l.lastSeenDate(dayLabel(seen, now, l));
  }

  Future<void> _messageActions(Message m) async {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    const quick = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.kind != MessageKind.deleted && m.kind != MessageKind.undecryptable)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final e in quick)
                      InkWell(
                        key: Key('react_$e'),
                        onTap: () => Navigator.pop(context, 'react:$e'),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(e, style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                  ],
                ),
              ),
            if (m.kind != MessageKind.deleted)
              ListTile(
                leading: const Icon(Icons.reply),
                title: Text(l.reply),
                onTap: () => Navigator.pop(context, 'reply'),
              ),
            if (m.kind == MessageKind.text)
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(l.copy),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            if (m.isMine && m.kind == MessageKind.text)
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(l.edit),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(l.delete),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'reply':
        _composer.currentState?.replyTo(m);
      case 'edit':
        _composer.currentState?.edit(m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
      case 'delete':
        await _confirmDelete(m);
      default:
        if (choice.startsWith('react:')) await _session.toggleReaction(m.id, choice.substring(6));
    }
  }

  Future<void> _confirmDelete(Message m) async {
    final l = L10n.of(context);
    final everyone = m.isMine && m.kind != MessageKind.deleted;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteQuestion),
        actions: [
          if (everyone)
            TextButton(
              key: const Key('delete_everyone'),
              onPressed: () => Navigator.pop(context, 'all'),
              child: Text(l.deleteForEveryone),
            ),
          TextButton(
            key: const Key('delete_me'),
            onPressed: () => Navigator.pop(context, 'me'),
            child: Text(l.deleteForMe),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        ],
      ),
    );
    if (choice == 'all') await _session.deleteForEveryone(m.id);
    if (choice == 'me') await _session.deleteForMe(m.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final items = buildTimelineItems(_session.messages);
        return Scaffold(
          appBar: AppBar(
            leading: widget.onClose == null
                ? null
                : IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close)),
            titleSpacing: 0,
            title: InkWell(
              key: const Key('chat_header'),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => GroupInfoScreen(session: _session))),
              child: Row(
                children: [
                  Avatar(name: _session.name, mxc: _session.avatar, radius: 18, group: _session.isGroup),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_session.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          _subtitle(l),
                          key: const Key('chat_subtitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: ColoredBox(
            color: ChatColors.of(context).background,
            child: Column(
              children: [
                Expanded(
                  child: _session.loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          key: const Key('timeline'),
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: items.length + 1,
                          itemBuilder: (context, i) {
                            if (i == items.length) {
                              if (_session.canLoadMore) {
                                WidgetsBinding.instance.addPostFrameCallback((_) => _session.loadMore());
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              return _E2eNotice(text: l.e2eNotice);
                            }
                            return switch (items[i]) {
                              DayDivider(:final day) => _DayChip(label: dayLabel(day, DateTime.now(), l)),
                              MessageItem(:final message, :final startsGroup) => MessageBubble(
                                message: message,
                                showSender: _session.isGroup && startsGroup && !message.isMine,
                                tail: startsGroup,
                                session: _session,
                                onLongPress: () => _messageActions(message),
                              ),
                            };
                          },
                        ),
                ),
                Composer(key: _composer, session: _session),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}

class _E2eNotice extends StatelessWidget {
  const _E2eNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(32, 16, 32, 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock, size: 14),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.labelSmall)),
      ],
    ),
  );
}
