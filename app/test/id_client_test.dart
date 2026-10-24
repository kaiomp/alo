import 'dart:convert';

import 'package:chama/auth/id_client.dart';
import 'package:chama/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final base = Uri.parse('http://localhost:8080');

  IdClient client(int status, Map<String, Object?> body, {void Function(http.Request)? onRequest}) => IdClient(
    base,
    httpClient: MockClient((req) async {
      onRequest?.call(req);
      return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
    }),
  );

  test('requestCode posts the phone and returns the normalised number', () async {
    late http.Request sent;
    final c = client(200, {'phone': '5511987654321', 'retry_after': 60}, onRequest: (r) => sent = r);
    final r = await c.requestCode('5511987654321');
    expect(sent.url.toString(), 'http://localhost:8080/id/v1/otp/request');
    expect(jsonDecode(sent.body), {'phone': '5511987654321'});
    expect(r.phone, '5511987654321');
    expect(r.retryAfter, 60);
  });

  test('verifyCode returns the login token', () async {
    final c = client(200, {
      'phone': '5511987654321',
      'user_id': '@u7k3m9q2x4w8a1b5c:chama.test',
      'login_token': 'jwt',
      'homeserver': 'http://localhost:8080',
      'new_account': true,
    });
    final login = await c.verifyCode('5511987654321', '000000');
    expect(login.userId, '@u7k3m9q2x4w8a1b5c:chama.test');
    expect(login.loginToken, 'jwt');
    expect(login.newAccount, isTrue);
  });

  test('lookup sends SHA-256 hashes with the access token and maps back to digits', () async {
    late http.Request sent;
    // sha256("5511987654321")
    const hash = '029c7290f14c4516673508635f0519db95f7daf42057fd0e4ad1de84c5408a66';
    final c = client(200, {
      'registered': [
        {'hash': hash, 'user_id': '@u7k3m9q2x4w8a1b5c:chama.test'},
      ],
    }, onRequest: (r) => sent = r);
    final found = await c.lookup(['5511987654321', '5511900000000'], accessToken: 'tok');
    expect(sent.headers['authorization'], 'Bearer tok');
    expect((jsonDecode(sent.body)['hashes'] as List), contains(hash));
    expect(sent.body, isNot(contains('5511987654321'))); // only hashes leave the device
    expect(found, {'5511987654321': '@u7k3m9q2x4w8a1b5c:chama.test'});
  });

  test('typed errors keep code and retry_after', () async {
    final c = client(429, {'error': 'rate_limited', 'retry_after': 42});
    await expectLater(
      c.requestCode('5511987654321'),
      throwsA(
        isA<IdError>().having((e) => e.code, 'code', 'rate_limited').having((e) => e.retryAfter, 'retryAfter', 42),
      ),
    );
  });

  test('malformed bodies are internal errors, never type errors', () async {
    Matcher internal = throwsA(isA<IdError>().having((e) => e.code, 'code', 'internal'));
    await expectLater(client(200, {'phone': 5511, 'retry_after': 60}).requestCode('1'), internal);
    await expectLater(client(200, {}).requestCode('1'), internal);
    await expectLater(client(200, {'phone': '1'}).verifyCode('1', '000000'), internal);
    await expectLater(client(200, {'registered': 'x'}).lookup(['1'], accessToken: 't'), internal);
    await expectLater(
      client(200, {
        'registered': [42],
      }).lookup(['1'], accessToken: 't'),
      internal,
    );
    await expectLater(client(400, {'error': 7}).requestCode('1'), internal);
    await expectLater(
      client(429, {'error': 'rate_limited', 'retry_after': 'soon'}).requestCode('1'),
      throwsA(isA<IdError>().having((e) => e.code, 'code', 'rate_limited').having((e) => e.retryAfter, 'retry', null)),
    );
    final list = IdClient(base, httpClient: MockClient((_) async => http.Response('[1]', 200)));
    await expectLater(list.requestCode('1'), internal);
  });

  test('resetIdentity posts phone, code and keys with the access token', () async {
    late http.Request sent;
    final c = client(200, {}, onRequest: (r) => sent = r);
    final keys = {
      'master_key': {
        'user_id': '@u7k3m9q2x4w8a1b5c:chama.test',
        'usage': ['master'],
        'keys': {'ed25519:abc': 'abc'},
      },
    };
    await c.resetIdentity('5511987654321', '000000', keys, accessToken: 'tok');
    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'http://localhost:8080/id/v1/account/reset-identity');
    expect(sent.headers['authorization'], 'Bearer tok');
    expect(jsonDecode(sent.body), {'phone': '5511987654321', 'code': '000000', 'keys': keys});
  });

  test('unreachable server is a network error', () async {
    final c = IdClient(base, httpClient: MockClient((_) async => throw http.ClientException('down')));
    await expectLater(c.requestCode('1'), throwsA(isA<IdError>().having((e) => e.code, 'code', 'network')));
  });

  test('error codes map to pt-BR text', () async {
    final l = await L10n.delegate.load(const Locale('pt'));
    expect(const IdError('invalid_code').message(l), 'Código incorreto. Confira e tente de novo.');
    expect(const IdError('rate_limited', retryAfter: 42).message(l), 'Muitas tentativas. Tente de novo em 42 s.');
    expect(const IdError('network').message(l), 'Sem conexão com o servidor. Verifique sua internet.');
    expect(const IdError('something_new').message(l), 'Algo deu errado. Tente de novo.');
  });

  test('identity reset errors each have their own text', () async {
    final l = await L10n.delegate.load(const Locale('pt'));
    expect(
      const IdError('invalid_keys').message(l),
      'Não foi possível salvar as novas chaves. Peça um novo código e tente de novo.',
    );
    final texts = {
      for (final code in ['invalid_keys', 'forbidden', 'invalid_token', 'something_new']) IdError(code).message(l),
    };
    expect(texts, hasLength(4));
  });
}
