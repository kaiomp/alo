import 'package:flutter/material.dart';

import '../common/actions.dart';
import '../common/deps.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/models.dart';
import 'chat_filter.dart';
import 'chat_tile.dart';

/// Search box, filter chips, "Arquivadas" row and the chats.
class ChatListView extends StatefulWidget {
  const ChatListView({super.key, required this.onOpen, this.onNewChat, this.selectedId, this.archived = false});

  final ValueChanged<String> onOpen;

  /// The empty state's "Iniciar conversa" button.
  final VoidCallback? onNewChat;
  final String? selectedId;
  final bool archived;

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final _search = TextEditingController();
  ChatFilter _filter = ChatFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _actions(ChatSummary c, Rect anchor, bool pointer) async {
    final l = L10n.of(context);
    final chat = Deps.of(context).chat;
    final run = await showActions<Future<void> Function()>(
      context,
      anchor: anchor,
      pointer: pointer,
      actions: [
        MenuAction(() => chat.setPinned(c.id, !c.isPinned), Icons.push_pin_outlined, c.isPinned ? l.unpin : l.pin),
        MenuAction(
          () => chat.setFavourite(c.id, !c.isFavourite),
          Icons.favorite_border,
          c.isFavourite ? l.unfavourite : l.favourite,
        ),
        MenuAction(() => chat.setMuted(c.id, !c.isMuted), Icons.volume_off_outlined, c.isMuted ? l.unmute : l.mute),
        MenuAction(
          () => chat.setArchived(c.id, !c.isArchived),
          Icons.archive_outlined,
          c.isArchived ? l.unarchive : l.archive,
        ),
        if (!c.isUnread) MenuAction(() => chat.markUnread(c.id, true), Icons.mark_chat_unread_outlined, l.markUnread),
      ],
    );
    await run?.call();
  }

  void _openArchived(L10n l) => Navigator.of(context).push(
    pageRoute<void>(
      context,
      Scaffold(
        appBar: AppBar(title: Text(l.archived)),
        body: ChatListView(archived: true, onOpen: widget.onOpen, selectedId: widget.selectedId),
      ),
    ),
  );

  Widget _searchBox(L10n l, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: SizedBox(
      height: 44,
      child: TextField(
        key: const Key('chat_search'),
        controller: _search,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 16),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: l.search,
          prefixIcon: const Icon(Icons.search, size: 20),
          fillColor: scheme.surfaceContainer,
          contentPadding: EdgeInsets.zero,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide.none,
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide.none,
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ),
  );

  Widget _chips(L10n l, ColorScheme scheme, ChatColors colors) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Row(
      children: [
        for (final (f, label) in [
          (ChatFilter.all, l.filterAll),
          (ChatFilter.unread, l.filterUnread),
          (ChatFilter.favourites, l.filterFavourites),
          (ChatFilter.groups, l.filterGroups),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: Key('filter_${f.name}'),
              label: Text(label),
              selected: _filter == f,
              showCheckmark: false,
              shape: const StadiumBorder(),
              side: BorderSide.none,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              labelPadding: EdgeInsets.zero,
              backgroundColor: scheme.surfaceContainer,
              selectedColor: colors.tint,
              labelStyle: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                fontWeight: _filter == f ? FontWeight.w600 : FontWeight.w500,
                color: _filter == f ? colors.onTint : scheme.onSurfaceVariant,
              ),
              onSelected: (_) => setState(() => _filter = f),
            ),
          ),
      ],
    ),
  );

  Widget _empty(L10n l) {
    if (_search.text.isNotEmpty || _filter != ChatFilter.all || widget.archived) {
      return EmptyState(icon: Icons.search, title: l.noResults);
    }
    return EmptyState(
      icon: Icons.chat_bubble_outline,
      title: l.noChatsTitle,
      body: isWide(context) ? l.noChatsBodyWide : l.noChatsBody,
      action: widget.onNewChat == null ? null : l.startConversation,
      onAction: widget.onNewChat,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    return ValueListenableBuilder<List<ChatSummary>>(
      valueListenable: Deps.of(context).chat.chats,
      builder: (context, all, _) {
        final chats = filterChats(all, filter: _filter, query: _search.text, archived: widget.archived);
        final archivedCount = widget.archived ? 0 : all.where((c) => c.isArchived).length;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _searchBox(l, scheme)),
            if (!widget.archived) SliverToBoxAdapter(child: _chips(l, scheme, colors)),
            if (archivedCount > 0)
              SliverToBoxAdapter(
                child: ListTile(
                  key: const Key('archived_row'),
                  horizontalTitleGap: 14,
                  leading: SizedBox(width: 48, child: Icon(Icons.archive_outlined, color: scheme.onSurfaceVariant)),
                  title: Text(l.archived, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  trailing: Text(
                    '$archivedCount',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.accent),
                  ),
                  onTap: () => _openArchived(l),
                ),
              ),
            if (chats.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _empty(l))
            else
              SliverList.builder(
                itemCount: chats.length,
                itemBuilder: (context, i) => ChatTile(
                  chat: chats[i],
                  selected: chats[i].id == widget.selectedId,
                  onTap: () => widget.onOpen(chats[i].id),
                  onActions: (anchor, pointer) => _actions(chats[i], anchor, pointer),
                ),
              ),
          ],
        );
      },
    );
  }
}
