import 'package:alo/services/delivery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const roomId = '!r:alo.test';
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

  /// An ack as the SDK hands it over after Olm decryption.
  Future<void> ack(String sender, int ts, {bool olm = true}) async {
    client.onToDeviceEvent.add(
      ToDeviceEvent(
        sender: sender,
        type: deliveredEventType,
        content: {'room_id': roomId, 'ts': ts},
        encryptedContent: olm ? {'algorithm': AlgorithmTypes.olmV1Curve25519AesSha2} : null,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('acks from joined members count', () async {
    member('@b:alo.test', 'join');
    await ack('@b:alo.test', 100);
    expect(tracker.deliveredUpTo(roomId), {'@b:alo.test': 100});
  });

  Future<void> syncDone() async {
    client.onSync.add(SyncUpdate(nextBatch: 'next'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('acks from people not joined to the room are ignored', () async {
    member('@left:alo.test', 'leave');
    await ack('@left:alo.test', 100);
    await ack('@stranger:alo.test', 100);
    await syncDone();
    expect(tracker.deliveredUpTo(roomId), isEmpty);
  });

  test('plaintext acks are ignored: the server could forge them', () async {
    member('@b:alo.test', 'join');
    await ack('@b:alo.test', 100, olm: false);
    expect(tracker.deliveredUpTo(roomId), isEmpty);
  });

  test('an ack that arrives in the same sync as the join counts', () async {
    member('@b:alo.test', 'invite');
    await ack('@b:alo.test', 100);
    expect(tracker.deliveredUpTo(roomId), isEmpty);
    member('@b:alo.test', 'join'); // the sync's room state, applied after its to-device events
    await syncDone();
    expect(tracker.deliveredUpTo(roomId), {'@b:alo.test': 100});
  });

  group('outgoing', () {
    late _RecordingClient sender;
    late DeliveryTracker tracker;

    setUp(() async {
      final db = await MatrixSdkDatabase.init(
        'delivery_out_test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      );
      sender = _RecordingClient(db)..setUserId('@me:alo.test');
      sender.rooms.add(Room(id: roomId, client: sender));
      tracker = DeliveryTracker(sender, await SharedPreferences.getInstance());
    });

    tearDown(() => tracker.dispose());

    Future<void> arrives(String type) async {
      sender.onTimelineEvent.add(
        Event(
          type: type,
          content: {'msgtype': MessageTypes.Text, 'body': 'oi'},
          eventId: '\$$type',
          senderId: '@b:alo.test',
          originServerTs: DateTime(2026),
          room: sender.getRoomById(roomId)!,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100)); // acks go out once a second
    }

    test('acks go Olm-encrypted, never in clear', () async {
      await arrives(EventTypes.Message);
      expect(sender.encrypted, [deliveredEventType]);
      expect(sender.plaintext, isEmpty);
    });

    test('a message this device cannot decrypt is not acked', () async {
      await arrives(EventTypes.Encrypted);
      expect(sender.encrypted, isEmpty);
      expect(sender.plaintext, isEmpty);
    });
  });
}

/// Records to-device sends instead of making them.
class _RecordingClient extends Client {
  _RecordingClient(DatabaseApi db) : super('delivery_out_test', database: db);

  final encrypted = <String>[];
  final plaintext = <String>[];

  @override
  Future<void> sendToDeviceEncrypted(
    List<DeviceKeys> deviceKeys,
    String eventType,
    Map<String, dynamic> message, {
    String? messageId,
    bool onlyVerified = false,
  }) async => encrypted.add(eventType);

  @override
  Future<void> sendToDevicesOfUserIds(
    Set<String> users,
    String eventType,
    Map<String, dynamic> message, {
    String? messageId,
  }) async => plaintext.add(eventType);
}
