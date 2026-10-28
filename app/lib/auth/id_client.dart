import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';

/// A typed alo-id error (`{"error": "<code>", ...}`), or `network` when the
/// server could not be reached.
class IdError implements Exception {
  const IdError(this.code, {this.retryAfter});
  final String code;
  final int? retryAfter;

  /// pt-BR / English text for the user.
  String message(L10n l) => switch (code) {
    'invalid_phone' => l.errInvalidPhone,
    'invalid_code' => l.errInvalidCode,
    'expired' => l.errExpired,
    'too_many_attempts' => l.errTooManyAttempts,
    'forbidden' => l.errForbidden,
    'invalid_token' => l.errSessionExpired,
    'invalid_keys' => l.errInvalidKeys,
    'rate_limited' => l.errRateLimited(retryAfter ?? 60),
    'network' => l.errNetwork,
    _ => l.errUnknown,
  };

  @override
  String toString() => 'IdError($code)';
}

class IdLogin {
  const IdLogin({required this.phone, required this.userId, required this.loginToken, required this.newAccount});
  final String phone;

  /// Opaque Matrix ID (`@u…:server`); never derived from the phone (spec §4).
  final String userId;
  final String loginToken;
  final bool newAccount;
}

/// Client for the alo-id sign-in API (M1 plan, Task 3).
class IdClient {
  IdClient(this.baseUrl, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;

  /// Posts [body] and hands the JSON answer to [parse]. A body of the wrong
  /// shape is an `internal` error, never a raw [TypeError].
  Future<T> _post<T>(
    String path,
    Map<String, Object?> body,
    T Function(Map<String, dynamic> json) parse, {
    String? accessToken,
  }) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            baseUrl.resolve(path),
            headers: {
              'content-type': 'application/json',
              if (accessToken != null) 'authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const IdError('network');
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw const IdError('internal');
    }
    if (res.statusCode != 200) {
      final code = json['error'], retry = json['retry_after'];
      throw IdError(code is String ? code : 'internal', retryAfter: retry is int ? retry : null);
    }
    try {
      return parse(json);
    } on TypeError {
      throw const IdError('internal');
    }
  }

  /// Sends the SMS. Returns the phone digits as the server normalised them
  /// and the seconds until a new code may be requested.
  Future<({String phone, int retryAfter})> requestCode(String phoneDigits) async {
    return _post('/id/v1/otp/request', {
      'phone': phoneDigits,
    }, (json) => (phone: json['phone'] as String, retryAfter: json['retry_after'] as int));
  }

  Future<IdLogin> verifyCode(String phoneDigits, String code) async {
    // `homeserver` in the answer is the server's public URL; the app keeps its
    // own base URL instead (the emulator reaches the same server as 10.0.2.2).
    return _post(
      '/id/v1/otp/verify',
      {'phone': phoneDigits, 'code': code},
      (json) => IdLogin(
        phone: json['phone'] as String,
        userId: json['user_id'] as String,
        loginToken: json['login_token'] as String,
        newAccount: json['new_account'] as bool? ?? false,
      ),
    );
  }

  /// Alô accounts for these phone numbers (E.164 digits), as
  /// `{digits: user_id}`. Numbers without an account are left out. The server
  /// only sees SHA-256 hashes of the digits (spec §6, "Contacts").
  Future<Map<String, String>> lookup(List<String> phoneDigits, {required String accessToken}) async {
    final byHash = {for (final d in phoneDigits) sha256.convert(utf8.encode(d)).toString(): d};
    return _post(
      '/id/v1/directory/lookup',
      {'hashes': byHash.keys.toList()},
      (json) => {
        for (final r in (json['registered'] as List).cast<Map<String, dynamic>>())
          if (byHash[r['hash']] != null) byHash[r['hash']]!: r['user_id'] as String,
      },
      accessToken: accessToken,
    );
  }

  /// Replaces this account's cross-signing keys (new phone, no recovery key;
  /// spec §4–5). [keys] is the body of Matrix `keys/device_signing/upload`
  /// (public keys only). Needs a fresh SMS code. Signs out other devices.
  Future<void> resetIdentity(
    String phoneDigits,
    String code,
    Map<String, Object?> keys, {
    required String accessToken,
  }) => _post(
    '/id/v1/account/reset-identity',
    {'phone': phoneDigits, 'code': code, 'keys': keys},
    (_) {},
    accessToken: accessToken,
  );
}
