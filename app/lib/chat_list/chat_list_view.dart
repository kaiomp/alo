import 'package:flutter/material.dart';

import '../common/deps.dart';
import '../l10n/app_localizations.dart';
import '../services/models.dart';
import 'chat_filter.dart';
import 'chat_tile.dart';

/// Search box, filter chips, "Arquivadas" row and the chats.
class ChatListView extends StatefulWidget {
  const ChatListView({super.key, required this.onOpen, this.selectedId, this.archived = false});

  final ValueChanged<String> onOpen;
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

  Future<void> _actions(ChatSummary c) async {
    final l = L10n.of(context);
    final chat = Deps.of(context).chat;
    final items = <(IconData, String, Future<void> Function())>[
      (Icons.push_pin_outlined, c.isPinned ? l.unpin : l.pin, () => chat.setPinned(c.id, !c.isPinned)),
      (
        Icons.favorite_border,
        c.isFavourite ? l.unfavourite : l.favourite,
        () => chat.setFavourite(c.id, !c.isFavourite),
      ),
      (Icons.volume_off_outlined, c.isMuted ? l.unmute : l.mute, () => chat.setMuted(c.id, !c.isMuted)),
      (Icons.archive_outlined, c.isArchived ? l.unarchive : l.archive, () => chat.setArchived(c.id, !c.isArchived)),
      if (!c.isUnread) (Icons.mark_chat_unread_outlined, l.markUnread, () => chat.markUnread(c.id, true)),
    ];
    final action = await showModalBottomSheet<Future<void> Function()>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (icon, label, run) in items)
              ListTile(leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(context, run)),
          ],
        ),
      ),
    );
    await action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ValueListenableBuilder<List<ChatSummary>>(
      valueListenable: Deps.of(context).chat.chats,
      builder: (context, all, _) {
        final chats = filterChats(all, filter: _filter, query: _search.text, archived: widget.archived);
        final archivedCount = widget.archived ? 0 : all.where((c) => c.isArchived).length;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  key: const Key('chat_search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: l.search,
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            if (!widget.archived)
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (archivedCount > 0)
              SliverToBoxAdapter(
                child: ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(l.archived),
                  trailing: Text('$archivedCount'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(l.archived)),
                        body: ChatListView(archived: true, onOpen: widget.onOpen),
                      ),
                    ),
                  ),
                ),
              ),
            if (chats.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(_search.text.isEmpty ? l.noChats : l.noResults)),
              )
            else
              SliverList.builder(
                itemCount: chats.length,
                itemBuilder: (context, i) => ChatTile(
                  chat: chats[i],
                  selected: chats[i].id == widget.selectedId,
                  onTap: () => widget.onOpen(chats[i].id),
                  onLongPress: () => _actions(chats[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}
