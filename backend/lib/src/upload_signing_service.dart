import 'dart:convert';
import 'dart:math';

import 'access/capabilities.dart';
import 'access/membership_service.dart';
import 'auth/provider_auth_repository.dart';
import 'security/identity_limits.dart';
import 'security/rate_limiter.dart';
import 'storage/storage_service.dart';
import 'upload_verification_service.dart';

/// Outcome of a sign request; [data] is the response body on success.
typedef SignResult = ({bool ok, String? error, Map<String, dynamic>? data});

/// Issues a presigned upload for an authenticated salon. The object **key is
/// built server-side from the token**, so a salon can only write under its own
/// prefix — the client never chooses the path. Content-type is allowlisted and
/// the size cap is advisory until claim-time verification lands; bytes never pass through the API.
/// Five purposes — the header said "two" for three purposes' worth of drift.
/// Designs: pro-image-upload-pipeline.md, pro-kyc.md, consumer-deposit.md,
/// reviews-photos-reporting.md, consumer-avatar-upload.md.
///
/// PROVIDER token:
/// - `gallery` → **public** bucket, prefix `gallery/{providerId}` (needs a
///   linked salon), returns a `publicUrl`.
/// - `kyc` → **private** bucket, prefix `kyc/{accountId}`, returns the `key`
///   only (no public URL — ID documents are never public); accepts PDF too.
///
/// CONSUMER token:
/// - `deposit` → **private** bucket, prefix `deposit/{userId}`, key only.
/// - `review` → **public** bucket, prefix `review/{userId}`.
/// - `avatar` → **public** bucket, prefix `avatar/{userId}`.
///
/// **The purpose string IS the storage namespace** — it is interpolated into
/// the key and promotion only strips `pending/`. So a purpose is not a label:
/// it is the prefix that erasure, moderation and any future lifecycle rule will
/// reason about, forever. That is why the avatar got its own rather than
/// borrowing `review`'s, which would have been free in code and wrong in data
/// (docs/design/consumer-avatar-upload.md §3).
class UploadSigningService {
  UploadSigningService(
    this._providerAuth,
    this._members,
    this._storage, {
    RateLimiter? limiter,
    IdentityLimits limits = kDefaultIdentityLimits,
  }) : _limiter = limiter,
       _limits = limits;

  /// Per-identity rate limit (T65). Null means no limit; the composition root
  /// always supplies one, and a source test proves it.
  ///
  /// **This is the cheapest of the three surfaces to abuse** — no database
  /// write, no repository, just a presign — and therefore the only one with no
  /// persistent trace of the attempt to count afterwards. The signing-time size
  /// cap is advisory (R2 ignores a signed content-length), so the real check is
  /// at claim time and an attacker who never claims never reaches it.
  final RateLimiter? _limiter;
  final IdentityLimits _limits;

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
    String? salonId,
  }) async {
    final isKyc = purpose == 'kyc';
    final isDeposit = purpose == 'deposit';
    final isGallery = purpose == 'gallery';
    // Consumer review photos (P2b, audit 2.13): public like gallery, but
    // scoped to the USER token — review/{userId}.
    final isReview = purpose == 'review';
    // Consumer profile photo — same shape as a review photo, its OWN prefix.
    final isAvatar = purpose == 'avatar';
    if (!isGallery && !isKyc && !isDeposit && !isReview && !isAvatar) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    // KYC accepts PDF; gallery + deposit (screenshots) are images only.
    final ext = (isKyc ? _kycTypes : _imageTypes)[contentType];
    if (contentType is! String || ext == null) {
      return (ok: false, error: 'invalid_input', data: null);
    }

    // **Here, and not one line earlier.** `purpose` arrives from the client and
    // is only known to be one of five literals AFTER the check above. Keying a
    // rate limit on the raw value would let an attacker send a fresh random
    // purpose per request: unbounded buckets, so the limit evaporates — and
    // every miss writes a NEW ROW, turning the limiter into the amplifier they
    // wanted. A rate-limit key may only be built from a closed set, which is
    // the whole reason this check lives in the service rather than the route.
    //
    // Keyed on the token's `sub`, never the derived salon id: that would make
    // one colleague's portfolio upload refuse another's.
    // docs/design/backend-identity-rate-limits.md §4.
    final validPurpose = purpose! as String;
    if (!await allowUnderLimit(
      _limiter,
      signBucket(validPurpose, accountId),
      signLimitFor(validPurpose, _limits),
    )) {
      return (ok: false, error: 'rate_limited', data: null);
    }

    // Prefix + target bucket per purpose. Deposit is a CONSUMER upload scoped
    // to the user id (no provider account); kyc → the provider account; gallery
    // → the linked salon (public).
    final String prefixId;
    final StorageBucket bucket;
    if (isDeposit) {
      prefixId = accountId;
      bucket = StorageBucket.deposit;
    } else if (isReview || isAvatar) {
      // Public (review tiles and profile photos both render), under the
      // caller's own prefix. They share this branch and NOT their key prefix:
      // `purpose` is interpolated below, so they land in separate namespaces —
      // which is the whole point (docs/design/consumer-avatar-upload.md §3).
      prefixId = accountId;
      bucket = StorageBucket.public;
    } else if (isKyc) {
      if (await _providerAuth.accountById(accountId) == null) {
        return (ok: false, error: 'forbidden', data: null);
      }
      prefixId = accountId;
      bucket = StorageBucket.kyc;
    } else {
      // Module `access` R1: gallery uploads need catalogue.manage inside
      // the caller's acting salon; R6: `?salonId=` selects among ACTIVE
      // memberships (T55).
      final providerId = await _members.salonForRequest(
        accountId,
        salonId: salonId,
      );
      if (providerId == null ||
          !await _members.can(accountId, providerId, Cap.catalogueManage)) {
        return (ok: false, error: 'forbidden', data: null);
      }
      prefixId = providerId;
      bucket = StorageBucket.public;
    }

    // Uploads land under `pending/` and are PROMOTED to the final key only when
    // claimed. Anything still under this prefix is by construction an orphan —
    // which is what makes a lifecycle rule on it impossible to get wrong.
    // Claim-time size verification cannot see an unclaimed object, so without
    // this the cap simply does not apply to them.
    // docs/design/backend-upload-orphans.md.
    final key = '$kPendingPrefix$purpose/$prefixId/${_objectId()}.$ext';
    final upload = _storage.presignPut(
      key: key,
      contentType: contentType,
      ttl: _ttl,
      bucket: bucket,
    );

    return (
      ok: true,
      error: null,
      data: {
        'method': 'PUT',
        'uploadUrl': upload.url,
        // Exactly the headers the signature pins — sending anything else is a
        // 403 from storage, so this is a requirement, not a hint.
        'headers': upload.headers,
        'key': key,
        // Private objects (kyc/deposit) are never publicly served.
        if (bucket == StorageBucket.public)
          'publicUrl': _storage.publicUrl(key),
        // ADVISORY. The old POST policy pinned a content-length-range that
        // storage enforced; R2 ignores a signed content-length on a PUT
        // (measured). Real enforcement has to happen when the object is
        // claimed — docs/design/backend-r2-presigned-put.md §3.
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
