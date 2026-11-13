import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/kyc_service.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:myweli_backend/src/upload_verification_service.dart';
import 'package:test/test.dart';

import '../routes/me/kyc.dart' as kyc_route;
import 'auth/kyc_write_contract.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// Storage whose deletes all fail, recording each attempt with its bucket.
class _DeleteFails extends FakeStorageService {
  _DeleteFails() : super(defaultSize: 10);

  final attempted = <(String, StorageBucket)>[];

  @override
  Future<void> deleteObject({
    required String key,
    required StorageBucket bucket,
  }) async {
    attempted.add((key, bucket));
    throw StateError('storage is down');
  }
}

/// Storage that HANGS on every delete of a promoted `kyc/` object — R2 not
/// answering rather than erroring. The promotion's own `pending/` deletes
/// still complete, so only the post-write deletes meet the hang.
class _KycDeleteHangs extends FakeStorageService {
  _KycDeleteHangs() : super(defaultSize: 10);

  final attempted = <String>[];

  @override
  Future<void> deleteObject({
    required String key,
    required StorageBucket bucket,
  }) {
    if (!key.startsWith('kyc/')) {
      return super.deleteObject(key: key, bucket: bucket);
    }
    attempted.add(key);
    return Completer<void>().future;
  }
}

/// Storage whose copies fail: the promotion answers `storage_unavailable`.
class _CopyFails extends FakeStorageService {
  _CopyFails() : super(defaultSize: 10);

  @override
  Future<void> copyObject({
    required String fromKey,
    required String toKey,
    required StorageBucket bucket,
  }) async => throw StateError('storage is down');
}

/// The race of B0.22 §3.2 point 2, staged in the repository: the read hands
/// back the row as it was, and the [winner]'s submit lands right after it —
/// between this request's read and its write.
class _WinnerLandsAfterRead extends InMemoryProviderAuthRepository {
  _WinnerLandsAfterRead({required super.tokens}) : super(echoDevCode: true);

  List<Map<String, dynamic>>? winner;

  /// Instead of a winner's submit, the account's deletion lands there.
  bool deletedAfterRead = false;

  /// A THIRD submit, landing right after a refusal commits — after the
  /// refused request's lock is gone, before its deletes run.
  List<Map<String, dynamic>>? afterRefusal;

  @override
  Future<KycWrite> submitKyc(
    String accountId,
    List<Map<String, dynamic>> docs, {
    Set<String> passThrough = const {},
  }) async {
    final w = await super.submitKyc(accountId, docs, passThrough: passThrough);
    final third = afterRefusal;
    if (w.refused && third != null) {
      afterRefusal = null;
      await super.submitKyc(accountId, third);
    }
    return w;
  }

  @override
  Future<ProviderAccount?> accountById(String id) async {
    final current = await super.accountById(id);
    final docs = winner;
    if (current == null || (docs == null && !deletedAfterRead)) return current;
    winner = null;
    final asRead = ProviderAccount(
      id: current.id,
      phoneNumber: current.phoneNumber,
      businessName: current.businessName,
      businessType: current.businessType,
      createdAt: current.createdAt,
      verificationStatus: current.verificationStatus,
      providerId: current.providerId,
      kycDocs: List.of(current.kycDocs),
    );
    if (deletedAfterRead) {
      deletedAfterRead = false;
      await super.deleteAccount(id);
    } else {
      await super.submitKyc(id, docs!);
    }
    return asRead;
  }
}

