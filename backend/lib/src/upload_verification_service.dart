import 'storage/storage_service.dart';

/// The **authoritative** upload size check, run when a client claims an object.
///
/// Why it exists: the old presigned POST pinned a `content-length-range`, so
/// storage refused an oversized upload outright. Cloudflare R2 does not
/// implement presigned POST, and on a presigned PUT it **ignores a signed
/// `content-length`** — measured: a body 500 bytes larger than the signed value
/// was accepted with 200, while a mismatched `content-type` was correctly
/// rejected. So `UploadSigningService`'s cap is advisory, and this is the layer
/// that actually holds.
///
/// Without it, any authenticated client can PUT an object of arbitrary size
/// into a bucket we pay for. Design + threat model T61:
/// docs/design/backend-upload-size-verification.md.
class UploadVerificationService {
  UploadVerificationService({
    required StorageService storage,
    int maxBytes = 5 * 1024 * 1024,
  }) : _storage = storage,
       _maxBytes = maxBytes;

  final StorageService _storage;
  final int _maxBytes;

  /// Verify every key, deleting any that is too large.
  ///
  /// **Fails closed.** If storage cannot be reached the claim is refused with
  /// `storage_unavailable`, never accepted — otherwise the control is removable
  /// by anyone who can make one request fail.
  Future<({bool ok, String? error})> verify(
    List<String> keys, {
    required StorageBucket bucket,
  }) async {
    for (final key in keys) {
      final int? size;
      try {
        size = await _storage.objectSize(key: key, bucket: bucket);
      } catch (_) {
        return (ok: false, error: 'storage_unavailable');
      }

      // Absent is distinct from "could not tell" and is the client's problem:
      // it claimed a key it never uploaded.
      if (size == null) return (ok: false, error: 'upload_not_found');

      if (size > _maxBytes) {
        // Delete before returning. Refusing the claim while leaving the bytes
        // in the bucket would decline the booking AND still pay for storage —
        // exactly the outcome this class exists to prevent. Best-effort: a
        // failed delete must not turn a clean rejection into a 502.
        try {
          await _storage.deleteObject(key: key, bucket: bucket);
        } catch (_) {}
        return (ok: false, error: 'upload_too_large');
      }
    }
    return (ok: true, error: null);
  }

  /// [verify], then **promote** each key out of `pending/` to its final path.
  ///
  /// Returns the promoted keys in the same order, or an error. A claim records
  /// the promoted key, never the pending one — that is what leaves `pending/`
  /// containing only orphans.
  ///
  /// Promotion is copy-then-delete because S3/R2 has no rename. The delete is
  /// **best-effort**: if the copy succeeded the claim is valid, and failing it
  /// over a leftover pending object would reject a booking to save a few
  /// kilobytes the lifecycle rule collects anyway.
  Future<({bool ok, String? error, List<String> keys})> verifyAndPromote(
    List<String> keys, {
    required StorageBucket bucket,
  }) async {
    for (final k in keys) {
      if (promotedKey(k) == null) {
        // Not a pending key: either already claimed or attacker-chosen. Either
        // way the caller must not act on it.
        return (ok: false, error: 'invalid_input', keys: <String>[]);
      }
    }

    // verify() HEADs every object, which also PROVES each source is visible to
    // storage before the copy below. That ordering is load-bearing, not
    // incidental: R2's CopyObject intermittently 404s on a source written
    // milliseconds earlier, measured while building the live test. Reversing
    // these two steps would make fast claims fail with storage_unavailable.
    final v = await verify(keys, bucket: bucket);
    if (!v.ok) return (ok: false, error: v.error, keys: <String>[]);

    final promoted = <String>[];
    for (final k in keys) {
      final to = promotedKey(k)!;
      try {
        await _storage.copyObject(fromKey: k, toKey: to, bucket: bucket);
      } catch (_) {
        return (ok: false, error: 'storage_unavailable', keys: <String>[]);
      }
      try {
        await _storage.deleteObject(key: k, bucket: bucket);
      } catch (_) {}
      promoted.add(to);
    }
    return (ok: true, error: null, keys: promoted);
  }

  /// The object key behind a public delivery URL, or null if it is not one of
  /// ours.
  ///
  /// Public claims (review photos, gallery) carry URLs rather than keys. Those
  /// paths already reject any URL outside the configured origin allowlist, and
  /// **this must only ever be called on a URL that passed that check** — the
  /// prefix it strips is the very thing that check validates.
  String? keyFromPublicUrl(String url, {required String publicBaseUrl}) {
    final base = publicBaseUrl.endsWith('/')
        ? publicBaseUrl
        : '$publicBaseUrl/';
    if (!url.startsWith(base)) return null;
    final key = url.substring(base.length);
    return key.isEmpty ? null : key;
  }
}

/// Every signed upload key starts here until it is claimed.
///
/// The whole point: an object under this prefix has never been claimed, so a
/// lifecycle rule that expires the prefix cannot delete anything a user still
/// needs. Deleting by age *without* it would hit live galleries, retained KYC
/// evidence, and payment proof for open disputes —
/// docs/design/backend-upload-orphans.md §2.
const String kPendingPrefix = 'pending/';

/// The key an upload takes once claimed: the same path minus [kPendingPrefix].
///
/// Returns null when [key] is not a pending key, which the claim paths treat as
/// invalid input rather than silently accepting an arbitrary path.
///
/// **A `startsWith` prefix check is not an ownership check.** Every claim path
/// proves ownership by requiring a prefix — `pending/deposit/{userId}/`,
/// `pending/kyc/{accountId}/` — and `pending/deposit/{me}/../{you}/x.jpg`
/// satisfies that check *and* this one. Whether it then resolves to the other
/// tenant's object depends on whether R2 normalises dot segments in an object
/// key (S3 keys are opaque strings, so probably not) and on whether `Uri`
/// normalises the path before or after the SigV4 canonical request is built.
/// Both are empirical questions about someone else's implementation, and
/// neither was tested — which is the whole argument for closing this by
/// construction instead of by analysis. Rejecting empty, `.` and `..` segments
/// here covers every claim path at once, because this function is already the
/// single gate they all pass through.
///
/// An empty remainder (`pending/` alone) is refused for the same reason: it
/// used to promote to the empty string, which is not a key.
String? promotedKey(String key) {
  if (!key.startsWith(kPendingPrefix)) return null;
  final rest = key.substring(kPendingPrefix.length);
  if (rest.isEmpty) return null;
  for (final segment in rest.split('/')) {
    if (segment.isEmpty || segment == '.' || segment == '..') return null;
  }
  return rest;
}
