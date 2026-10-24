import 'package:chama/services/delivery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const roomId = '!r:chama.test';
  late Client client;
  late Room room;
  late DeliveryTracker tracker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = await MatrixSdkDatabase.init(
      'delivery_test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    client = Client('delivery_test', database: db);
    room = Room(id: roomId, client: client);
    client.rooms.add(room);
    tracker = DeliveryTracker(client, await SharedPreferences.getInstance());
  });

  tearDown(() => tracker.dispose());

  void member(String userId, String membership) => room.setState(
    Event(
      type: EventTypes.RoomMember,
      content: {'membership': membership},
      eventId: '\$$userId$membership',
      senderId: userId,
      stateKey: userId,
      originServerTs: DateTime(2026),
      room: room,
    ),
  );

  Future<void> ack(String sender, int ts) async {
    client.onToDeviceEvent.add(
      ToDeviceEvent(sender: sender, type: deliveredEventType, content: {'room_id': roomId, 'ts': ts}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('acks from joined members count', () async {
    member('@b:chama.test', 'join');
    await ack('@b:chama.test', 100);
    expect(tracker.deliveredUpTo(roomId), {'@b:chama.test': 100});
  });

  Future<void> syncDone() async {
    client.onSync.add(SyncUpdate(nextBatch: 'next'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('acks from people not joined to the room are ignored', () async {
    member('@left:chama.test', 'leave');
    await ack('@left:chama.test', 100);
    await ack('@stranger:chama.test', 100);
    await syncDone();
    expect(tracker.deliveredUpTo(roomId), isEmpty);
  });

  test('an ack that arrives in the same sync as the join counts', () async {
    member('@b:chama.test', 'invite');
    await ack('@b:chama.test', 100);
    expect(tracker.deliveredUpTo(roomId), isEmpty);
    member('@b:chama.test', 'join'); // the sync's room state, applied after its to-device events
    await syncDone();
    expect(tracker.deliveredUpTo(roomId), {'@b:chama.test': 100});
  });
}
