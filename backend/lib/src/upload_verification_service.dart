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

  /// The delivery origin public urls are built from, or null under a Fake.
  ///
  /// Read off the storage service rather than passed in again, so a caller that
  /// holds this service cannot end up validating urls against a DIFFERENT base
  /// than the one the objects are actually served from. `routes/me/index.dart`
  /// uses it: the avatar is written straight through `AuthRepository` with no
  /// service in between, so the route itself has to promote, and this keeps
  /// that to ONE thing it reads out of the context.
  String? get publicBaseUrl => _storage.publicBaseUrl;

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

  /// Promote the NEWLY-uploaded urls in [urls] and pass the unchanged ones
  /// through, returning the list to store — in the same order.
  ///
  /// ## The distinction nothing else modelled
  ///
  /// A save carries two kinds of url: ones the client just uploaded (still
  /// under `pending/`) and ones the server handed it on a previous read (long
  /// since promoted). [verifyAndPromote] rejects the second kind outright,
  /// which is correct for a claim and wrong for a save. Every surface that got
  /// this wrong got it wrong in one of exactly two ways:
  ///
  ///   · **never promote** — before/after pairs, avatars and artist images.
  ///     The object stays under `pending/`, and production expires that prefix
  ///     daily, so the image disappears a day after upload while its url sits
  ///     in Postgres pointing at nothing.
  ///   · **promote everything, every time** — the gallery, which re-sends its
  ///     existing urls on each save and is therefore refused from the second
  ///     save onward.
  ///
  /// Both are the same missing idea: *pending* and *already ours* are different
  /// states and need different handling.
  ///
  /// ## Why [alreadyStored] rather than "does it look promoted"
  ///
  /// A promoted key is just a key without the prefix — so "not pending" is
  /// indistinguishable from "arbitrary string the client made up". Treating
  /// that as trusted is precisely the hole the booking-time deposit field has
  /// (BACKEND.md §7). So an unchanged url must be **exactly one the caller
  /// already had**, matched against what is stored today. Membership, not shape.
  ///
  /// Anything that is neither pending nor already stored is refused. That is
  /// deny-by-default: a url we did not issue and do not hold has no legitimate
  /// way into this list.
  Future<({bool ok, String? error, List<String> urls})> promoteNewUrls(
    List<String> urls, {
    required String publicBaseUrl,
    required Set<String> alreadyStored,
    required StorageBucket bucket,
  }) async {
    final base = publicBaseUrl.endsWith('/')
        ? publicBaseUrl
        : '$publicBaseUrl/';

    // Partition, preserving order. `slot` records where each promoted key
    // belongs so the result can be reassembled exactly as submitted — the
    // caller's list order is meaningful (before/after pairs, gallery ordering).
    final result = List<String?>.filled(urls.length, null);
    final toPromote = <String>[];
    final slots = <int>[];

    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      if (alreadyStored.contains(url)) {
        result[i] = url; // unchanged, and provably ours
        continue;
      }
      final key = keyFromPublicUrl(url, publicBaseUrl: publicBaseUrl);
      if (key == null || promotedKey(key) == null) {
        // Not ours, or not pending and not previously stored.
        return (ok: false, error: 'invalid_input', urls: <String>[]);
      }
      toPromote.add(key);
      slots.add(i);
    }

    if (toPromote.isNotEmpty) {
      final v = await verifyAndPromote(toPromote, bucket: bucket);
      if (!v.ok) return (ok: false, error: v.error, urls: <String>[]);
      for (var j = 0; j < slots.length; j++) {
        result[slots[j]] = '$base${v.keys[j]}';
      }
    }
    return (ok: true, error: null, urls: result.cast<String>());
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
String? promotedKey(String key) => key.startsWith(kPendingPrefix)
    ? key.substring(kPendingPrefix.length)
    : null;
