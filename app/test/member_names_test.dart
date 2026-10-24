import 'package:chama/chat/chat_screen.dart';
import 'package:chama/services/models.dart';
import 'package:flutter_test/flutter_test.dart';

Member m(String id, String name) => Member(userId: id, name: name, isAdmin: false);

void main() {
  test('group header lists the others, then "Você" for me', () {
    final members = [m('@me', 'Ana Teste'), m('@b', 'Bia'), m('@c', 'Caio')];
    expect(memberNames(members, me: '@me', you: 'Você'), 'Bia, Caio, Você');
  });
}
