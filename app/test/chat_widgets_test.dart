import 'dart:async';

import 'package:chama/auth/id_client.dart';
import 'package:chama/chat/composer.dart';
import 'package:chama/chat/message_bubble.dart';
import 'package:chama/chat/voice/voice_player.dart';
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

  testWidgets('a cancelled hold stops the recording', (tester) async {
    final (service, session) = (await tester.runAsync(_session))!;
    final recorder = _Recorder();
    await tester.pumpWidget(_composer(service, session, recorder));

    final hold = await tester.startGesture(tester.getCenter(find.byKey(const Key('mic'))));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.byKey(const Key('recording_timer')), findsOneWidget);

    await hold.cancel();
    await tester.pump();
    expect(find.byKey(const Key('recording_timer')), findsNothing);
    expect(recorder.cancelled, isTrue);
  });

  testWidgets('a hold cancelled by the permission prompt never starts recording', (tester) async {
    final (service, session) = (await tester.runAsync(_session))!;
    final recorder = _Recorder()..starting = Completer();
    await tester.pumpWidget(_composer(service, session, recorder));

    final hold = await tester.startGesture(tester.getCenter(find.byKey(const Key('mic'))));
    await tester.pump(const Duration(milliseconds: 600));
    await hold.cancel();
    await tester.pump();

    // A second hold while the first recorder is still asking is ignored.
    final again = await tester.startGesture(tester.getCenter(find.byKey(const Key('mic'))));
    await tester.pump(const Duration(milliseconds: 600));
    expect(recorder.created, 1);

    recorder.starting!.complete(true);
    await tester.pump();
    expect(find.byKey(const Key('recording_timer')), findsNothing);
    expect(recorder.cancelled, isTrue);
    await again.up();
    await tester.pump();
  });
  testWidgets('the send button says "Enviar", and "Salvar edição" while editing', (tester) async {
    final (service, session) = (await tester.runAsync(_session))!;
    await tester.pumpWidget(_composer(service, session, _Recorder()));
    await tester.enterText(find.byKey(const Key('composer_text')), 'Oi');
    await tester.pumpAndSettle();
    String? tooltip() => tester.widget<IconButton>(find.byKey(const Key('send'))).tooltip;
    expect(tooltip(), 'Enviar');

    tester.state<ComposerState>(find.byType(Composer)).edit(_message(MessageKind.text, body: 'Oi'));
    await tester.pumpAndSettle();
    expect(tooltip(), 'Salvar edição');
  });

  testWidgets('with a screen reader on, a tap on the mic records and Send or Cancel ends it', (tester) async {
    final (service, session) = (await tester.runAsync(_session))!;
    final recorder = _Recorder();
    await tester.pumpWidget(_composer(service, session, recorder, accessible: true));

    await tester.tap(find.byKey(const Key('mic')));
    await tester.pump();
    expect(find.byKey(const Key('recording_timer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel_recording')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recording_timer')), findsNothing);
    expect(recorder.cancelled, isTrue);

    recorder.cancelled = false;
    await tester.tap(find.byKey(const Key('mic')));
    await tester.pump();
    expect(find.byKey(const Key('recording_timer')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // a tap must not end it
    // Shorter than 0.5 s (wall clock) is dropped.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    expect(find.byKey(const Key('recording_timer')), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('send_voice'))).tooltip, 'Enviar mensagem de voz');
    await tester.tap(find.byKey(const Key('send_voice')));
    await tester.pump();
    expect(find.byKey(const Key('recording_timer')), findsNothing);
    expect(recorder.stopped, isTrue);
    expect(recorder.cancelled, isFalse);
  });

  testWidgets('voice play and file download buttons are labelled 48 px targets', (tester) async {
    final (_, session) = (await tester.runAsync(_session))!;
    final voice = _message(MessageKind.voice, durationMs: 3000);
    final file = _message(MessageKind.file, body: 'nota.pdf', size: 2048);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            VoicePlayer(message: voice, load: () async => Uint8List(0), color: Tokens.flame),
            MessageBubble(message: file, session: session, onActions: (_, _) {}, maxWidth: 400),
          ],
        ),
      ),
    );
    final play = find.byKey(Key('voice_play_${voice.id}'));
    expect(tester.widget<IconButton>(play).tooltip, 'Reproduzir');
    expect(tester.getSize(play), const Size(48, 48));
    final download = find.byKey(Key('download_${file.id}'));
    expect(tester.widget<IconButton>(download).tooltip, 'Baixar');
    expect(tester.getSize(download), const Size(48, 48));
  });

  testWidgets('reaction pills are buttons with a 40 px target', (tester) async {
    final handle = tester.ensureSemantics();
    final (_, session) = (await tester.runAsync(_session))!;
    final m = _message(MessageKind.text, body: 'Oi', reactions: const [Reaction('👍', 2, mine: true)]);
    await tester.pumpWidget(_app(MessageBubble(message: m, session: session, onActions: (_, _) {}, maxWidth: 400)));
    final pill = find.byKey(Key('reaction_${m.id}_👍'));
    expect(tester.getSize(pill).width, greaterThanOrEqualTo(40));
    expect(tester.getSize(pill).height, greaterThanOrEqualTo(40));
    expect(tester.getSemantics(pill), isSemantics(label: '👍 2', isButton: true, isSelected: true, hasTapAction: true));
    handle.dispose();
  });
}

Message _message(
  MessageKind kind, {
  String body = '',
  int? durationMs,
  int? size,
  List<Reaction> reactions = const [],
}) => Message(
  id: r'$m',
  senderId: '@me:chama.test',
  senderName: 'Eu',
  isMine: true,
  time: DateTime(2026, 10, 24, 7, 29),
  kind: kind,
  body: body,
  tick: Tick.sent,
  durationMs: durationMs,
  size: size,
  reactions: reactions,
);

Widget _app(Widget child) => MaterialApp(
  theme: chamaTheme(Brightness.light),
  locale: const Locale('pt'),
  supportedLocales: L10n.supportedLocales,
  localizationsDelegates: L10n.localizationsDelegates,
  home: Scaffold(body: child),
);

class _Recorder implements VoiceRecorder {
  /// How many times the composer asked for a recorder.
  int created = 0;

  bool cancelled = false;

  /// Completes when the test says so (a permission prompt, say).
  Completer<bool>? starting;

  @override
  Future<bool> start() => starting?.future ?? Future.value(true);

  bool stopped = false;

  @override
  Future<RecordedVoice?> stop() async {
    stopped = true;
    return null;
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  void dispose() {}
}

Widget _composer(ChatService service, ChatSession session, _Recorder recorder, {bool accessible = false}) => Deps(
  chat: service,
  id: IdClient(Uri.parse('http://localhost:8080')),
  newRecorder: () => recorder..created += 1,
  pickFile: ({required image}) async => null,
  child: MaterialApp(
    theme: chamaTheme(Brightness.light),
    locale: const Locale('pt'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: L10n.localizationsDelegates,
    // TalkBack or VoiceOver on.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(accessibleNavigation: accessible),
      child: child!,
    ),
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
