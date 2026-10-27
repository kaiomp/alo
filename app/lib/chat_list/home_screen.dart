import 'dart:async';

import 'package:flutter/material.dart';

import '../chat/chat_screen.dart';
import '../civic/voz_view.dart';
import '../common/avatar.dart';
import '../common/brand.dart';
import '../common/connection_banner.dart';
import '../common/deps.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import '../config.dart';
import '../feed/compose_screen.dart';
import '../feed/feed_view.dart';
import '../group/new_chat_screen.dart';
import '../l10n/app_localizations.dart';
import '../profile/me_view.dart';
import '../profile/settings_screen.dart';
import '../stories/moments_view.dart';
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
  bool _isWide = false; // last layout, for chats opened from a notification
  late final Deps _deps = Deps.of(context);

  @override
  void initState() {
    super.initState();
    // Signed in and on screen: the steps that need the user or an activity.
    _deps.notifications.opened.addListener(_openFromNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // A tap can arrive (as a new intent) before this screen exists.
      unawaited(_openFromNotification());
      unawaited(_deps.contacts.start());
      // A tap that started the app: the engine may have started headless for
      // a push, with no activity to read the tap from. First, so the chat
      // opens without waiting for the permission dialog or the push setup
      // (up to 10 s offline).
      await _deps.notifications.checkLaunch();
      await _deps.notifications.requestPermission();
      await _deps.push.register();
    });
  }

  @override
  void dispose() {
    _deps.notifications.opened.removeListener(_openFromNotification);
    super.dispose();
  }

  Future<void> _openFromNotification() async {
    final roomId = _deps.notifications.opened.value;
    if (roomId == null) return;
    _deps.notifications.opened.value = null;
    if (await _deps.chat.hasChat(roomId) && mounted) _open(roomId, _isWide);
  }

  NavigatorState _nav(bool wide) => wide ? _left.currentState! : Navigator.of(context);

  Route<T> _route<T>(bool wide, Widget page) => wide ? paneRoute<T>(page) : MaterialPageRoute<T>(builder: (_) => page);

  void _open(String roomId, bool wide) {
    unawaited(_deps.notifications.cancel(roomId));
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
        final wide = _isWide = constraints.maxWidth >= wideLayoutMinWidth;
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
    if (_deps.social != null) return _socialPhone(context, l);
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
        title: _tab == 0 ? const ChamaMark(size: 34, tile: true) : Text(tabs[_tab].$2),
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
          HomeNavBar(tabs: tabs, selected: _tab, onSelected: (i) => setState(() => _tab = i)),
        ],
      ),
    );
  }

  /// Conversas · Momentos · feed (tabFeed) · Voz · Perfil. Each tab keeps its scroll
  /// position while another one shows.
  Widget _socialPhone(BuildContext context, L10n l) {
    final voz = _deps.civic != null;
    final tabs = [
      (Icons.chat_bubble_outline_rounded, l.tabChats),
      (Icons.motion_photos_on_outlined, l.tabMoments),
      (Icons.dynamic_feed_outlined, l.tabFeed),
      if (voz) (Icons.campaign_outlined, l.tabVoice),
      (Icons.person_outline_rounded, l.tabProfile),
    ];
    final profileTab = tabs.length - 1;
    void soon() => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.comingSoon)));
    Future<void> compose() async {
      final messenger = ScaffoldMessenger.of(context);
      final posted = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ComposeScreen()));
      if (posted == true) messenger.showSnackBar(SnackBar(content: Text(l.posted)));
    }

    final fab = switch (_tab) {
      0 => FloatingActionButton(
        key: const Key('new_chat'),
        tooltip: l.newChat,
        onPressed: () => _newChat(false),
        child: const Icon(Icons.add_comment),
      ),
      1 => FloatingActionButton(
        key: const Key('new_moment'),
        tooltip: l.myMoment,
        onPressed: soon,
        child: const Icon(Icons.photo_camera_outlined),
      ),
      2 => FloatingActionButton(
        key: const Key('compose'),
        tooltip: l.newPost,
        onPressed: compose,
        child: const Icon(Icons.edit_outlined),
      ),
      _ => null,
    };
    return Scaffold(
      appBar: AppBar(
        title: _tab == 0 ? const ChamaMark(size: 34, tile: true) : Text(tabs[_tab].$2),
        actions: [
          if (_tab == profileTab)
            IconButton(
              key: const Key('settings'),
              tooltip: l.settings,
              onPressed: () => _settings(false),
              icon: const Icon(Icons.settings_outlined),
            )
          else
            _menu(false),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                ChatListView(onOpen: (id) => _open(id, false), onNewChat: () => _newChat(false)),
                const MomentsView(),
                const FeedView(),
                if (voz) const VozView(),
                const MeView(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: fab,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 0.5),
          HomeNavBar(tabs: tabs, selected: _tab, onSelected: (i) => setState(() => _tab = i)),
        ],
      ),
    );
  }
}

/// The four phone tabs.
class HomeNavBar extends StatelessWidget {
  const HomeNavBar({super.key, required this.tabs, required this.selected, required this.onSelected});
  final List<(IconData, String)> tabs;
  final int selected;
  final ValueChanged<int> onSelected;

  // Limit: labels grow only to 1.1x. A bold "Comunidades" (12 px, theme.dart)
  // breaks mid-word on a 360 px phone above that.
  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.1,
    child: NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: onSelected,
      destinations: [for (final (icon, label) in tabs) NavigationDestination(icon: Icon(icon), label: label)],
    ),
  );
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
