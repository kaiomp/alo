import 'package:chama/chat_list/chat_filter.dart';
import 'package:chama/services/models.dart';
import 'package:flutter_test/flutter_test.dart';

ChatSummary chat(String name, {bool group = false, int unread = 0, bool fav = false, bool archived = false}) =>
    ChatSummary(
      id: name,
      name: name,
      isGroup: group,
      lastTime: DateTime(2026),
      unread: unread,
      isFavourite: fav,
      isArchived: archived,
    );

void main() {
  final chats = [
    chat('João Silva', unread: 2),
    chat('Família', group: true, fav: true),
    chat('Trabalho', group: true),
    chat('Antigo', archived: true),
  ];
  List<String> names(List<ChatSummary> l) => l.map((c) => c.name).toList();

  test('all hides archived chats', () {
    expect(names(filterChats(chats)), ['João Silva', 'Família', 'Trabalho']);
  });

  test('filters', () {
    expect(names(filterChats(chats, filter: ChatFilter.unread)), ['João Silva']);
    expect(names(filterChats(chats, filter: ChatFilter.favourites)), ['Família']);
    expect(names(filterChats(chats, filter: ChatFilter.groups)), ['Família', 'Trabalho']);
  });

  test('search ignores case and accents', () {
    expect(names(filterChats(chats, query: 'joao')), ['João Silva']);
    expect(names(filterChats(chats, query: 'FAMI')), ['Família']);
  });

  test('archived list', () {
    expect(names(filterChats(chats, archived: true)), ['Antigo']);
  });

  test('markedUnread counts as unread', () {
    final c = ChatSummary(id: 'x', name: 'x', isGroup: false, lastTime: DateTime(2026), markedUnread: true);
    expect(filterChats([c], filter: ChatFilter.unread), hasLength(1));
  });
}
