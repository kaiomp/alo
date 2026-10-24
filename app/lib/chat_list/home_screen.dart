import 'package:flutter/material.dart';

import '../chat/chat_screen.dart';
import '../common/connection_banner.dart';
import '../common/theme.dart';
import '../config.dart';
import '../group/new_chat_screen.dart';
import '../l10n/app_localizations.dart';
import '../profile/settings_screen.dart';
import 'chat_list_view.dart';

/// Phone: WhatsApp Android (app bar, 4 tabs, FAB). Wide: WhatsApp Web
/// (chat list on the left, open chat on the right).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String? _selected; // wide layout only

  void _open(BuildContext context, String roomId, bool wide) {
    if (wide) {
      setState(() => _selected = roomId);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(roomId: roomId)));
    }
  }

  Future<void> _newChat(BuildContext context, bool wide) async {
    final roomId = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewChatScreen()));
    if (roomId != null && context.mounted) _open(context, roomId, wide);
  }

  List<Widget> _actions(BuildContext context, bool wide) => [
    if (wide)
      IconButton(
        key: const Key('new_chat'),
        tooltip: L10n.of(context).newChat,
        onPressed: () => _newChat(context, wide),
        icon: const Icon(Icons.add_comment_outlined),
      ),
    PopupMenuButton<void>(
      itemBuilder: (_) => [
        PopupMenuItem(
          child: Text(L10n.of(context).settings),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideLayoutMinWidth;
        final list = ChatListView(selectedId: wide ? _selected : null, onOpen: (id) => _open(context, id, wide));
        if (wide) {
          final selected = _selected;
          return Scaffold(
            body: Column(
              children: [
                const ConnectionBanner(),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 400,
                        child: Scaffold(
                          appBar: AppBar(title: Text(l.tabChats), actions: _actions(context, wide)),
                          body: list,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: selected == null
                            ? const _EmptyPane()
                            : ChatScreen(
                                key: ValueKey(selected),
                                roomId: selected,
                                onClose: () => setState(() => _selected = null),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        final tabs = [
          (Icons.chat_outlined, l.tabChats),
          (Icons.update, l.tabUpdates),
          (Icons.groups_outlined, l.tabCommunities),
          (Icons.call_outlined, l.tabCalls),
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _tab == 0 ? l.appName : tabs[_tab].$2,
              style: TextStyle(
                color: _tab == 0 ? Theme.of(context).colorScheme.primary : null,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: _actions(context, wide),
          ),
          body: Column(
            children: [
              const ConnectionBanner(),
              Expanded(child: _tab == 0 ? list : Center(child: Text(l.comingSoon))),
            ],
          ),
          floatingActionButton: _tab == 0
              ? FloatingActionButton(
                  key: const Key('new_chat'),
                  tooltip: l.newChat,
                  onPressed: () => _newChat(context, wide),
                  child: const Icon(Icons.add_comment),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [for (final (icon, label) in tabs) NavigationDestination(icon: Icon(icon), label: label)],
          ),
        );
      },
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ColoredBox(
      color: ChatColors.of(context).background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, size: 96, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(l.appName, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(l.selectChat),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 14),
                const SizedBox(width: 4),
                Text(l.e2eNotice.split('.').first),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
