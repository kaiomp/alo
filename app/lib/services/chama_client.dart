import 'package:matrix/matrix.dart';

import '../auth/id_client.dart';

/// The SDK client plus one hook: during an identity reset the new public
/// cross-signing keys go to chama-id, which uploads them for us. Synapse
/// would ask for a password (UIA) there, and Chama accounts have none
/// (spec §4, docs/chama-id-api.md "reset-identity").
class ChamaClient extends Client {
  ChamaClient(
    super.clientName, {
    required super.database,
    super.supportedLoginTypes,
    super.nativeImplementations,
    super.shareKeysWith,
    super.sendTimelineEventTimeout,
  });

  /// Set for the length of one reset; receives the upload body.
  Future<void> Function(Map<String, Object?> keys)? resetUpload;

  @override
  Future<void> uploadCrossSigningKeys({
    AuthenticationData? auth,
    MatrixCrossSigningKey? masterKey,
    MatrixCrossSigningKey? selfSigningKey,
    MatrixCrossSigningKey? userSigningKey,
  }) async {
    final reset = resetUpload;
    if (reset != null && masterKey != null && selfSigningKey != null && userSigningKey != null) {
      resetUpload = null;
      try {
        return await reset({
          'master_key': masterKey.toJson(),
          'self_signing_key': selfSigningKey.toJson(),
          'user_signing_key': userSigningKey.toJson(),
        });
      } on IdError catch (e) {
        // No keys on the server yet: a first upload needs no UIA, do it here.
        if (e.code != 'no_identity') rethrow;
      }
    }
    return super.uploadCrossSigningKeys(
      auth: auth,
      masterKey: masterKey,
      selfSigningKey: selfSigningKey,
      userSigningKey: userSigningKey,
    );
  }
}
