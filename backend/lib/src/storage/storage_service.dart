import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// A signed, single-use **PUT**. The client PUTs the raw bytes to [url] with
/// exactly [headers] and nothing else.
///
/// **Not a bare URL, because the headers are load-bearing.** The signature
/// covers them, so sending a different `content-type` than the one signed is
/// `403 SignatureDoesNotMatch` — measured against real R2. The caller has to be
/// told what to send.
///
/// This replaced a presigned **POST** (S3 POST Object), which Cloudflare R2
/// answers with `501 NotImplemented` — every upload in the product was broken.
/// docs/design/backend-r2-presigned-put.md.
class PresignedUpload {
  const PresignedUpload({required this.url, required this.headers});

  final String url;

  /// Exactly the headers the signature pins. Lowercase names, as signed.
  final Map<String, String> headers;
}

/// Which bucket an object lives in. Each is physically separate so they can have
/// independent access scoping, lifecycle/retention, and blast-radius isolation:
/// `public` (gallery/review photos, CDN-served), `kyc` (identity/KYB docs —
/// retained), `deposit` (Mobile Money payment proofs — transient).
enum StorageBucket { public, kyc, deposit }

/// Object storage behind an interface so the upload-signing logic is testable
/// without a live bucket (Fake) and swappable across S3-compatible providers
/// (R2 today). Design: docs/design/pro-image-upload-pipeline.md.
abstract interface class StorageService {
  /// Build a presigned PUT that allows uploading exactly [key] with
  /// [contentType], valid for [ttl], into [bucket].
  ///
  /// **There is no size parameter, and that is deliberate.** The old POST
  /// policy carried a `content-length-range`; R2 ignores a signed
  /// `content-length` on a PUT — measured: a body 500 bytes larger than the
  /// signed value was accepted with 200. Signing it would look like enforcement
  /// and enforce nothing, so the cap lives in `UploadSigningService` instead
  /// (advisory) and, ultimately, in claim-time verification.
  PresignedUpload presignPut({
    required String key,
    required String contentType,
    Duration ttl,
    StorageBucket bucket,
  });

  /// The public (CDN) delivery URL for a public-bucket [key].
  String publicUrl(String key);

  /// The origin [publicUrl] builds on, or **null when there is no real public
  /// delivery** (the Fake).
  ///
  /// Exists so the gallery's origin allowlist can be derived from the storage
  /// actually in use instead of re-reading `R2_PUBLIC_BASE_URL` — see
  /// [galleryOriginsFor]. Two independent reads of one variable is two chances
  /// to disagree, and the one that disagrees silently is the security control.
  String? get publicBaseUrl;

  /// A short-lived **signed GET** URL for a [key] in a **private** [bucket]
  /// (KYC / deposit). The caller authorizes who may request it.
  String presignGet({
    required String key,
    required StorageBucket bucket,
    Duration ttl,
  });

  /// Short-lived signed **DELETE** URL for a private object — the erasure
  /// half of the lifecycle (T53: KYC docs go with the account). The caller
  /// executes the HTTP DELETE; signing only.
  String presignDelete({
    required String key,
    required StorageBucket bucket,
    Duration ttl,
  });

  /// Size of [key] in bytes, or **null when the object does not exist** —
  /// distinguishable from a zero-byte object, and treated as a rejection.
  ///
  /// **This method performs network I/O**, unlike everything above it. That is
  /// a deliberate change to this interface's character: R2 does not enforce a
  /// signed `content-length`, so the size cap can only be checked by asking
  /// storage what actually landed. A storage abstraction that cannot stat an
  /// object is not one. docs/design/backend-upload-size-verification.md.
  ///
  /// Throws on transport failure — callers must fail CLOSED rather than treat
  /// an error as "fine", or the control is removable by anyone who can make one
  /// request fail.
  Future<int?> objectSize({required String key, required StorageBucket bucket});

