import '../services/models.dart';

enum ChatFilter { all, unread, favourites, groups }

/// Chats for the list: archived ones only when [archived] is true, then the
/// filter chip, then the search text (ignores case and accents).
List<ChatSummary> filterChats(
  List<ChatSummary> chats, {
  ChatFilter filter = ChatFilter.all,
  String query = '',
  bool archived = false,
}) {
  final q = foldText(query.trim());
  return [
    for (final c in chats)
      if (c.isArchived == archived &&
          switch (filter) {
            ChatFilter.all => true,
            ChatFilter.unread => c.isUnread,
            ChatFilter.favourites => c.isFavourite,
            ChatFilter.groups => c.isGroup,
          } &&
          (q.isEmpty || foldText(c.name).contains(q)))
        c,
  ];
}

const _from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const _to = 'aaaaaeeeeiiiiooooouuuucn';

/// Lower case without Portuguese accents: "João" -> "joao".
String foldText(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = _from.indexOf(ch);
    out.write(i < 0 ? ch : _to[i]);
  }
  return out.toString();
}
