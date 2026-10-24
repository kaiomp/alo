import 'package:chama/chat_list/chat_tile.dart';
import 'package:chama/common/theme.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/models.dart';
import 'package:chama/services/ticks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(ChatSummary c) => MaterialApp(
  theme: chamaTheme(Brightness.light),
  locale: const Locale('pt'),
  supportedLocales: L10n.supportedLocales,
  localizationsDelegates: L10n.localizationsDelegates,
  home: Scaffold(
    body: ChatTile(chat: c, onTap: () {}, onLongPress: () {}),
  ),
);

void main() {
  testWidgets('group preview shows sender, unread badge and pin', (tester) async {
    await tester.pumpWidget(
      host(
        ChatSummary(
          id: '!a',
          name: 'Família',
          isGroup: true,
          lastTime: DateTime.now(),
          preview: 'Bom dia',
          previewSender: 'Mãe',
          unread: 3,
          isPinned: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Família'), findsOneWidget);
    expect(find.text('Mãe: Bom dia'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
  });

  testWidgets('my last message shows its tick and no sender', (tester) async {
    await tester.pumpWidget(
      host(
        ChatSummary(
          id: '!b',
          name: 'João',
          isGroup: false,
          lastTime: DateTime.now(),
          preview: 'Até já',
          lastTick: Tick.read,
          previewKind: MessageKind.text,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Até já'), findsOneWidget);
    expect(find.byKey(const Key('tick_read')), findsOneWidget);
  });

  testWidgets('voice note preview', (tester) async {
    await tester.pumpWidget(
      host(
        ChatSummary(id: '!c', name: 'Bia', isGroup: false, lastTime: DateTime.now(), previewKind: MessageKind.voice),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mensagem de voz'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });
}
