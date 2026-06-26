import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A signed, single-use **multipart POST** upload (S3 POST Object). The client
/// POSTs `fields` + the file (last) to [url]; the signed policy pins the key,
/// content-type, and a size range, so storage rejects anything else.
class PresignedPost {
  const PresignedPost({required this.url, required this.fields});

  final String url;
  final Map<String, String> fields;
}

/// Object storage behind an interface so the upload-signing logic is testable
/// without a live bucket (Fake) and swappable across S3-compatible providers
/// (R2 today). Design: docs/design/pro-image-upload-pipeline.md.
abstract interface class StorageService {
  /// Build a presigned POST that allows uploading exactly [key] with
  /// [contentType] and at most [maxBytes] bytes, valid for [ttl].
  PresignedPost presignPost({
    required String key,
    required String contentType,
    required int maxBytes,
    Duration ttl,
  });

  /// The public (CDN) delivery URL for [key].
  String publicUrl(String key);
}

/// No-network stand-in for dev/CI/tests (selected when R2 isn't configured).
/// Deterministic and obviously-fake so it can never be mistaken for real
/// storage, while still exercising the full endpoint + app code paths.
class FakeStorageService implements StorageService {
  const FakeStorageService();

  static const origin = 'https://fake-storage.local';

  @override
  PresignedPost presignPost({
    required String key,
    required String contentType,
    required int maxBytes,
    Duration ttl = const Duration(minutes: 5),
  }) {
    return PresignedPost(
      url: '$origin/bucket',
      fields: {
        'key': key,
        'Content-Type': contentType,
        'x-amz-signature': 'fake',
        'x-amz-meta-max-bytes': '$maxBytes',
      },
    );
  }

  @override
  String publicUrl(String key) => '$origin/$key';
}

/// S3-compatible **presigned POST** signer (Cloudflare R2; also AWS S3 /
/// Supabase / MinIO). Implements AWS SigV4 POST-policy signing in-house with
/// `crypto` (HMAC-SHA256) — no heavy AWS SDK. Credentials come from env; this
/// class only signs, it never touches the network.
class R2StorageService implements StorageService {
  R2StorageService({
    required this.endpoint,
    required this.bucket,
    required String accessKeyId,
    required String secretAccessKey,
    required this.publicBaseUrl,
    this.region = 'auto',
    DateTime Function()? clock,
  }) : _accessKeyId = accessKeyId,
       _secretAccessKey = secretAccessKey,
       _clock = clock ?? DateTime.now;

  /// Storage API endpoint, e.g. `https://<account>.r2.cloudflarestorage.com`.
  final String endpoint;
  final String bucket;
  final String region;

  /// Public delivery base, e.g. `https://cdn.myweli.com` (a domain bound to the
  /// bucket). `publicUrl` = `$publicBaseUrl/$key`.
  final String publicBaseUrl;

  final String _accessKeyId;
  final String _secretAccessKey;
  final DateTime Function() _clock;

  @override
  PresignedPost presignPost({
    required String key,
    required String contentType,
    required int maxBytes,
    Duration ttl = const Duration(minutes: 5),
  }) {
    final now = _clock().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final credential = '$_accessKeyId/$dateStamp/$region/s3/aws4_request';
    final expiration = _iso8601(now.add(ttl));

    final policy = {
      'expiration': expiration,
      'conditions': [
        {'bucket': bucket},
        {'key': key},
        {'Content-Type': contentType},
        ['content-length-range', 0, maxBytes],
        {'x-amz-algorithm': 'AWS4-HMAC-SHA256'},
        {'x-amz-credential': credential},
        {'x-amz-date': amzDate},
      ],
    };
    final policyB64 = base64.encode(utf8.encode(jsonEncode(policy)));
    final signature = _sign(dateStamp, policyB64);

    return PresignedPost(
      url: '${_trim(endpoint)}/$bucket',
      fields: {
        'key': key,
        'Content-Type': contentType,
        'bucket': bucket,
        'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
        'X-Amz-Credential': credential,
        'X-Amz-Date': amzDate,
        'Policy': policyB64,
        'X-Amz-Signature': signature,
      },
    );
  }

  @override
  String publicUrl(String key) => '${_trim(publicBaseUrl)}/$key';

  /// SigV4 key-derivation chain, then HMAC the base64 policy → hex signature.
  String _sign(String dateStamp, String policyB64) {
    List<int> hmac(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;

    final kDate = hmac(utf8.encode('AWS4$_secretAccessKey'), dateStamp);
    final kRegion = hmac(kDate, region);
    final kService = hmac(kRegion, 's3');
    final kSigning = hmac(kService, 'aws4_request');
    return Hmac(sha256, kSigning).convert(utf8.encode(policyB64)).toString();
  }

  static String _trim(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// `yyyyMMddTHHmmssZ`.
  static String _amzDate(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}T'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';

  /// `yyyy-MM-ddTHH:mm:ss.000Z` (policy expiration).
  static String _iso8601(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}T'
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.000Z';
}
