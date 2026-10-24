import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/actions.dart';
import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/theme.dart';
import '../common/time_format.dart';
import '../common/widgets.dart';
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
  String? _highlighted; // message whose action sheet is open

  // Wide layout: contact/group info as a third pane.
  bool _info = false;
  bool _infoMounted = false;

  bool get _wide => widget.onClose != null;

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

  void _openInfo() {
    if (_wide) {
      setState(() => _info = _infoMounted = true);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupInfoScreen(session: _session)));
    }
  }

  Future<void> _messageActions(Message m, Rect anchor, bool pointer) async {
    final l = L10n.of(context);
    const quick = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    final canReact = m.kind != MessageKind.deleted && m.kind != MessageKind.undecryptable;
    setState(() => _highlighted = m.id);
    final choice = await showActions<String>(
      context,
      anchor: anchor,
      pointer: pointer,
      alignEnd: m.isMine,
      emojis: canReact ? quick : const [],
      onEmoji: (e) => 'react:$e',
      actions: [
        if (m.kind != MessageKind.deleted) MenuAction('reply', Icons.reply, l.reply),
        if (m.kind == MessageKind.text) MenuAction('copy', Icons.copy, l.copy),
        if (m.isMine && m.kind == MessageKind.text) MenuAction('edit', Icons.edit, l.edit),
        MenuAction('delete', Icons.delete_outline, l.delete, destructive: true),
      ],
    );
    if (!mounted) return;
    setState(() => _highlighted = null);
    switch (choice) {
      case null:
        return;
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
    final scheme = Theme.of(context).colorScheme;
    final everyone = m.isMine && m.kind != MessageKind.deleted;
    final destructive = TextButton.styleFrom(
      foregroundColor: scheme.error,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteQuestion),
        content: Text(everyone ? l.deleteBodyEveryone : l.deleteBodyMe),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (everyone)
                TextButton(
                  key: const Key('delete_everyone'),
                  style: destructive,
                  onPressed: () => Navigator.pop(context, 'all'),
                  child: Text(l.deleteForEveryone),
                ),
              TextButton(
                key: const Key('delete_me'),
                style: destructive,
                onPressed: () => Navigator.pop(context, 'me'),
                child: Text(l.deleteForMe),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                onPressed: () => Navigator.pop(context),
                child: Text(l.cancel),
              ),
            ],
          ),
        ],
      ),
    );
    if (choice == 'all') await _session.deleteForEveryone(m.id);
    if (choice == 'me') await _session.deleteForMe(m.id);
  }

  PreferredSizeWidget _header(BuildContext context, L10n l) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typing = _session.typing.isNotEmpty;
    final subtitle = _subtitle(l);
    return AppBar(
      backgroundColor: _wide ? scheme.surfaceContainer : null,
      shape: _wide ? Border(bottom: BorderSide(color: scheme.outlineVariant)) : null,
      leading: widget.onClose == null
          ? null
          : IconButton(tooltip: l.close, onPressed: widget.onClose, icon: const Icon(Icons.close)),
      titleSpacing: _wide ? 0 : 0,
      title: InkWell(
        key: const Key('chat_header'),
        borderRadius: BorderRadius.circular(8),
        onTap: _openInfo,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Avatar(
                name: _session.name,
                seed: _session.roomId,
                mxc: _session.avatar,
                radius: 20,
                group: _session.isGroup,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _session.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        height: 22 / 17,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        key: const Key('chat_subtitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 18 / 13,
                          fontWeight: FontWeight.w400,
                          color: typing ? ChatColors.of(context).accent : scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeline(BuildContext context, L10n l) {
    final items = buildTimelineItems(_session.messages);
    // Bubbles keep their state (a decrypted photo, a playing voice note)
    // when newer messages shift them down the list.
    final indexOf = {
      for (final (i, item) in items.indexed)
        if (item case MessageItem(:final message)) message.id: i,
    };
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final inset = _wide ? math.max(16.0, width * 0.05) : 8.0;
        final maxBubble = _wide ? math.min(560.0, width * 0.65) : width * 0.78;
        // Messages fade out under the header instead of being cut.
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Color(0x00000000), Color(0xFF000000)],
            stops: [0, 12 / math.max(rect.height, 12)],
          ).createShader(rect),
          child: ListView.builder(
            key: const Key('timeline'),
            reverse: true,
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            itemCount: items.length + 1,
            findChildIndexCallback: (key) => key is ValueKey<String> ? indexOf[key.value] : null,
            itemBuilder: (context, i) {
              if (i == items.length) {
                if (_session.canLoadMore) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _session.loadMore());
                  // Every reopened chat pages through the local database first;
                  // a spinner there only flashes (a stray orange dot where the
                  // encryption notice belongs). Spin only for the server.
                  if (!_session.moreOnServer) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return E2eNotice(text: l.e2eNotice);
              }
              return switch (items[i]) {
                DayDivider(:final day) => SystemChip(
                  text: dayLabel(day, DateTime.now(), l),
                  weight: FontWeight.w500,
                  margin: 8,
                ),
                MessageItem(:final message, :final startsGroup) => MessageBubble(
                  key: ValueKey(message.id),
                  message: message,
                  showSender: _session.isGroup && startsGroup && !message.isMine,
                  tail: startsGroup,
                  session: _session,
                  maxWidth: maxBubble,
                  inset: inset,
                  highlighted: _highlighted == message.id,
                  onActions: (anchor, pointer) => _messageActions(message, anchor, pointer),
                ),
              };
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final chat = ListenableBuilder(
      listenable: _session,
      builder: (context, _) => Scaffold(
        appBar: _header(context, l),
        body: ColoredBox(
          color: ChatColors.of(context).background,
          child: Column(
            children: [
              Expanded(
                child: _session.loading ? const Center(child: CircularProgressIndicator()) : _timeline(context, l),
              ),
              Composer(key: _composer, session: _session, wide: _wide),
            ],
          ),
        ),
      ),
    );
    if (!_wide) return chat;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: chat),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: _info ? 380 : 0,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: scheme.outlineVariant)),
          ),
          onEnd: () {
            if (!_info) setState(() => _infoMounted = false);
          },
          child: !_infoMounted
              ? null
              : ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 380,
                    maxWidth: 380,
                    child: InPane(
                      child: Navigator(
                        pages: [
                          MaterialPage<void>(
                            child: GroupInfoScreen(
                              session: _session,
                              onClose: () => setState(() => _info = false),
                              onLeft: widget.onClose,
                            ),
                          ),
                        ],
                        onDidRemovePage: (_) {},
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
