import 'package:alo/services/event_mapping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Room room;

  setUpAll(() async {
    final db = await MatrixSdkDatabase.init(
      'event_mapping_test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    room = Room(
      id: '!r:alo.test',
      client: Client('event_mapping_test', database: db),
    );
  });

  Event encrypted(String id, {Map<String, Object?>? relatesTo}) => Event(
    type: EventTypes.Encrypted,
    content: {'algorithm': 'm.megolm.v1.aes-sha2', 'ciphertext': 'x', 'm.relates_to': ?relatesTo},
    eventId: id,
    senderId: '@b:alo.test',
    originServerTs: DateTime(2026),
    room: room,
  );

  test('an undecryptable message gets its own row', () {
    expect(isVisible(encrypted(r'$m'), isGroup: false, hidden: const {}), isTrue);
  });

  test('undecryptable reactions and edits fold into their message', () {
    final reaction = encrypted(r'$r', relatesTo: {'rel_type': RelationshipTypes.reaction, 'event_id': r'$m'});
    final edit = encrypted(r'$e', relatesTo: {'rel_type': RelationshipTypes.edit, 'event_id': r'$m'});
    expect(isVisible(reaction, isGroup: false, hidden: const {}), isFalse);
    expect(isVisible(edit, isGroup: false, hidden: const {}), isFalse);
  });

  test('a message deleted for me is hidden', () {
    expect(isVisible(encrypted(r'$m'), isGroup: false, hidden: {r'$m'}), isFalse);
  });
}
