import 'package:chama/common/notifications.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

IncomingMessage msg(MessageKind kind, [String body = '']) => IncomingMessage(
  roomId: '!r:chama.test',
  eventId: r'$e',
  chatName: 'Família',
  senderName: 'Ana',
  kind: kind,
  isGroup: true,
  time: DateTime(2026, 10, 24),
  body: body,
);

void main() {
  final l = lookupL10n(const Locale('pt'));

  test('notification text per message kind; "Nova mensagem" when it cannot be decrypted yet', () {
    expect(notificationBody(msg(MessageKind.text, 'oi'), l), 'oi');
    expect(notificationBody(msg(MessageKind.undecryptable), l), 'Nova mensagem');
    expect(notificationBody(msg(MessageKind.image), l), 'Foto');
    expect(notificationBody(msg(MessageKind.voice), l), '🎤 Mensagem de voz');
    expect(notificationBody(msg(MessageKind.file, 'nota.pdf'), l), '📄 nota.pdf');
  });

  test('notification IDs are stable per chat and fit an Android int', () {
    expect(notificationId('!r:chama.test'), notificationId('!r:chama.test'));
    expect(notificationId('!r:chama.test'), isNot(notificationId('!s:chama.test')));
    expect(notificationId('!r:chama.test'), inInclusiveRange(0, 0x3fffffff));
  });
}
