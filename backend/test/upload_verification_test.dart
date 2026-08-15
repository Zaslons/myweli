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

  group('promoteNewKeys — the key-shaped twin, for the private buckets', () {
    test(
      'verifyAndPromote IS promoteNewKeys with an empty stored set',
      () async {
        // The drift pin. The two are defined as one function precisely so the
        // refusal rule cannot live in two places and disagree — including in the
        // fail-open direction.
        const keys = ['pending/kyc/a1/id.jpg', 'pending/kyc/a1/selfie.jpg'];
        final viaClaim = FakeStorageService(defaultSize: 10);
        final viaSave = FakeStorageService(defaultSize: 10);
        final a = await svc(
          viaClaim,
        ).verifyAndPromote(keys, bucket: StorageBucket.kyc);
        final b = await svc(viaSave).promoteNewKeys(
          keys,
          alreadyStored: const {},
          bucket: StorageBucket.kyc,
        );
        expect(a.ok, b.ok);
        expect(a.keys, b.keys);
        expect(viaClaim.copied, viaSave.copied);
        expect(viaClaim.deleted, viaSave.deleted);

        // …and they agree on the refusals too, not just the happy path.
        for (final bad in ['kyc/a1/id.jpg', '', 'pending/']) {
          final x = await svc(
            FakeStorageService(),
          ).verifyAndPromote([bad], bucket: StorageBucket.kyc);
          final y = await svc(FakeStorageService()).promoteNewKeys(
            [bad],
            alreadyStored: const {},
            bucket: StorageBucket.kyc,
          );
          expect(x.ok, isFalse, reason: bad);
          expect(x.error, y.error, reason: bad);
        }
      },
    );

    test('a key we do NOT hold is refused however promoted it looks', () async {
      final store = FakeStorageService(defaultSize: 10);
      final r = await svc(store).promoteNewKeys(
        ['kyc/someone_else/passport.pdf'],
        alreadyStored: const {},
        bucket: StorageBucket.kyc,
      );
      expect(r.ok, isFalse);
      expect(r.error, 'invalid_input');
      expect(store.copied, isEmpty);
    });

    test('an all-unchanged save touches storage not at all', () async {
      final store = FakeStorageService(defaultSize: 10);
      final r = await svc(store).promoteNewKeys(
        ['kyc/a1/id.jpg'],
        alreadyStored: const {'kyc/a1/id.jpg'},
        bucket: StorageBucket.kyc,
      );
      expect(r.ok, isTrue);
      expect(r.keys, ['kyc/a1/id.jpg']);
      expect(store.copied, isEmpty);
      expect(store.deleted, isEmpty);
    });
  });

  group('a partial promotion must stay RETRYABLE', () {
    test('a failure on the SECOND copy destroys no source', () async {
      // The test the old one could not be. `_CopyFailsStorage` passes a single
      // key, so the failure is always at index 0 and half-application is
      // unobservable. Interleaved copy-then-delete left key 0 at its FINAL
      // prefix — unrecorded in Postgres, outside `pending/`, so no lifecycle
      // rule collects it — and made the identical retry fail DIFFERENTLY,
      // because verify() then HEADs a source promotion had already deleted.
      final store = _FailsSecondCopy();
      const keys = ['pending/kyc/a1/one.jpg', 'pending/kyc/a1/two.jpg'];
      final first = await svc(store).promoteNewKeys(
        keys,
        alreadyStored: const {},
        bucket: StorageBucket.kyc,
      );
      expect(first.ok, isFalse);
      expect(first.error, 'storage_unavailable');
      expect(
        store.deleted,
        isEmpty,
        reason: 'every pending source must survive, or the retry cannot work',
      );

      // Same payload, no re-upload. The destination is a pure function of the
      // source, so the already-copied object is simply overwritten.
      store.armed = false;
      final second = await svc(store).promoteNewKeys(
        keys,
        alreadyStored: const {},
        bucket: StorageBucket.kyc,
      );
      expect(second.ok, isTrue, reason: 'error was ${second.error}');
      expect(second.keys, ['kyc/a1/one.jpg', 'kyc/a1/two.jpg']);
      expect(store.deleted, keys);
    });
  });

  group('promoteNewUrls — a SAVE is not a claim', () {
    const base = 'https://cdn.myweli.com';
    String url(String key) => '$base/$key';

    test('promotes the new url and passes the stored one through', () async {
      // The shape every one of these surfaces actually has: one url the client
      // just uploaded next to one the server handed it on the last read.
      // `verifyAndPromote` refuses the second outright, which is why every
      // caller that used it re-saved into a 400.
      final store = FakeStorageService(sizes: {'pending/g/p1/new.jpg': 10});
      final r = await svc(store).promoteNewUrls(
        [url('g/p1/old.jpg'), url('pending/g/p1/new.jpg')],
        publicBaseUrl: base,
        alreadyStored: {url('g/p1/old.jpg')},
        bucket: StorageBucket.public,
      );
      expect(r.ok, isTrue);
      expect(r.urls, [url('g/p1/old.jpg'), url('g/p1/new.jpg')]);
      expect(
        store.copied,
        ['pending/g/p1/new.jpg -> g/p1/new.jpg'],
        reason: 'only the NEW object moves; the stored one is already promoted',
      );
    });

    test('order survives the partition', () async {
      // The result is reassembled from two lists, and before/after pairs are
      // read positionally (`urls[i * 2]` / `urls[i * 2 + 1]`) — a scramble here
      // swaps somebody's before with their after.
      final store = FakeStorageService(defaultSize: 10);
      final r = await svc(store).promoteNewUrls(
        [
          url('pending/a.jpg'),
          url('kept-b.jpg'),
          url('pending/c.jpg'),
          url('kept-d.jpg'),
        ],
        publicBaseUrl: base,
        alreadyStored: {url('kept-b.jpg'), url('kept-d.jpg')},
        bucket: StorageBucket.public,
      );
      expect(r.ok, isTrue);
      expect(r.urls, [
        url('a.jpg'),
        url('kept-b.jpg'),
        url('c.jpg'),
        url('kept-d.jpg'),
      ]);
    });

    test('a promoted-looking url we do NOT hold is refused', () async {
      // The security half. A promoted key is just a key without the prefix, so
      // "not pending" is indistinguishable from "string the client invented" —
      // membership in `alreadyStored` is the only thing that separates them.
      // Accepting on shape would let a caller point its avatar at any object in
      // the bucket, including another salon's.
      final store = FakeStorageService(defaultSize: 10);
      final r = await svc(store).promoteNewUrls(
        [url('kyc/someone-else/passport.jpg')],
        publicBaseUrl: base,
        alreadyStored: const {},
        bucket: StorageBucket.public,
      );
      expect(r.ok, isFalse);
      expect(r.error, 'invalid_input');
      expect(store.copied, isEmpty);
    });

    test('a foreign origin is refused', () async {
      final r = await svc(FakeStorageService(defaultSize: 10)).promoteNewUrls(
        ['https://evil.example/pending/x.jpg'],
        publicBaseUrl: base,
        alreadyStored: const {},
        bucket: StorageBucket.public,
      );
      expect(r.ok, isFalse);
      expect(r.error, 'invalid_input');
    });

    test('an oversized new upload refuses the WHOLE save', () async {
      // Partial application would store a mix of promoted and pending urls,
      // and the pending half would vanish a day later.
      final store = FakeStorageService(
        sizes: {'pending/ok.jpg': 10, 'pending/big.jpg': max + 1},
      );
      final r = await svc(store).promoteNewUrls(
        [url('pending/ok.jpg'), url('pending/big.jpg')],
        publicBaseUrl: base,
        alreadyStored: const {},
        bucket: StorageBucket.public,
      );
      expect(r.ok, isFalse);
      expect(r.error, 'upload_too_large');
      expect(store.copied, isEmpty);
    });

    test('an all-unchanged save touches storage not at all', () async {
      // The common case — editing a caption, renaming an artist. It must not
      // cost a HEAD per image, and must never fail.
      final store = FakeStorageService(defaultSize: 10);
      final r = await svc(store).promoteNewUrls(
        [url('a.jpg'), url('b.jpg')],
        publicBaseUrl: base,
        alreadyStored: {url('a.jpg'), url('b.jpg')},
        bucket: StorageBucket.public,
      );
      expect(r.ok, isTrue);
      expect(r.urls, [url('a.jpg'), url('b.jpg')]);
      expect(store.copied, isEmpty);
      expect(store.deleted, isEmpty);
    });

    test('a trailing slash on the base does not double up', () async {
      final store = FakeStorageService(defaultSize: 10);
      final r = await svc(store).promoteNewUrls(
        [url('pending/a.jpg')],
        publicBaseUrl: '$base/',
        alreadyStored: const {},
        bucket: StorageBucket.public,
      );
      expect(r.urls, [url('a.jpg')]);
    });

    test('a promoted key belongs to the SAME set as a promoted url', () async {
      // promoteNewUrls delegates its pending half to promoteNewKeys, so the
      // refusal rule exists once. This is the seam.
      final store = FakeStorageService(defaultSize: 10);
      final r = await svc(store).promoteNewKeys(
        ['kept.jpg', 'pending/new.jpg'],
        alreadyStored: const {'kept.jpg'},
        bucket: StorageBucket.kyc,
      );
      expect(r.ok, isTrue);
      expect(r.keys, ['kept.jpg', 'new.jpg']);
      expect(store.copied, ['pending/new.jpg -> new.jpg']);
    });

    test('publicBaseUrl comes from storage, so it cannot drift', () {
      // The route reads this instead of taking a second base from the
      // composition root — one source, so a url can never be validated against
      // an origin the objects are not served from.
      expect(svc(FakeStorageService()).publicBaseUrl, isNull);
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

/// Storage that fails only the SECOND copy, and can be disarmed for the retry.
class _FailsSecondCopy extends FakeStorageService {
  _FailsSecondCopy() : super(defaultSize: 10);

  bool armed = true;
  int _copies = 0;

  @override
  Future<void> copyObject({
    required String fromKey,
    required String toKey,
    required StorageBucket bucket,
  }) async {
    _copies++;
    if (armed && _copies == 2) throw StateError('copy failed');
    return super.copyObject(fromKey: fromKey, toKey: toKey, bucket: bucket);
  }
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
