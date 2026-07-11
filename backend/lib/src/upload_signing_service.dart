import 'dart:convert';
import 'dart:math';

import 'access/capabilities.dart';
import 'access/membership_service.dart';
import 'auth/provider_auth_repository.dart';
import 'storage/storage_service.dart';

/// Outcome of a sign request; [data] is the response body on success.
typedef SignResult = ({bool ok, String? error, Map<String, dynamic>? data});

/// Issues a presigned upload for an authenticated salon. The object **key is
/// built server-side from the token**, so a salon can only write under its own
/// prefix — the client never chooses the path. Content-type is allowlisted and
/// the size cap is signed into the policy; bytes never pass through the API.
/// Two purposes (designs: pro-image-upload-pipeline.md, pro-kyc.md):
/// - `gallery` → **public** bucket, prefix `gallery/{providerId}` (needs a
///   linked salon), returns a `publicUrl`.
/// - `kyc` → **private** bucket, prefix `kyc/{accountId}`, returns the `key`
///   only (no public URL — ID documents are never public); accepts PDF too.
class UploadSigningService {
  UploadSigningService(this._providerAuth, this._members, this._storage);

  final ProviderAuthRepository _providerAuth;
  final MembershipService _members;
  final StorageService _storage;

  /// content-type → file extension, per purpose.
  static const _imageTypes = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  };
  static const _kycTypes = {..._imageTypes, 'application/pdf': 'pdf'};
  static const _maxBytes = 5 * 1024 * 1024; // 5 MB
  static const _ttl = Duration(minutes: 5);

  final _rng = Random.secure();

  /// Sign an upload. [accountId] is the token's `sub` (a provider account id for
  /// gallery/kyc; the consumer's user id for deposit). The route gates which
  /// role may use which purpose.
  Future<SignResult> sign(
    String accountId, {
    required Object? contentType,
    required Object? purpose,
  }) async {
    final isKyc = purpose == 'kyc';
    final isDeposit = purpose == 'deposit';
    final isGallery = purpose == 'gallery';
    // Consumer review photos (P2b, audit 2.13): public like gallery, but
    // scoped to the USER token — review/{userId}.
    final isReview = purpose == 'review';
    if (!isGallery && !isKyc && !isDeposit && !isReview) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    // KYC accepts PDF; gallery + deposit (screenshots) are images only.
    final ext = (isKyc ? _kycTypes : _imageTypes)[contentType];
    if (contentType is! String || ext == null) {
      return (ok: false, error: 'invalid_input', data: null);
    }

    // Prefix + target bucket per purpose. Deposit is a CONSUMER upload scoped
    // to the user id (no provider account); kyc → the provider account; gallery
    // → the linked salon (public).
    final String prefixId;
    final StorageBucket bucket;
    if (isDeposit) {
      prefixId = accountId;
      bucket = StorageBucket.deposit;
    } else if (isReview) {
      // Public (review tiles render them), under the caller's own prefix.
      prefixId = accountId;
      bucket = StorageBucket.public;
    } else if (isKyc) {
      if (await _providerAuth.accountById(accountId) == null) {
        return (ok: false, error: 'forbidden', data: null);
      }
      prefixId = accountId;
      bucket = StorageBucket.kyc;
    } else {
      // Module `access` R1: gallery uploads need catalogue.manage inside the
      // caller's acting salon (R6 adds an explicit salon selection).
      final providerId = await _members.activeSalonFor(accountId);
      if (providerId == null ||
          !await _members.can(accountId, providerId, Cap.catalogueManage)) {
        return (ok: false, error: 'forbidden', data: null);
      }
      prefixId = providerId;
      bucket = StorageBucket.public;
    }

    final key = '$purpose/$prefixId/${_objectId()}.$ext';
    final post = _storage.presignPost(
      key: key,
      contentType: contentType,
      maxBytes: _maxBytes,
      ttl: _ttl,
      bucket: bucket,
    );

    return (
      ok: true,
      error: null,
      data: {
        'method': 'POST',
        'uploadUrl': post.url,
        'fields': post.fields,
        'key': key,
        // Private objects (kyc/deposit) are never publicly served.
        if (bucket == StorageBucket.public)
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