  /// Delete [key]. Used to remove an object rejected at claim time — refusing
  /// the claim while leaving the bytes in the bucket would decline the booking
  /// and still pay for the storage, which is the outcome being prevented.
  Future<void> deleteObject({
    required String key,
    required StorageBucket bucket,
  });

  /// Server-side copy within [bucket]. The bytes never travel through us.
  ///
  /// Exists for **promotion**: uploads land under `pending/` and move to their
  /// final key only when claimed, so anything still under `pending/` is by
  /// construction an orphan and can be expired by a lifecycle rule that cannot
  /// be wrong. docs/design/backend-upload-orphans.md.
  Future<void> copyObject({
    required String fromKey,
    required String toKey,
    required StorageBucket bucket,
  });
}

/// Which origins the gallery will accept an image URL from, derived from the
/// [storage] actually in use (anti-hotlink / anti-SSRF).
///
/// **Derived, not read.** `R2_PUBLIC_BASE_URL` used to be read three separate
/// times in the composition root: once inside storage's all-or-nothing
/// fail-fast, once here, and once as the key-derivation base. Only the first
/// participated in the guard, so the other two would happily carry a wrong or
/// absent value while every route still returned 200 — a security control that
/// is off and looks on.
///
/// `asset:` is the seed placeholder scheme, always allowed.
///
/// The `null` case is where the two environments part:
///
///   · **dev** → empty, meaning *accept anything*. Local work needs to paste an
///     arbitrary image URL, and always has.
///   · **guarded** (`STORAGE_PROVIDER=disabled` in staging) → the Fake's own
///     origin plus `asset:`, so the fake upload flow still round-trips while
///     switching storage off cannot silently widen what the gallery accepts.
///     Turning a subsystem off must never turn a check off with it.
List<String> galleryOriginsFor(
  StorageService storage, {
  required bool guardsOn,
}) {
  final base = storage.publicBaseUrl;
  if (base != null) return <String>[base, 'asset:'];
  if (guardsOn) return const <String>[FakeStorageService.origin, 'asset:'];
  return const <String>[];
}

/// No-network stand-in for dev/CI/tests (selected when R2 isn't configured).
/// Deterministic and obviously-fake so it can never be mistaken for real
/// storage, while still exercising the full endpoint + app code paths.
class FakeStorageService implements StorageService {
  FakeStorageService({
    this.defaultSize = 1024,
    Map<String, int>? sizes,
    Set<String>? missing,
  }) : sizes = sizes ?? {},
       missing = missing ?? {};

  static const origin = 'https://fake-storage.local';

  /// Size reported for any key not in [sizes] or [missing].
  final int defaultSize;

  /// Per-key sizes, so a test can make one object oversized.
  final Map<String, int> sizes;

  /// Keys reported as absent (objectSize → null).
  final Set<String> missing;

  /// Keys passed to [deleteObject] — asserted on, so "the offending object was
  /// deleted" is proven rather than assumed.
  final List<String> deleted = [];

  /// `from -> to` pairs passed to [copyObject], so promotion is provable.
  final List<String> copied = [];

  @override
  PresignedUpload presignPut({
    required String key,
    required String contentType,
    Duration ttl = const Duration(minutes: 5),
    StorageBucket bucket = StorageBucket.public,
  }) {
    // Mirrors presignGet/presignDelete: the OBJECT path, so the fake exercises
    // the same client code path as R2 rather than a shape only it accepts.
    return PresignedUpload(
      url: '$origin/${bucket.name}/$key?sig=fake-put',
      headers: {'content-type': contentType},
    );
  }

  @override
  String presignGet({
    required String key,
    required StorageBucket bucket,
    Duration ttl = const Duration(minutes: 5),
  }) => '$origin/${bucket.name}/$key?sig=fake';

  @override
  String presignDelete({
    required String key,
    required StorageBucket bucket,
    Duration ttl = const Duration(minutes: 5),
  }) => '$origin/${bucket.name}/$key?sig=fake-delete';

  @override
  String publicUrl(String key) => '$origin/$key';

