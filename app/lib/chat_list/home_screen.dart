import 'package:flutter/material.dart';

import '../chat/chat_screen.dart';
import '../common/avatar.dart';
import '../common/brand.dart';
import '../common/connection_banner.dart';
import '../common/deps.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import '../config.dart';
import '../group/new_chat_screen.dart';
import '../l10n/app_localizations.dart';
import '../profile/settings_screen.dart';
import 'chat_list_view.dart';

/// Phone: WhatsApp Android (app bar, 4 tabs, FAB). Wide: WhatsApp Web
/// (chat list on the left, open chat on the right). On wide screens the left
/// pane has its own navigator: new chat, new group, archived and settings
/// slide in over the list and the open chat stays visible.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String? _selected; // wide layout only
  final _left = GlobalKey<NavigatorState>();
  int _profileVersion = 0; // reloads my avatar after settings

  NavigatorState _nav(bool wide) => wide ? _left.currentState! : Navigator.of(context);

  Route<T> _route<T>(bool wide, Widget page) => wide ? paneRoute<T>(page) : MaterialPageRoute<T>(builder: (_) => page);

  void _open(String roomId, bool wide) {
    if (wide) {
      // The chat opens in the right pane: close anything stacked on the list.
      _left.currentState?.popUntil((r) => r.isFirst);
      setState(() => _selected = roomId);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(roomId: roomId)));
    }
  }

  Future<void> _newChat(bool wide) async {
    final roomId = await _nav(wide).push<String>(_route(wide, const NewChatScreen()));
    if (roomId != null && mounted) _open(roomId, wide);
  }

  Future<void> _settings(bool wide) async {
    await _nav(wide).push<void>(_route(wide, const SettingsScreen()));
    if (mounted) setState(() => _profileVersion++);
  }

  Widget _menu(bool wide) => PopupMenuButton<void>(
    icon: const Icon(Icons.more_vert),
    itemBuilder: (_) => [PopupMenuItem(child: Text(L10n.of(context).settings), onTap: () => _settings(wide))],
  );

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideLayoutMinWidth;
        return wide ? _wide(context, l) : _phone(context, l);
      },
    );
  }

  Widget _wide(BuildContext context, L10n l) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = _selected;
    // Pane headers: 60 px on the container colour with a hairline under them.
    final paneTheme = theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: scheme.surfaceContainer,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(fontSize: 19),
      ),
    );
    final list = Scaffold(
      appBar: AppBar(
        leadingWidth: 72,
        leading: Center(
          child: _MyAvatar(key: ValueKey(_profileVersion), onTap: () => _settings(true)),
        ),
        titleSpacing: 0,
        title: Text(l.tabChats),
        actions: [
          IconButton(
            key: const Key('new_chat'),
            tooltip: l.newChat,
            onPressed: () => _newChat(true),
            icon: const Icon(Icons.add_comment_outlined),
          ),
          _menu(true),
          const SizedBox(width: 4),
        ],
      ),
      body: ChatListView(selectedId: selected, onOpen: (id) => _open(id, true), onNewChat: () => _newChat(true)),
    );
    return Scaffold(
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 400,
                  child: Theme(
                    data: paneTheme,
                    child: InPane(
                      child: Navigator(
                        key: _left,
                        pages: [MaterialPage<void>(key: const ValueKey('chats'), child: list)],
                        onDidRemovePage: (_) {},
                      ),
                    ),
                  ),
                ),
                VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
                Expanded(
                  child: Theme(
                    data: paneTheme,
                    child: selected == null
                        ? const _EmptyPane()
                        : ChatScreen(
                            key: ValueKey(selected),
                            roomId: selected,
                            onClose: () => setState(() => _selected = null),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phone(BuildContext context, L10n l) {
    final tabs = [
      (Icons.chat_outlined, l.tabChats),
      (Icons.update, l.tabUpdates),
      (Icons.groups_outlined, l.tabCommunities),
      (Icons.call_outlined, l.tabCalls),
    ];
    final soon = [
      null,
      (Icons.update, l.updatesSoonTitle, l.updatesSoonBody),
      (Icons.groups_outlined, l.communitiesSoonTitle, l.communitiesSoonBody),
      (Icons.call_outlined, l.callsSoonTitle, l.callsSoonBody),
    ][_tab];
    return Scaffold(
      appBar: AppBar(
        title: _tab == 0
            ? Text(
                l.wordmark,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: Tokens.flame,
                ),
              )
            : Text(tabs[_tab].$2),
        actions: [_menu(false), const SizedBox(width: 4)],
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: soon == null
                ? ChatListView(onOpen: (id) => _open(id, false), onNewChat: () => _newChat(false))
                : EmptyState(icon: soon.$1, title: soon.$2, body: soon.$3),
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              key: const Key('new_chat'),
              tooltip: l.newChat,
              onPressed: () => _newChat(false),
              child: const Icon(Icons.add_comment),
            )
          : null,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 0.5),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [for (final (icon, label) in tabs) NavigationDestination(icon: Icon(icon), label: label)],
          ),
        ],
      ),
    );
  }
}

/// My photo in the wide header; opens the settings.
class _MyAvatar extends StatefulWidget {
  const _MyAvatar({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  State<_MyAvatar> createState() => _MyAvatarState();
}

class _MyAvatarState extends State<_MyAvatar> {
  late final _profile = Deps.of(context).chat.myProfile();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _profile,
    builder: (context, snap) => IconButton(
      key: const Key('my_avatar'),
      tooltip: L10n.of(context).settings,
      padding: EdgeInsets.zero,
      onPressed: widget.onTap,
      icon: Avatar(
        name: snap.data?.name ?? '',
        seed: Deps.of(context).chat.myUserId,
        mxc: snap.data?.avatar,
        radius: 20,
      ),
    ),
  );
}

/// Right pane with no chat open (WhatsApp Web's intro panel).
class _EmptyPane extends StatelessWidget {
  const _EmptyPane();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ColoredBox(
      color: ChatColors.of(context).background,
      child: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ChamaMark(size: 80),
                  const SizedBox(height: 24),
                  Text(
                    l.chamaForWeb,
                    style: theme.textTheme.displaySmall?.copyWith(color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.selectChat,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: muted),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: muted),
                const SizedBox(width: 6),
                Text(l.e2eShort, style: TextStyle(fontSize: 13, color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
