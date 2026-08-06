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
