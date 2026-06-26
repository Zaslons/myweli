import 'dart:convert';
import 'dart:math';

import 'auth/provider_auth_repository.dart';
import 'storage/storage_service.dart';

/// Outcome of a sign request; [data] is the response body on success.
typedef SignResult = ({bool ok, String? error, Map<String, dynamic>? data});

/// Issues a presigned upload for an authenticated salon (design:
/// docs/design/pro-image-upload-pipeline.md). The object **key is built from
/// the token's `providerId`**, so a salon can only write under its own prefix —
/// the client never chooses the path. Content-type is allowlisted and the size
/// cap is signed into the policy; bytes never pass through the API.
class UploadSigningService {
  UploadSigningService(this._providerAuth, this._storage);

  final ProviderAuthRepository _providerAuth;
  final StorageService _storage;

  /// jpeg/png/webp → file extension.
  static const _allowedTypes = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  };
  static const _allowedPurposes = {'gallery'};
  static const _maxBytes = 5 * 1024 * 1024; // 5 MB
  static const _ttl = Duration(minutes: 5);

  final _rng = Random.secure();

  Future<SignResult> sign(
    String accountId, {
    required Object? contentType,
    required Object? purpose,
  }) async {
    final account = await _providerAuth.accountById(accountId);
    final providerId = account?.providerId;
    if (providerId == null) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final ext = _allowedTypes[contentType];
    if (contentType is! String || ext == null) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    if (purpose is! String || !_allowedPurposes.contains(purpose)) {
      return (ok: false, error: 'invalid_input', data: null);
    }

    final key = '$purpose/$providerId/${_objectId()}.$ext';
    final post = _storage.presignPost(
      key: key,
      contentType: contentType,
      maxBytes: _maxBytes,
      ttl: _ttl,
    );

    return (
      ok: true,
      error: null,
      data: {
        'method': 'POST',
        'uploadUrl': post.url,
        'fields': post.fields,
        'publicUrl': _storage.publicUrl(key),
        'maxBytes': _maxBytes,
        'expiresInSeconds': _ttl.inSeconds,
      },
    );
  }

  /// 16 random bytes → unguessable, URL-safe object id (no padding).
  String _objectId() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
