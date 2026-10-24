import 'dart:convert';

import 'package:chama/services/push.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import 'fakes.dart';

final pushConfig = MockClient(
  (req) async => req.url.path == '/push/v1/config'
      ? http.Response(jsonEncode({'gateway': 'http://sygnal:5000/_matrix/push/v1/notify', 'vapid': 'V'}), 200)
      : http.Response('', 404),
);

/// A distributor connector that fails the way Android's can (no distributor
/// app answering, a broken binder).
class _FailingDistributor extends DefaultUnifiedPush {
  _FailingDistributor({required this.onPick});
  final bool onPick;
  final registered = <String?>[];

  @override
  Future<bool> tryUseCurrentOrDefaultDistributor() async =>
      onPick ? throw PlatformException(code: 'error', message: 'no distributor') : true;

  @override
  Future<void> register(String instance, List<String> features, String? messageForDistributor, String? vapid) async {
    registered.add(vapid);
    throw PlatformException(code: 'error', message: 'binder died');
  }
}

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

  test('sign-out deletes the server pusher before logging out, even when the logout is refused', () async {
    SharedPreferences.setMockInitialValues({'chama.push.pushkey': 'PUB'});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final calls = <String>[];
    final matrix = MockClient((req) async {
      calls.add('${req.url.path} ${req.body}');
      if (req.url.path.endsWith('/logout')) return http.Response('{"errcode":"M_UNKNOWN","error":"down"}', 500);
      return http.Response('{}', 200);
    });
    final service = await testService(prefs, matrix: matrix);
    service.client
      ..homeserver = testBase
      ..accessToken = 'token';
    final push = PushService(service, prefs, httpClient: pushConfig)..active.value = true;

    await service.signOut();

    final deletion = calls.indexWhere((c) => c.startsWith('/_matrix/client/v3/pushers/set'));
    expect(deletion, isNot(-1), reason: 'pusher deleted');
    final body = jsonDecode(calls[deletion].split(' ').skip(1).join(' ')) as Map<String, dynamic>;
    expect(body, containsPair('kind', null));
    expect(body, containsPair('pushkey', 'PUB'));
    expect(body, containsPair('app_id', pushAppId));
    expect(calls.indexWhere((c) => c.startsWith('/_matrix/client/v3/logout')), greaterThan(deletion));
    expect(push.active.value, isFalse);
    expect(prefs.getString('chama.push.pushkey'), isNull);
  });

  test('a failing distributor connector does not break registration: it logs and reports no push', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = await testService(prefs);
    final push = PushService(service, prefs, httpClient: pushConfig);
    final saved = UnifiedPushPlatform.instance;
    addTearDown(() => UnifiedPushPlatform.instance = saved);

    UnifiedPushPlatform.instance = _FailingDistributor(onPick: true);
    expect(await push.register(), isFalse);
    final failing = _FailingDistributor(onPick: false);
    UnifiedPushPlatform.instance = failing;
    expect(await push.register(), isFalse);
    expect(failing.registered, ['V']);
  });

  test('the push status follows the server: a pusher the server dropped shows as off', () async {
    SharedPreferences.setMockInitialValues({'chama.push.pushkey': 'PUB'});
    final prefs = await SharedPreferences.getInstance();
    var pushers = <Map<String, Object?>>[];
    var online = true;
    final matrix = MockClient((req) async {
      if (!online) throw http.ClientException('offline');
      if (req.url.path == '/_matrix/client/v3/pushers') return http.Response(jsonEncode({'pushers': pushers}), 200);
      return http.Response('{}', 200);
    });
    final service = await testService(prefs, matrix: matrix);
    service.client
      ..homeserver = testBase
      ..accessToken = 'token';
    final push = PushService(service, prefs, httpClient: pushConfig)..active.value = true;
    Map<String, Object?> pusher(String key) => {
      'app_id': pushAppId,
      'pushkey': key,
      'kind': 'http',
      'app_display_name': 'Chama',
      'device_display_name': 'Chama',
      'lang': 'pt-BR',
      'data': {'url': 'http://sygnal:5000/_matrix/push/v1/notify', 'format': 'event_id_only'},
    };

    await push.refresh();
    expect(push.active.value, isFalse, reason: 'no pusher on the server');

    pushers = [pusher('OTHER-DEVICE'), pusher('PUB')];
    await push.refresh();
    expect(push.active.value, isTrue);

    online = false;
    await push.refresh();
    expect(push.active.value, isTrue, reason: 'offline: the last known state stays');
  });
}