  /// **Null, not [origin].** There is no real delivery domain here, and the
  /// gallery allowlist keys off exactly that distinction: null means "no public
  /// origin to pin to", which is what dev has always meant.
  @override
  String? get publicBaseUrl => null;

  @override
  Future<int?> objectSize({
    required String key,
    required StorageBucket bucket,
  }) async => sizes[key] ?? (missing.contains(key) ? null : defaultSize);

  @override
  Future<void> deleteObject({
    required String key,
    required StorageBucket bucket,
  }) async => deleted.add(key);

  @override
  Future<void> copyObject({
    required String fromKey,
    required String toKey,
    required StorageBucket bucket,
  }) async {
    copied.add('$fromKey -> $toKey');
    // Carry the size across so a promoted object still stats correctly.
    final n = sizes[fromKey];
    if (n != null) sizes[toKey] = n;
  }
}

/// S3-compatible **presigned URL** signer (Cloudflare R2; also AWS S3 /
/// Supabase / MinIO). Implements AWS SigV4 query-string signing in-house with
/// `crypto` (HMAC-SHA256) — no heavy AWS SDK. Credentials come from env; this
/// class only signs, it never touches the network.
class R2StorageService implements StorageService {
  R2StorageService({
    required this.endpoint,
    required this.bucket,
    required String accessKeyId,
    required String secretAccessKey,
    required this.publicBaseUrl,
    String? kycBucket,
    String? depositBucket,
    this.region = 'auto',
    DateTime Function()? clock,
    http.Client? client,
  }) : _accessKeyId = accessKeyId,
       _secretAccessKey = secretAccessKey,
       _client = client ?? http.Client(),
       _kycBucket = kycBucket ?? bucket,
       _depositBucket = depositBucket ?? bucket,
       _clock = clock ?? DateTime.now;

  /// Storage API endpoint, e.g. `https://<account>.r2.cloudflarestorage.com`.
  final String endpoint;
  final String bucket;

  /// Separate **private** bucket for KYC documents (never publicly served).
  final String _kycBucket;

  /// Separate **private** bucket for deposit screenshots (never public).
  final String _depositBucket;
  final String region;

  String _bucketFor(StorageBucket b) => switch (b) {
    StorageBucket.public => bucket,
    StorageBucket.kyc => _kycBucket,
    StorageBucket.deposit => _depositBucket,
  };

  /// Public delivery base, e.g. `https://cdn.myweli.com` (a domain bound to the
  /// bucket). `publicUrl` = `$publicBaseUrl/$key`. Non-null here — R2 always has
  /// one — which satisfies the interface's nullable getter.
  @override
  final String publicBaseUrl;

  final String _accessKeyId;
  final String _secretAccessKey;
  final DateTime Function() _clock;

  /// Injected so claim-time verification is testable without a bucket, the
  /// same shape `ResendEmailProvider` uses.
  final http.Client _client;

  @override
  PresignedUpload presignPut({
    required String key,
    required String contentType,
    Duration ttl = const Duration(minutes: 5),
    StorageBucket bucket = StorageBucket.public,
  }) {
    // Reuses the SAME signer that has served GET and DELETE in production
    // since the KYC work, rather than growing a second signing path. The
    // target is the OBJECT path — the old POST signed the bucket ROOT, which
    // is right for POST (the key rides in the form) and wrong for PUT.
    final headers = {'content-type': contentType};
    return PresignedUpload(
      url: _presignUrl(
        method: 'PUT',
        key: key,
        bucket: bucket,
        ttl: ttl,
        signedHeaders: headers,
      ),
      headers: headers,
    );
  }

  @override
  String publicUrl(String key) => '${_trim(publicBaseUrl)}/$key';