void main() {
  late InMemoryProviderAuthRepository providerAuth;
  late KycService service;
  final tokens = TokenService(secret: 'test-secret');
  late String accountId;
  late String token;

  setUp(() async {
    providerAuth = InMemoryProviderAuthRepository(
      tokens: tokens,
      echoDevCode: true,
    );
    service = KycService(providerAuth);
    final reg = await providerAuth.register(
      email: 'reg7@test.pro',
      authProvider: 'google',
      googleSub: 'reg-sub-7',
      phoneNumber: '+2250500000070',
      businessName: 'X',
      businessType: 'salon',
    );
    accountId = reg.provider!.id;
    token = tokens.issueAccessToken(subject: accountId, role: 'provider').token;
  });

  List<Map<String, dynamic>> docs() => [
    {
      'type': 'idCard',
      'fileName': 'id.jpg',
      'key': 'pending/kyc/$accountId/a.jpg',
    },
    {
      'type': 'selfie',
      'fileName': 's.jpg',
      'key': 'pending/kyc/$accountId/b.jpg',
    },
  ];

  group('KycService', () {
    test('submit stores docs + sets pending; status reads back', () async {
      final r = await service.submit(accountId, docs());
      expect(r.ok, isTrue);
      expect(r.data!['status'], 'pending');
      expect((r.data!['documents'] as List).length, 2);
      final first = (r.data!['documents'] as List).first as Map;
      expect(first['type'], 'idCard');
      expect(first['submittedAt'], isNotNull); // server-stamped

      final got = await service.status(accountId);
      expect((got.data!['documents'] as List).length, 2);
    });

    test('resubmit clears a prior rejection back to pending', () async {
      (await providerAuth.accountById(accountId))!
        ..verificationStatus = 'rejected'
        ..rejectionReason = 'Blurry ID';
      final r = await service.submit(accountId, docs());
      expect(r.data!['status'], 'pending');
      expect(r.data!['rejectionReason'], isNull);
    });

    test('rejects bad type / foreign key / empty', () async {
      expect(
        (await service.submit(accountId, [
          {'type': 'passport', 'key': 'pending/kyc/$accountId/a.jpg'},
        ])).error,
        'invalid_input',
      );
      // A key under another account's prefix is rejected.
      expect(
        (await service.submit(accountId, [
          {'type': 'idCard', 'key': 'pending/kyc/someone_else/a.jpg'},
        ])).error,
        'invalid_input',
      );
      expect(
        (await service.submit(accountId, const [])).error,
        'invalid_input',
      );
    });
  });

  // B0.22 §3.2 — the in-memory twin of the compare under the row lock; the
  // Postgres twin runs the same contract in db/postgres_repositories_test.dart.
  group('submitKyc — the twin contract (in memory)', () {
    var n = 0;
    kycWriteContract(
      repo: () =>
          InMemoryProviderAuthRepository(tokens: tokens, echoDevCode: true),
      account: (r) async => (await r.register(
        email: 'kycw${++n}@test.pro',
        authProvider: 'google',
        googleSub: 'kycw-sub-$n',
        phoneNumber: '+2250500000072',
        businessName: 'X',
        businessType: 'salon',
      )).provider!.id,
    );
  });

  // B0.22 (decision 137): a document replaced by a re-submit is deleted from
  // storage then, so it can no longer outlive the account. After the write,
  // best effort, own prefix only; the pass-through check runs under the row
  // lock. Design: docs/design/pro-deletion-erase-gaps.md §3.2, §8 tests 4-9.
  group('B0.22 — a re-submit deletes the documents it replaced', () {
    late FakeStorageService store;
    late KycService kyc;

    String pending(String name) => 'pending/kyc/$accountId/$name';
    String promoted(String name) => 'kyc/$accountId/$name';

    KycService over(ProviderAuthRepository repo, StorageService storage) =>
        KycService(
          repo,
          verifier: UploadVerificationService(storage: storage),
          storage: storage,
        );

    setUp(() {
      store = FakeStorageService(defaultSize: 10);
      kyc = over(providerAuth, store);
    });

    Future<List<String>> rowKeys(
      ProviderAuthRepository repo,
      String id,
    ) async => [
      for (final d in (await repo.accountById(id))!.kycDocs) d['key'] as String,
    ];

    List<String> answered(KycResult r) => [
      for (final d in r.data!['documents'] as List) (d as Map)['key'] as String,
    ];

    /// What a first submit leaves: two documents, promoted and stored.
    Future<void> seed(KycService service) async {
      final r = await service.submit(accountId, [
        {'type': 'idCard', 'key': pending('id.jpg')},
        {'type': 'selfie', 'key': pending('selfie.jpg')},
      ]);
      expect(r.ok, isTrue, reason: 'seed: ${r.error}');
      expect(await rowKeys(providerAuth, accountId), [
        promoted('id.jpg'),
        promoted('selfie.jpg'),
      ]);
      store.deleted.clear();
      store.copied.clear();
    }

    test('4. one of two stored documents replaced: exactly the replaced '
        'object is deleted', () async {
      await seed(kyc);
      final r = await kyc.submit(accountId, [
        {'type': 'idCard', 'key': pending('id-v2.jpg')},
        {'type': 'selfie', 'key': promoted('selfie.jpg')},
      ]);
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(answered(r), [promoted('id-v2.jpg'), promoted('selfie.jpg')]);
      expect(
        store.deleted,
        [pending('id-v2.jpg'), promoted('id.jpg')],
        reason:
            'the promotion deletes its pending source; the write then '
            'deletes the replaced document, and nothing else',
      );
    });

    test('5. a re-sent pending key whose promoted object is stored deletes '
        'nothing — compared after the promotion', () async {
      await seed(kyc);
      final r = await kyc.submit(accountId, [
        {'type': 'idCard', 'key': pending('id.jpg')},
        {'type': 'selfie', 'key': promoted('selfie.jpg')},
      ]);
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(answered(r), [promoted('id.jpg'), promoted('selfie.jpg')]);
      expect(store.copied, isEmpty, reason: 'nothing new was promoted');
      expect(store.deleted, isEmpty, reason: 'the document is still listed');
    });

    test('6. a foreign key, a pending key or a look-alike prefix in the '
        'stored list is never deleted; the own superseded one is', () async {
      // Seeded straight into the row, as provider_account_service_test.dart
      // seeds its foreign key: the service itself could not store these.
      await providerAuth.submitKyc(accountId, [
        {'type': 'idCard', 'key': promoted('a.jpg')},
        {'type': 'selfie', 'key': promoted('b.jpg')},
        {'type': 'addressProof', 'key': 'kyc/other-account/c.jpg'},
        {'type': 'businessRegistration', 'key': pending('d.jpg')},
        {'type': 'addressProof', 'key': 'kyc/${accountId}x/e.jpg'},
      ]);
      final r = await kyc.submit(accountId, [
        {'type': 'idCard', 'key': promoted('a.jpg')},
      ]);
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(store.deleted, [promoted('b.jpg')]);
    });

    test('7. a failing storage delete is swallowed: 200, the row holds the '
        'new list, and the delete was attempted in the KYC bucket', () async {
      final failing = _DeleteFails();
      final service = over(providerAuth, failing);
      await seed(service);
      failing.attempted.clear();

      final r = await service.submit(accountId, [
        {'type': 'idCard', 'key': pending('id-v2.jpg')},
        {'type': 'selfie', 'key': promoted('selfie.jpg')},
      ]);
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.data!['status'], 'pending');
      final now = [promoted('id-v2.jpg'), promoted('selfie.jpg')];
      expect(answered(r), now);
      expect(await rowKeys(providerAuth, accountId), now);
      expect(
        failing.attempted,
        contains((promoted('id.jpg'), StorageBucket.kyc)),
      );
    });

    test('7b. a storage delete that never answers is cut off: the stored '
        'submit still answers 200 with the new list', () async {
      final hangs = _KycDeleteHangs();
      final service = KycService(
        providerAuth,
        verifier: UploadVerificationService(storage: hangs),
        storage: hangs,
        deleteBudget: const Duration(milliseconds: 50),
      );
      await seed(service);

      final r = await service.submit(accountId, [
        {'type': 'idCard', 'key': pending('id-v2.jpg')},
        {'type': 'selfie', 'key': promoted('selfie.jpg')},
      ]);
      expect(r.ok, isTrue, reason: '${r.error}');
      final now = [promoted('id-v2.jpg'), promoted('selfie.jpg')];
      expect(answered(r), now);
      expect(await rowKeys(providerAuth, accountId), now);
      expect(hangs.attempted, [promoted('id.jpg')]);
    }, timeout: const Timeout(Duration(seconds: 10)));

    group('8. a refused submit deletes nothing old', () {
      final stored = <Map<String, dynamic>>[];

      setUp(() async {
        stored
          ..clear()
          ..addAll([
            {'type': 'idCard', 'key': promoted('id.jpg')},
            {'type': 'selfie', 'key': promoted('selfie.jpg')},
          ]);
        await providerAuth.submitKyc(accountId, stored);
      });

      test('invalid_input', () async {
        final r = await kyc.submit(accountId, [
          {'type': 'idCard', 'key': pending('id-v2.jpg')},
          {'type': 'selfie', 'key': 'kyc/someone_else/a.jpg'},
        ]);
        expect(r.error, 'invalid_input');
        expect(store.deleted, isEmpty);
        expect(await rowKeys(providerAuth, accountId), [
          promoted('id.jpg'),
          promoted('selfie.jpg'),
        ]);
      });

      test('storage_unavailable from the promotion', () async {
        final copyFails = _CopyFails();
        final r = await over(providerAuth, copyFails).submit(accountId, [
          {'type': 'idCard', 'key': pending('id-v2.jpg')},
          {'type': 'selfie', 'key': promoted('selfie.jpg')},
        ]);
        expect(r.error, 'storage_unavailable');
        expect(copyFails.deleted, isEmpty);
        expect(await rowKeys(providerAuth, accountId), [
          promoted('id.jpg'),
          promoted('selfie.jpg'),
        ]);
      });

      // The one refusal where deleting an old document does harm: the lock
      // refuses a request that REPLACED a document, and the winner kept it.
      // Both refusals above return before any delete could run; this one
      // reaches the write, so « delete before the write » turns it red.
      test('refused by the lock after replacing a document: the replaced '
          'document, which the winner kept, is not deleted', () async {
        final repo = _WinnerLandsAfterRead(tokens: tokens);
        final id = (await repo.register(
          email: 'replaced@test.pro',
          authProvider: 'google',
          googleSub: 'replaced-sub',
          phoneNumber: '+2250500000074',
          businessName: 'X',
          businessType: 'salon',
        )).provider!.id;
        final k1 = 'kyc/$id/k1.jpg';
        final k2 = 'kyc/$id/k2.jpg';
        await repo.submitKyc(id, [
          {'type': 'idCard', 'key': k1},
          {'type': 'selfie', 'key': k2},
        ]);
        // The winner, landing after this request's read, dropped k1 and
        // kept k2.
        repo.winner = [
          {'type': 'selfie', 'key': k2},
          {'type': 'idCard', 'key': 'kyc/$id/kx.jpg'},
        ];

        final r = await over(repo, store).submit(id, [
          {'type': 'idCard', 'key': k1}, // pass-through
          {'type': 'selfie', 'key': 'pending/kyc/$id/p3.jpg'}, // replaces k2
        ]);
        expect(r.error, 'invalid_input');
        expect(await rowKeys(repo, id), [
          k2,
          'kyc/$id/kx.jpg',
        ], reason: 'the winner\'s row stands');
        expect(
          store.deleted.where((k) => k.startsWith('kyc/')),
          ['kyc/$id/p3.jpg'],
          reason:
              'only this request\'s own fresh copy; k2 is the winner\'s '
              'document, k1 was the winner\'s to delete',
        );
      });
    });

    test('9. a pass-through key gone from the row between the read and the '
        'write: 400 invalid_input, the row unchanged, this request\'s own '
        'promoted copies deleted — except the one the winner stored from the '
        'same pending upload', () async {
      final repo = _WinnerLandsAfterRead(tokens: tokens);
      final reg = await repo.register(
        email: 'race@test.pro',
        authProvider: 'google',
        googleSub: 'race-sub',
        phoneNumber: '+2250500000071',
        businessName: 'X',
        businessType: 'salon',
      );
      final id = reg.provider!.id;
      await repo.submitKyc(id, [
        {'type': 'idCard', 'key': 'kyc/$id/k1.jpg'},
      ]);
      // The winner replaced k1, carrying the same pending upload p2 as this
      // request: `promotedKey(p2)` is the winner's committed document.
      final winner = [
        {'type': 'selfie', 'key': 'kyc/$id/p2.jpg'},
        {'type': 'idCard', 'key': 'kyc/$id/kx.jpg'},
      ];
      repo.winner = winner;

      final r = await over(repo, store).submit(id, [
        {'type': 'idCard', 'key': 'kyc/$id/k1.jpg'}, // pass-through
        {'type': 'selfie', 'key': 'pending/kyc/$id/p2.jpg'},
        {'type': 'addressProof', 'key': 'pending/kyc/$id/p3.jpg'},
      ]);
      expect(r.ok, isFalse);
      expect(r.error, 'invalid_input');
      expect(await rowKeys(repo, id), [
        'kyc/$id/p2.jpg',
        'kyc/$id/kx.jpg',
      ], reason: 'the winner\'s row stands');
      expect(store.copied, [
        'pending/kyc/$id/p2.jpg -> kyc/$id/p2.jpg',
        'pending/kyc/$id/p3.jpg -> kyc/$id/p3.jpg',
      ], reason: 'setup: both uploads were promoted before the write');
      expect(
        store.deleted.where((k) => k.startsWith('kyc/')),
        ['kyc/$id/p3.jpg'],
        reason:
            'p3 is this request\'s alone; p2 is the winner\'s stored '
            'document; k1 was the winner\'s to delete',
      );
    });
    test('9b. the account deleted between the read and the write: forbidden, '
        'and this request\'s promoted copies deleted — they would otherwise '
        'outlive it', () async {
      final repo = _WinnerLandsAfterRead(tokens: tokens);
      final reg = await repo.register(
        email: 'gone@test.pro',
        authProvider: 'google',
        googleSub: 'gone-sub',
        phoneNumber: '+2250500000073',
        businessName: 'X',
        businessType: 'salon',
      );
      final id = reg.provider!.id;
      repo.deletedAfterRead = true;

      final r = await over(repo, store).submit(id, [
        {'type': 'idCard', 'key': 'pending/kyc/$id/p1.jpg'},
      ]);
      expect(r.error, 'forbidden');
      expect(await repo.accountById(id), isNull, reason: 'setup');
      expect(store.deleted.where((k) => k.startsWith('kyc/')), [
        'kyc/$id/p1.jpg',
      ]);
    });

    test('9c. three concurrent submits: a third that commits the shared '
        'upload\'s copy after the refusal keeps it — the refused request '
        're-reads the row before each delete', () async {
      final repo = _WinnerLandsAfterRead(tokens: tokens);
      final id = (await repo.register(
        email: 'third@test.pro',
        authProvider: 'google',
        googleSub: 'third-sub',
        phoneNumber: '+2250500000075',
        businessName: 'X',
        businessType: 'salon',
      )).provider!.id;
      await repo.submitKyc(id, [
        {'type': 'idCard', 'key': 'kyc/$id/k1.jpg'},
      ]);
      // A commits [k3] after this request's read; C, carrying the same
      // pending upload p2 as this request, commits [promotedKey(p2)] once
      // this request has been refused and its lock is gone.
      repo
        ..winner = [
          {'type': 'idCard', 'key': 'kyc/$id/k3.jpg'},
        ]
        ..afterRefusal = [
          {'type': 'selfie', 'key': 'kyc/$id/p2.jpg'},
        ];

      final r = await over(repo, store).submit(id, [
        {'type': 'idCard', 'key': 'kyc/$id/k1.jpg'}, // pass-through
        {'type': 'selfie', 'key': 'pending/kyc/$id/p2.jpg'},
      ]);
      expect(r.error, 'invalid_input');
      expect(await rowKeys(repo, id), [
        'kyc/$id/p2.jpg',
      ], reason: 'setup: C\'s row stands');
      expect(
        store.deleted.where((k) => k.startsWith('kyc/')),
        isEmpty,
        reason:
            'p2 was this request\'s own fresh copy under the lock, but C '
            'has committed it since: deleting it would leave C\'s row '
            'pointing at a deleted object',
      );
    });
  });

  group('route', () {
    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<TokenService>()).thenReturn(tokens);
      when(() => context.read<KycService>()).thenReturn(service);
      return context;
    }

    Request req(String method, {String? bearer, Object? body}) => Request(
      method,
      Uri.parse('http://localhost/me/kyc'),
      headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
      body: body == null ? null : '{"documents":${_json(docs())}}',
    );

    test('GET → 200; POST → 200 pending; no token → 401; user → 403; '
        'bad verb → 405', () async {
      final post = await kyc_route.onRequest(
        ctx(req('POST', bearer: token, body: docs())),
      );
      expect(post.statusCode, HttpStatus.ok);
      expect((await post.json() as Map)['status'], 'pending');

      final get = await kyc_route.onRequest(ctx(req('GET', bearer: token)));
      expect(get.statusCode, HttpStatus.ok);

      final noAuth = await kyc_route.onRequest(ctx(req('GET')));
      expect(noAuth.statusCode, HttpStatus.unauthorized);

      final userTok = tokens
          .issueAccessToken(subject: 'u1', role: 'user')
          .token;
      final asUser = await kyc_route.onRequest(
        ctx(req('GET', bearer: userTok)),
      );
      expect(asUser.statusCode, HttpStatus.forbidden);

      final badVerb = await kyc_route.onRequest(
        ctx(req('DELETE', bearer: token)),
      );
      expect(badVerb.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}

/// Tiny JSON-array encoder for the fixture docs (avoids importing convert here).
String _json(List<Map<String, dynamic>> docs) {
  final parts = docs.map(
    (d) =>
        '{"type":"${d['type']}","fileName":"${d['fileName']}",'
        '"key":"${d['key']}"}',
  );
  return '[${parts.join(',')}]';
}
