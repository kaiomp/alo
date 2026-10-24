import 'dart:convert';

import 'package:chama/services/push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  test('a Sygnal Web Push (event_id_only) gives room and event; anything else is ignored', () {
    final push = utf8.encode(jsonEncode({'room_id': '!r:chama.test', 'event_id': r'$e', 'unread': 2, 'prio': 'high'}));
    expect(parsePush(push), (roomId: '!r:chama.test', eventId: r'$e'));
    expect(parsePush(utf8.encode('{"unread": 0}')), isNull); // badge-only push
    expect(parsePush(utf8.encode('not json')), isNull);
    expect(parsePush([0xff, 0xfe]), isNull);
  });

  test('the pusher asks for event_id_only pushes: no sender, no room name, no content', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final posted = <Map<String, dynamic>>[];
    final matrix = MockClient((req) async {
      if (req.url.path == '/_matrix/client/v3/pushers/set') posted.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    });
    final config = MockClient(
      (req) async => req.url.path == '/push/v1/config'
          ? http.Response(jsonEncode({'gateway': 'http://sygnal:5000/_matrix/push/v1/notify', 'vapid': 'V'}), 200)
          : http.Response('', 404),
    );
    final service = await testService(prefs, matrix: matrix);
    service.client
      ..homeserver = testBase
      ..accessToken = 'token';
    final push = PushService(service, prefs, httpClient: config);

    await push.postPusher(endpoint: 'http://10.0.2.2:8081/upAbc?up=1', pubKey: 'PUB', auth: 'AUTH');

    final pusher = posted.single;
    expect(pusher['app_id'], pushAppId);
    expect(pusher['kind'], 'http');
    expect(pusher['pushkey'], 'PUB');
    expect(pusher['data'], {
      'url': 'http://sygnal:5000/_matrix/push/v1/notify',
      'format': 'event_id_only',
      'endpoint': 'http://10.0.2.2:8081/upAbc?up=1',
      'auth': 'AUTH',
      'events_only': true,
    });
    expect(push.active.value, isTrue);
  });
}
