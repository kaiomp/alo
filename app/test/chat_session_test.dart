import 'dart:async';

import 'package:alo/auth/id_client.dart';
import 'package:alo/services/alo_client.dart';
import 'package:alo/services/chat_service.dart';
import 'package:alo/services/chat_session.dart';
import 'package:alo/services/delivery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
// TimelineChunk is not exported, and a Timeline cannot be built without one.
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A room whose timeline arrives only when the test says so.
class _SlowRoom extends Room {
  _SlowRoom({required super.id, required super.client});

  final gate = Completer<Timeline>();

  @override
  Future<Timeline> getTimeline({
    void Function(int index)? onChange,
    void Function(int index)? onRemove,
    void Function(int insertID)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) => gate.future;
}

class _TrackedTimeline extends Timeline {
  _TrackedTimeline(Room room)
    : super(
        room: room,
        chunk: TimelineChunk(events: []),
      );

  bool cancelled = false;

  @override
  void cancelSubscriptions() {
    cancelled = true;
    super.cancelSubscriptions();
  }
}

void main() {
  test('leaving the chat before the timeline loads leaves nothing listening', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await MatrixSdkDatabase.init(
      'chat_session_test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    final client = AloClient('chat_session_test', database: db);
    final delivery = DeliveryTracker(client, prefs);
    final service = ChatService(
      client,
      delivery,
      IdClient(Uri.parse('http://localhost:8080')),
      prefs,
      homeserver: Uri.parse('http://localhost:8080'),
    );
    final room = _SlowRoom(id: '!r:alo.test', client: client);
    client.rooms.add(room);

    final session = ChatSession(service, room);
    final opening = session.open();
    session.dispose();
    final timeline = _TrackedTimeline(room);
    room.gate.complete(timeline);
    await opening;

    expect(timeline.cancelled, isTrue);
    // Neither of these may reach the disposed session.
    delivery.revision.value++;
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'n',
        rooms: RoomsUpdate(join: {room.id: JoinedRoomUpdate()}),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await delivery.dispose();
  });
}