  @override
  Future<int?> objectSize({
    required String key,
    required StorageBucket bucket,
  }) async {
    // Signed for HEAD, because SigV4 covers the HTTP METHOD: a URL signed for
    // GET and sent as HEAD is a signature mismatch, and R2 answers 403.
    //
    // It shipped that way — presignGet(...) here — and the live R2 test caught
    // it. The failure mode was not a missing size check but a TOTAL upload
    // outage: objectSize threw, verify() failed closed, and every claim
    // (deposit, KYC, review, gallery) was refused with storage_unavailable.
    final res = await _client.head(
      Uri.parse(
        _presignUrl(method: 'HEAD', key: key, bucket: bucket, ttl: _ioTtl),
      ),
      // `identity` because Cloudflare COMPRESSES compressible content types and
      // then omits content-length entirely. Measured: a 51-byte text/plain
      // object came back `200, content-encoding: gzip` with NO content-length,
      // while an image/jpeg of the same size was fine — which is exactly why
      // the live test, which uploads a JPEG, never saw this.
      headers: const {'accept-encoding': 'identity'},
    );
    if (res.statusCode == 404) {
      // MEASURED: R2 can answer 404 for an object written moments earlier.
      // Left unhandled that is a production bug, not a test flake — a client
      // that claims straight after uploading gets upload_not_found and its
      // legitimate claim is refused.
      //
      // Bounded retry: ~2s total. 900ms was NOT enough — measured, the window
      // exceeded it repeatedly. A claim in the wild also crosses a client round
      // trip, so this budget is a worst case rather than the norm; two seconds
      // of latency on a claim beats rejecting a valid one.
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final again = await _client.head(
          Uri.parse(
            _presignUrl(method: 'HEAD', key: key, bucket: bucket, ttl: _ioTtl),
          ),
          headers: const {'accept-encoding': 'identity'},
        );
        if (again.statusCode == 404) continue;
        if (again.statusCode >= 400) {
          throw StateError('objectSize failed: HTTP ${again.statusCode}');
        }
        final n = int.tryParse(again.headers['content-length'] ?? '');
        if (n != null) return n;
      }
      return null;
    }
    if (res.statusCode >= 400) {
      // Deliberately an exception, not a null: "absent" and "could not tell"
      // must not collapse into the same value, because they demand different
      // answers (reject the claim vs. 502 and retry).
      throw StateError('objectSize failed: HTTP ${res.statusCode}');
    }
    final size = int.tryParse(res.headers['content-length'] ?? '');
    if (size == null) {
      // A 200 with no usable length is "could not tell", NOT "absent".
      // Returning null here is what made the gzip case silent: it read as
      // upload_not_found and refused a claim for an object that was really
      // there. Throwing makes it fail closed AND loud.
      throw StateError(
        'objectSize: HTTP 200 but no usable content-length '
        '(content-encoding: ${res.headers['content-encoding'] ?? 'none'})',
      );
    }
    return size;
  }

  @override
  Future<void> deleteObject({
    required String key,
    required StorageBucket bucket,
  }) async {
    final res = await _client.delete(
      Uri.parse(presignDelete(key: key, bucket: bucket, ttl: _ioTtl)),
    );
    // 204 on success, 404 if it was already gone — both are the desired end
    // state, so neither is an error.
    if (res.statusCode >= 400 && res.statusCode != 404) {
      throw StateError('deleteObject failed: HTTP ${res.statusCode}');
    }
  }

  @override
  Future<void> copyObject({
    required String fromKey,
    required String toKey,
    required StorageBucket bucket,
  }) async {
    // S3 CopyObject: PUT the DESTINATION carrying x-amz-copy-source. The header
    // is part of the signature, so it goes through signedHeaders — the same
    // mechanism that pins content-type on an upload, and the reason
    // _presignUrl grew that parameter.
    final source =
        '/${[_bucketFor(bucket), ...fromKey.split('/')].map(_uriEncode).join('/')}';
    final headers = {'x-amz-copy-source': source};
    final res = await _client.put(
      Uri.parse(
        _presignUrl(
          method: 'PUT',
          key: toKey,
          bucket: bucket,
          ttl: _ioTtl,
          signedHeaders: headers,
        ),
      ),
      headers: headers,
    );
    if (res.statusCode >= 400) {
      throw StateError('copyObject failed: HTTP ${res.statusCode}');
    }
  }

  static const _ioTtl = Duration(minutes: 1);

  @override
  String presignGet({
    required String key,
    required StorageBucket bucket,
    Duration ttl = const Duration(minutes: 5),
  }) => _presignUrl(method: 'GET', key: key, bucket: bucket, ttl: ttl);

  @override
  String presignDelete({
    required String key,
    required StorageBucket bucket,
    Duration ttl = const Duration(minutes: 5),
  }) => _presignUrl(method: 'DELETE', key: key, bucket: bucket, ttl: ttl);

  /// SigV4 query-signed URL for [method] on a private object.
  /// SigV4 query-string signing for GET / PUT / DELETE.
  ///
  /// [signedHeaders] are lowercase names covered by the signature, in addition
  /// to the always-present `host`. GET and DELETE pass none and produce
  /// byte-identical URLs to before this parameter existed — which is what their
  /// untouched tests prove.
  String _presignUrl({
    required String method,
    required String key,
    required StorageBucket bucket,
    required Duration ttl,
    Map<String, String> signedHeaders = const {},
  }) {
    final now = _clock().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final credential = '$_accessKeyId/$dateStamp/$region/s3/aws4_request';
    final host = Uri.parse(endpoint).host;
    // Path-style, on the target private bucket; each segment URI-encoded.
    final canonicalUri =
        '/${[_bucketFor(bucket), ...key.split('/')].map(_uriEncode).join('/')}';

    // One sorted map drives all three places SigV4 needs the header set:
    // the canonical headers block, the signed-headers list in the canonical
    // request, and the X-Amz-SignedHeaders query parameter. They were three
    // hardcoded 'host' literals; a mismatch between any two is a 403 that only
    // appears at upload time.
    final allHeaders = <String, String>{'host': host, ...signedHeaders};
    final headerNames = allHeaders.keys.toList()..sort();
    final canonicalHeaders = headerNames
        .map<String>((n) => '$n:${allHeaders[n]}\n')
        .join();
    final signedHeaderList = headerNames.join(';');

    final query = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': credential,
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': '${ttl.inSeconds}',
      'X-Amz-SignedHeaders': signedHeaderList,
    };
    final canonicalQuery = (query.keys.toList()..sort())
        .map((k) => '${_uriEncode(k)}=${_uriEncode(query[k]!)}')
        .join('&');

    final canonicalRequest = [
      method,
      canonicalUri,
      canonicalQuery,
      canonicalHeaders,
      signedHeaderList,
      'UNSIGNED-PAYLOAD',
    ].join('\n');
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      '$dateStamp/$region/s3/aws4_request',
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    final signature = _hmacHex(_signingKey(dateStamp), stringToSign);

    return '${_trim(endpoint)}$canonicalUri?$canonicalQuery'
        '&X-Amz-Signature=$signature';
  }

  /// Percent-encode per RFC 3986 (SigV4 canonicalisation) — Dart's
  /// Uri.encodeComponent leaves some reserved characters alone.
  static String _uriEncode(String s) {
    const unreserved =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';
    final out = StringBuffer();
    for (final byte in utf8.encode(s)) {
      final ch = String.fromCharCode(byte);
      if (unreserved.contains(ch)) {
        out.write(ch);
      } else {
        out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  /// SigV4 key-derivation chain → the signing key for [dateStamp].
  List<int> _signingKey(String dateStamp) {
    List<int> hmac(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    final kDate = hmac(utf8.encode('AWS4$_secretAccessKey'), dateStamp);
    final kRegion = hmac(kDate, region);
    final kService = hmac(kRegion, 's3');
    return hmac(kService, 'aws4_request');
  }

  String _hmacHex(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).toString();

  static String _trim(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// `yyyyMMddTHHmmssZ`.
  static String _amzDate(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}T'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';
}
