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
    // EVERY key this file can create, not just the happy-path one. The first
    // version deleted only `key`, so when the objectSize test failed its
    // `$key.size` object survived — two of them were still sitting in the
    // bucket afterwards. A test that leaves orphans while orphans are the
    // problem under discussion is not a good test.
    //
    // Best-effort throughout: a failed assertion must not leave residue, and a
    // failed cleanup must not mask the assertion that actually failed.
    for (final k in [
      key,
      '\$key.size',
      '\$key.control',
      '\$key.pending',
      '\$key.promoted',
      '\$key.text',
    ]) {
      try {
        final req = await client.deleteUrl(
          Uri.parse(r2.presignDelete(key: k, bucket: StorageBucket.public)),
        );
        await (await req.close()).drain<void>();
      } catch (_) {}
    }
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

  test('copyObject promotes an object server-side', () async {
    // The promotion primitive, against real R2 — it had never run there. S3
    // CopyObject signs x-amz-copy-source as a SIGNED HEADER, the same mechanism
    // that pins content-type, so a signing mistake here is a 403 that only real
    // storage can show.
    final from = '$key.pending';
    final to = '$key.promoted';
    final up = r2.presignPut(
      key: from,
      contentType: 'image/jpeg',
      bucket: StorageBucket.public,
    );
    final put = await client.putUrl(Uri.parse(up.url));
    up.headers.forEach(put.headers.set);
    put.add(bytes);
    final putRes = await put.close();
    await putRes.drain<void>();
    // Assert the WRITE, not just the read. Twice now a missing status check
    // sent me chasing a read bug that was really a failed write.
    expect(putRes.statusCode, anyOf(200, 204), reason: 'the source must exist');

    // Confirm the source is VISIBLE before copying. Not ceremony: R2's
    // CopyObject intermittently answers 404 for a source written milliseconds
    // earlier, and this test reproduced that ~3 runs in 4.
    //
    // Production never hits it, because verifyAndPromote runs verify() —
    // which HEADs the object — before promoting, so the object is proven
    // visible first. Copying straight after a PUT is something only this test
    // did, so the test is what was wrong, not the code.
    expect(
      await r2.objectSize(key: from, bucket: StorageBucket.public),
      bytes.length,
      reason: 'the source must be visible before CopyObject can see it',
    );

    await r2.copyObject(fromKey: from, toKey: to, bucket: StorageBucket.public);
    expect(
      await r2.objectSize(key: to, bucket: StorageBucket.public),
      bytes.length,
      reason: 'the promoted object must exist with the same bytes',
    );

    await r2.deleteObject(key: from, bucket: StorageBucket.public);
    expect(
      await r2.objectSize(key: from, bucket: StorageBucket.public),
      isNull,
      reason:
          'and the pending original must be gone, or pending/ still fills up',
    );
    await r2.deleteObject(key: to, bucket: StorageBucket.public);
  });

  test('objectSize survives a COMPRESSIBLE object', () async {
    // The regression this file previously could not see. Every other test here
    // uploads image/jpeg, which Cloudflare does not compress. A text/plain
    // object comes back `200, content-encoding: gzip` with NO content-length —
    // and objectSize used to read that as null, i.e. "absent", which
    // UploadVerificationService turns into upload_not_found and a REFUSED
    // claim for an object that is really there.
    final k = '$key.text';
    final up = r2.presignPut(
      key: k,
      contentType: 'text/plain',
      bucket: StorageBucket.public,
    );
    final put = await client.putUrl(Uri.parse(up.url));
    up.headers.forEach(put.headers.set);
    final text = List.filled(51, 0x78);
    put.add(text);
    await (await put.close()).drain<void>();

    expect(
      await r2.objectSize(key: k, bucket: StorageBucket.public),
      text.length,
      reason: 'a compressible object must report its TRUE stored size',
    );
    await r2.deleteObject(key: k, bucket: StorageBucket.public);
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
