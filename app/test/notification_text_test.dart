import 'package:chama/common/notifications.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:chama/services/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

IncomingMessage msg(MessageKind kind, [String body = '']) => IncomingMessage(
  roomId: '!r:chama.test',
  eventId: r'$e',
  chatName: 'Família',
  senderId: '@ana:chama.test',
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
    expect(notificationBody(msg(MessageKind.voice), l), '🎤 Mensagem de voz');
  });

  test('a photo or a file shows as one, never by its file name', () {
    expect(notificationBody(msg(MessageKind.image, 'IMG_20261024_083112.jpg'), l), '📷 Foto');
    expect(notificationBody(msg(MessageKind.file, 'exames-mae.pdf'), l), '📎 Arquivo');
    final en = lookupL10n(const Locale('en'));
    expect(notificationBody(msg(MessageKind.image, 'IMG_1.jpg'), en), '📷 Photo');
    expect(notificationBody(msg(MessageKind.file, 'a.pdf'), en), '📎 File');
  });

  test('notification IDs are stable per chat and fit an Android int', () {
    expect(notificationId('!r:chama.test'), notificationId('!r:chama.test'));
    expect(notificationId('!r:chama.test'), isNot(notificationId('!s:chama.test')));
    expect(notificationId('!r:chama.test'), inInclusiveRange(-0x80000000, 0x7fffffff));
    // These two collide in a 31-based string hash ("Aa" and "BB").
    expect(notificationId('!Aa:chama.test'), isNot(notificationId('!BB:chama.test')));
  });
}
