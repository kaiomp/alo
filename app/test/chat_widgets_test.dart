import 'dart:async';

import 'package:chama/auth/id_client.dart';
import 'package:chama/chat/composer.dart';
import 'package:chama/chat/message_bubble.dart';
import 'package:chama/chat/voice/voice_recorder.dart';
import 'package:chama/common/deps.dart';
import 'package:chama/common/theme.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/chama_client.dart';
import 'package:chama/services/chat_service.dart';
import 'package:chama/services/chat_session.dart';
import 'package:chama/services/delivery.dart';
import 'package:chama/services/models.dart';
import 'package:chama/services/ticks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('the time keeps an 8 px gap after the text, "Editada" included', (tester) async {
    // The real font: the bug was measuring the time in the default font and
    // drawing it in Inter.
    await tester.runAsync(() async {
      await (FontLoader('Inter')..addFont(rootBundle.load('assets/fonts/Inter-400.ttf'))).load();
    });
    final (_, session) = (await tester.runAsync(_session))!;
    const body = 'Chego às 13h';
    await tester.pumpWidget(
      MaterialApp(
        theme: chamaTheme(Brightness.light),
        locale: const Locale('pt'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Scaffold(
          body: MessageBubble(
            message: Message(
              id: r'$e',
              senderId: '@me:chama.test',
              senderName: 'Eu',
              isMine: true,
              time: DateTime(2026, 10, 24, 7, 29),
              kind: MessageKind.text,
              body: body,
              edited: true,
              tick: Tick.read,
            ),
            session: session,
            onActions: (_, _) {},
            maxWidth: 400,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = tester.renderObject<RenderParagraph>(find.text(body));
    final textEnd = text
        .localToGlobal(
          text
              .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: body.length))
              .last
              .toRect()
              .topRight,
        )
        .dx;
    final metaStart = tester.getTopLeft(find.textContaining('Editada')).dx;
    expect(metaStart - textEnd, inInclusiveRange(8, 9.5));
  });

  testWidgets('holding the mic records, sliding left cancels', (tester) async {
    final (service, session) = (await tester.runAsync(_session))!;
    final recorder = _Recorder();
    await tester.pumpWidget(_composer(service, session, recorder));

    // A touch hold: the button's tooltip must not take the long press.
    final hold = await tester.startGesture(tester.getCenter(find.byKey(const Key('mic'))));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.byKey(const Key('recording_timer')), findsOneWidget);

    await hold.moveBy(const Offset(-100, 0));
    await tester.pump();
    await hold.up();
    await tester.pump();
    expect(find.byKey(const Key('recording_timer')), findsNothing);
    expect(recorder.cancelled, isTrue);
  });

  testWidgets('a recorder that starts after the finger is lifted is stopped at once', (tester) async {
    final (service, session) = (await tester.runAsync(_session))!;
    final recorder = _Recorder()..starting = Completer();
    await tester.pumpWidget(_composer(service, session, recorder));

    final hold = await tester.startGesture(tester.getCenter(find.byKey(const Key('mic'))));
    await tester.pump(const Duration(milliseconds: 600));
    await hold.up();
    await tester.pump();
    recorder.starting!.complete(true);
    await tester.pump();
    expect(find.byKey(const Key('recording_timer')), findsNothing);
    expect(recorder.cancelled, isTrue);
  });
}

class _Recorder implements VoiceRecorder {
  bool cancelled = false;

  /// Completes when the test says so (a permission prompt, say).
  Completer<bool>? starting;

  @override
  Future<bool> start() => starting?.future ?? Future.value(true);

  @override
  Future<RecordedVoice?> stop() async => null;

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  void dispose() {}
}

Widget _composer(ChatService service, ChatSession session, VoiceRecorder recorder) => Deps(
  chat: service,
  id: IdClient(Uri.parse('http://localhost:8080')),
  newRecorder: () => recorder,
  pickFile: ({required image}) async => null,
  child: MaterialApp(
    theme: chamaTheme(Brightness.light),
    locale: const Locale('pt'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: L10n.localizationsDelegates,
    home: Scaffold(body: Composer(session: session)),
  ),
);

Future<(ChatService, ChatSession)> _session() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = await MatrixSdkDatabase.init(
    'message_bubble_test',
    database: await databaseFactoryFfi.openDatabase(':memory:'),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client = ChamaClient('message_bubble_test', database: db);
  final service = ChatService(
    client,
    DeliveryTracker(client, prefs),
    IdClient(Uri.parse('http://localhost:8080')),
    prefs,
    homeserver: Uri.parse('http://localhost:8080'),
  );
  return (service, ChatSession(service, Room(id: '!r:chama.test', client: client)));
}
