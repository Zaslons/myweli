@Tags(['r2'])
library;

import 'dart:io';

import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

/// **Does real storage accept the shape we produce?**
///
/// This is the test that did not exist when it mattered. The signer produced an
/// S3 presigned POST; Cloudflare R2 answers those with `501 NotImplemented`, so
/// **every upload in the product was broken** — deposit screenshots, review
/// photos, galleries, KYC. The full backend suite and a 47-assertion funnel gate
/// were green throughout, because every one of them asserted the shape of *our
/// own output*. A test that only checks what we emit cannot detect that the
/// counterparty refuses it.
///
/// So this one talks to real R2. It self-gates on credentials and skips
/// everywhere they are absent — CI included — but it exists, and running it is
/// the difference between "we think this works" and "we watched it work".
///
///   R2_ACCOUNT_ID=… R2_ACCESS_KEY_ID=… R2_SECRET_ACCESS_KEY=… \
///   R2_BUCKET=… R2_PUBLIC_BASE_URL=… dart test test/storage/r2_live_test.dart
///
/// Design: docs/design/backend-r2-presigned-put.md §6.
void main() {
  final env = Platform.environment;
  final account = env['R2_ACCOUNT_ID'];
  final keyId = env['R2_ACCESS_KEY_ID'];
  final secret = env['R2_SECRET_ACCESS_KEY'];
  final bucket = env['R2_BUCKET'];

  if ([account, keyId, secret, bucket].any((v) => v == null || v.isEmpty)) {
    group(
      'R2 live (skipped — set R2_ACCOUNT_ID/ACCESS_KEY_ID/SECRET_ACCESS_KEY/BUCKET)',
      () => test('needs credentials', () {}),
      skip: 'requires real R2 credentials',
    );
    return;
  }

  // The production class, built exactly as the composition root builds it —
  // testing a bespoke signer here would prove nothing about what ships.
  final r2 = R2StorageService(
    endpoint: 'https://$account.r2.cloudflarestorage.com',
    bucket: bucket!,
    accessKeyId: keyId!,
    secretAccessKey: secret!,
    publicBaseUrl: env['R2_PUBLIC_BASE_URL'] ?? 'https://example.invalid',
  );

  // A tiny real JPEG. Keyed under `livetest/` so anything this leaves behind is
  // identifiable and purgeable by prefix.
  final bytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 0x78)];
  final key = 'livetest/${DateTime.now().microsecondsSinceEpoch}.jpg';
  final client = HttpClient();

  tearDownAll(() async {
    // Best-effort: a failed assertion must not leave the object behind, and a
    // failed cleanup must not mask the assertion that actually failed.
    try {
      final req = await client.deleteUrl(
        Uri.parse(r2.presignDelete(key: key, bucket: StorageBucket.public)),
      );
      await (await req.close()).drain<void>();
    } catch (_) {}
    client.close();
  });

  test('a presigned PUT is a shape R2 actually accepts', () async {
    // THE regression guard. If this ever returns 501 NotImplemented, the signer
    // has drifted back to a presigned POST and every upload is broken again.
    final upload = r2.presignPut(
      key: key,
      contentType: 'image/jpeg',
      bucket: StorageBucket.public,
    );

    final req = await client.putUrl(Uri.parse(upload.url));
    upload.headers.forEach(req.headers.set);
    req.add(bytes);
    final res = await req.close();
    await res.drain<void>();

    expect(
      res.statusCode,
      anyOf(200, 204),
      reason:
          '501 here means the signer went back to presigned POST, which R2 '
          'does not implement; 403 means the signed headers and the sent '
          'headers disagree',
    );
  });

  test('the signature really pins content-type', () async {
    // The control that makes the size finding trustworthy. If sending a
    // different content-type than the one signed were ACCEPTED, the signed
    // headers would be decoration and `PresignedUpload.headers` would be a
    // lie. It must be refused.
    final upload = r2.presignPut(
      key: '$key.control',
      contentType: 'image/jpeg',
      bucket: StorageBucket.public,
    );

    final req = await client.putUrl(Uri.parse(upload.url));
    req.headers.set('content-type', 'text/html'); // NOT what was signed
    req.add(bytes);
    final res = await req.close();
    await res.drain<void>();

    expect(
      res.statusCode,
      403,
      reason: 'a content-type other than the signed one must not be accepted',
    );
  });

  test('objectSize reports the real size, and delete removes it', () async {
    // The claim-time cap (T61) rests on objectSize being truthful against real
    // storage, not just against the fake.
    final upload = r2.presignPut(
      key: '$key.size',
      contentType: 'image/jpeg',
      bucket: StorageBucket.public,
    );
    final put = await client.putUrl(Uri.parse(upload.url));
    upload.headers.forEach(put.headers.set);
    put.add(bytes);
    await (await put.close()).drain<void>();

    expect(
      await r2.objectSize(key: '$key.size', bucket: StorageBucket.public),
      bytes.length,
    );

    await r2.deleteObject(key: '$key.size', bucket: StorageBucket.public);
    expect(
      await r2.objectSize(key: '$key.size', bucket: StorageBucket.public),
      isNull,
      reason: 'a deleted object must read as absent, not as zero bytes',
    );
  });
}
