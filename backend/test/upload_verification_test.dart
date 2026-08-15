import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:myweli_backend/src/upload_verification_service.dart';
import 'package:test/test.dart';

/// The authoritative upload size cap (T61).
///
/// R2 ignores a signed `content-length` on a presigned PUT — measured against
/// the live bucket — so `UploadSigningService`'s limit is advisory and THIS is
/// the layer that holds. Written negative-first: a bug here is a
/// denial-of-wallet, not a broken feature.
///
/// Design: docs/design/backend-upload-size-verification.md.
void main() {
  const max = 1000;

  UploadVerificationService svc(StorageService s) =>
      UploadVerificationService(storage: s, maxBytes: max);

  group('rejections', () {
    test('an oversized object is refused AND deleted', () {
      // The delete is asserted, not assumed. Refusing the claim while leaving
      // the bytes in the bucket would decline the booking and still pay for
      // the storage — the exact outcome this class prevents.
      final store = FakeStorageService(sizes: {'deposit/u1/big.jpg': max + 1});
      return svc(
        store,
      ).verify(['deposit/u1/big.jpg'], bucket: StorageBucket.deposit).then((r) {
        expect(r.ok, isFalse);
        expect(r.error, 'upload_too_large');
        expect(
          store.deleted,
          ['deposit/u1/big.jpg'],
          reason: 'the offending object must not survive the rejection',
        );
      });
    });

    test('a claimed-but-absent object is refused', () async {
      final store = FakeStorageService(missing: {'deposit/u1/ghost.jpg'});
      final r = await svc(
        store,
      ).verify(['deposit/u1/ghost.jpg'], bucket: StorageBucket.deposit);
      expect(r.ok, isFalse);
      expect(
        r.error,
        'upload_not_found',
        reason: 'absent must not collapse into the same answer as too-large',
      );
    });

    test('FAILS CLOSED when storage cannot be reached', () async {
      // The test that matters if this is ever "simplified". Accepting on error
      // makes the whole control removable by anyone who can make one request
      // fail — so an unreachable bucket must refuse, not wave through.
      final r = await svc(
        _ThrowingStorage(),
      ).verify(['deposit/u1/x.jpg'], bucket: StorageBucket.deposit);
      expect(r.ok, isFalse);
      expect(r.error, 'storage_unavailable');
    });

    test('one bad key in a list refuses the whole claim', () async {
      final store = FakeStorageService(
        sizes: {'a.jpg': 10, 'b.jpg': max + 1, 'c.jpg': 10},
      );
      final r = await svc(
        store,
      ).verify(['a.jpg', 'b.jpg', 'c.jpg'], bucket: StorageBucket.public);
      expect(r.ok, isFalse);
      expect(r.error, 'upload_too_large');
      expect(store.deleted, contains('b.jpg'));
    });
  });

  group('the boundary', () {
    test('exactly maxBytes passes; one more byte fails', () async {
      final at = FakeStorageService(sizes: {'k': max});
      expect(
        (await svc(at).verify(['k'], bucket: StorageBucket.public)).ok,
        isTrue,
      );

      final over = FakeStorageService(sizes: {'k': max + 1});
      expect(
        (await svc(over).verify(['k'], bucket: StorageBucket.public)).ok,
        isFalse,
        reason: 'the cap is inclusive — off-by-one here is a real limit change',
      );
    });

    test('an empty key list passes without touching storage', () async {
      // Claims with no attachments are the common case; they must not be
      // penalised, and must not perform a pointless round-trip.
      final store = FakeStorageService();
      final r = await svc(store).verify([], bucket: StorageBucket.public);
      expect(r.ok, isTrue);
      expect(store.deleted, isEmpty);
    });
  });

  group('keyFromPublicUrl — public claims carry URLs, not keys', () {
    final s = svc(FakeStorageService());
    const base = 'https://cdn.myweli.com';

    test('strips the configured base', () {
      expect(
        s.keyFromPublicUrl('$base/gallery/p1/a.jpg', publicBaseUrl: base),
        'gallery/p1/a.jpg',
      );
      expect(
        s.keyFromPublicUrl('$base/gallery/p1/a.jpg', publicBaseUrl: '$base/'),
        'gallery/p1/a.jpg',
        reason: 'a trailing slash on the base must not change the key',
      );
    });

    test('refuses a foreign origin and a bare base', () {
      // Defence in depth: the calling paths already enforce the origin
      // allowlist, and this must not become the only thing standing between a
      // foreign URL and a key we would then act on.
      expect(
        s.keyFromPublicUrl(
          'https://evil.example/gallery/a.jpg',
          publicBaseUrl: base,
        ),
        isNull,
      );
      expect(s.keyFromPublicUrl(base, publicBaseUrl: base), isNull);
      expect(s.keyFromPublicUrl('$base/', publicBaseUrl: base), isNull);
    });
  });

  group('verifyAndPromote — what makes pending/ mean "orphan"', () {
    test(
      'copies to the final key, deletes the pending one, returns it',
      () async {
        // The whole design in one assertion. If the object is not MOVED, then
        // pending/ holds claimed objects too, and the lifecycle rule that expires
        // the prefix starts deleting live data.
        final store = FakeStorageService(
          sizes: {'pending/deposit/u1/a.jpg': 10},
        );
        final r = await svc(store).verifyAndPromote([
          'pending/deposit/u1/a.jpg',
        ], bucket: StorageBucket.deposit);
        expect(r.ok, isTrue);
        expect(r.keys, ['deposit/u1/a.jpg']);
        expect(store.copied, ['pending/deposit/u1/a.jpg -> deposit/u1/a.jpg']);
        expect(store.deleted, ['pending/deposit/u1/a.jpg']);
      },
    );

    test('refuses a key that is not pending', () async {
      // Either already claimed, or attacker-chosen; promoting it would compute
      // a destination outside the prefix scheme entirely.
      final r = await svc(FakeStorageService()).verifyAndPromote([
        'deposit/u1/already.jpg',
      ], bucket: StorageBucket.deposit);
      expect(r.ok, isFalse);
      expect(r.error, 'invalid_input');
    });

    test('an oversized upload is refused BEFORE it is promoted', () async {
      // Ordering matters: promoting first would move the offending object to
      // its final key, where the lifecycle rule can no longer collect it.
      final store = FakeStorageService(
        sizes: {'pending/deposit/u1/big.jpg': max + 1},
      );
      final r = await svc(store).verifyAndPromote([
        'pending/deposit/u1/big.jpg',
      ], bucket: StorageBucket.deposit);
      expect(r.ok, isFalse);
      expect(r.error, 'upload_too_large');
      expect(store.copied, isEmpty, reason: 'nothing may be promoted');
      expect(store.deleted, ['pending/deposit/u1/big.jpg']);
    });

    test('a failed copy refuses rather than half-applying', () async {
      final r = await svc(_CopyFailsStorage()).verifyAndPromote([
        'pending/deposit/u1/a.jpg',
      ], bucket: StorageBucket.deposit);
      expect(r.ok, isFalse);
      expect(r.error, 'storage_unavailable');
    });
  });

  group('promotedKey — a startsWith prefix check is not an ownership check', () {
    test('a well-formed pending key promotes', () {
      expect(promotedKey('pending/deposit/u1/a.jpg'), 'deposit/u1/a.jpg');
      expect(promotedKey('pending/a.jpg'), 'a.jpg');
    });

    test('a non-pending key is not a claim', () {
      expect(promotedKey('deposit/u1/a.jpg'), isNull);
      expect(promotedKey(''), isNull);
      expect(
        promotedKey('pending/'),
        isNull,
        reason: 'this used to promote to the empty string, which is not a key',
      );
    });

    test('DOT SEGMENTS are refused — this is the whole point', () {
      // Every claim path proves ownership with a prefix, and
      // `pending/deposit/u1/../u2/x.jpg` satisfies
      // `startsWith('pending/deposit/u1/')`. Whether it then RESOLVES to u2's
      // object depends on whether R2 normalises dot segments in an object key
      // and on when `Uri` normalises relative to the SigV4 canonical request —
      // two empirical questions about someone else's implementation. Refusing
      // the shape here makes the answer irrelevant, for every claim path at
      // once, because this function is the gate they all pass through.
      expect(promotedKey('pending/deposit/u1/../u2/x.jpg'), isNull);
      expect(promotedKey('pending/../kyc/acct/passport.pdf'), isNull);
      expect(promotedKey('pending/deposit/u1/./x.jpg'), isNull);
      expect(promotedKey('pending/deposit/u1//x.jpg'), isNull);
      expect(promotedKey('pending/deposit/u1/..'), isNull);
      expect(promotedKey('pending/..'), isNull);
    });

    test('a dot INSIDE a segment is still a normal key', () {
      // The check is per segment, not a substring scan — `..` in a filename is
      // ordinary, and refusing it would break real uploads.
      expect(promotedKey('pending/g/p1/my..photo.jpg'), 'g/p1/my..photo.jpg');
      expect(promotedKey('pending/g/p1/.hidden.jpg'), 'g/p1/.hidden.jpg');
    });

    test('the refusal reaches verifyAndPromote', () async {
      // The unit above is only worth having if the claim path consults it.
      final store = FakeStorageService(defaultSize: 10);
      final r = await svc(store).verifyAndPromote([
        'pending/deposit/u1/../u2/x.jpg',
      ], bucket: StorageBucket.deposit);
      expect(r.ok, isFalse);
      expect(r.error, 'invalid_input');
      expect(
        store.copied,
        isEmpty,
        reason: 'and it refuses BEFORE any storage call',
      );
    });
  });
}

/// Storage whose every call throws — the fail-closed fixture.
class _ThrowingStorage implements StorageService {
  @override
  Future<int?> objectSize({
    required String key,
    required StorageBucket bucket,
  }) async => throw StateError('unreachable');

  @override
  Future<void> deleteObject({
    required String key,
    required StorageBucket bucket,
  }) async => throw StateError('unreachable');

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Storage whose copy fails but whose stat succeeds — promotion must not
/// half-apply a claim.
class _CopyFailsStorage extends FakeStorageService {
  // Under the cap ON PURPOSE: the inherited default (1024) exceeds this file's
  // max of 1000, so without this the object failed the SIZE check and never
  // reached the copy — the test passed while testing the wrong path.
  _CopyFailsStorage() : super(defaultSize: 10);

  @override
  Future<void> copyObject({
    required String fromKey,
    required String toKey,
    required StorageBucket bucket,
  }) async => throw StateError('copy failed');
}
