import 'package:myweli_backend/src/idempotency/idempotency_store.dart';
import 'package:test/test.dart';

/// The contract of [IdempotencyStore], run against BOTH twins — the in-memory
/// one (`idempotency_store_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself (no `_test`
/// suffix). docs/design/write-idempotency.md §3.
///
/// [store] builds the store under test with the clock it is given.
/// [prefix] makes the keys unique per run (Postgres keeps rows across files).
void idempotencyContract({
  required IdempotencyStore Function(DateTime Function() now) store,
  String prefix = '',
}) {
  var clock = DateTime.utc(2026, 10, 21, 9);
  DateTime now() => clock;
  String k(String key) => '$prefix$key';
  setUp(() => clock = DateTime.utc(2026, 10, 21, 9));

  test(
    'a first claim reserves; once completed, the same key replays its answer',
    () async {
      final s = store(now);
      final first = await s.claim(
        accountId: 'acc1',
        route: '/appointments',
        key: k('k1'),
        fingerprint: 'f1',
      );
      expect(first, isA<ClaimReserved>());
      await s.complete(
        accountId: 'acc1',
        route: '/appointments',
        key: k('k1'),
        status: 201,
        body: '{"id":"a1"}',
      );
      final again = await s.claim(
        accountId: 'acc1',
        route: '/appointments',
        key: k('k1'),
        fingerprint: 'f1',
      );
      expect(again, isA<ClaimReplay>());
      again as ClaimReplay;
      expect(again.status, 201);
      expect(again.body, '{"id":"a1"}');
    },
  );

  test('a claim while the first is still running → in progress', () async {
    final s = store(now);
    await s.claim(
      accountId: 'acc1',
      route: '/r',
      key: k('k2'),
      fingerprint: 'f',
    );
    expect(
      await s.claim(
        accountId: 'acc1',
        route: '/r',
        key: k('k2'),
        fingerprint: 'f',
      ),
      isA<ClaimInProgress>(),
    );
  });

  test('the same key with another body → mismatch, running or done', () async {
    final s = store(now);
    await s.claim(
      accountId: 'acc1',
      route: '/r',
      key: k('k3'),
      fingerprint: 'f1',
    );
    expect(
      await s.claim(
        accountId: 'acc1',
        route: '/r',
        key: k('k3'),
        fingerprint: 'f2',
      ),
      isA<ClaimMismatch>(),
    );
    await s.complete(
      accountId: 'acc1',
      route: '/r',
      key: k('k3'),
      status: 201,
      body: '{}',
    );
    expect(
      await s.claim(
        accountId: 'acc1',
        route: '/r',
        key: k('k3'),
        fingerprint: 'f2',
      ),
      isA<ClaimMismatch>(),
    );
  });

  test(
    'released (the write was refused) → the next claim starts afresh',
    () async {
      final s = store(now);
      await s.claim(
        accountId: 'acc1',
        route: '/r',
        key: k('k4'),
        fingerprint: 'f',
      );
      await s.release(accountId: 'acc1', route: '/r', key: k('k4'));
      expect(
        await s.claim(
          accountId: 'acc1',
          route: '/r',
          key: k('k4'),
          fingerprint: 'f',
        ),
        isA<ClaimReserved>(),
      );
    },
  );

  test(
    'scoped to the account and the route: the same key elsewhere is a new claim',
    () async {
      final s = store(now);
      await s.claim(
        accountId: 'acc1',
        route: '/r',
        key: k('k5'),
        fingerprint: 'f',
      );
      await s.complete(
        accountId: 'acc1',
        route: '/r',
        key: k('k5'),
        status: 201,
        body: '{"mine":1}',
      );
      expect(
        await s.claim(
          accountId: 'acc2',
          route: '/r',
          key: k('k5'),
          fingerprint: 'f',
        ),
        isA<ClaimReserved>(),
        reason: 'another account never gets the first account’s answer',
      );
      expect(
        await s.claim(
          accountId: 'acc1',
          route: '/other',
          key: k('k5'),
          fingerprint: 'f',
        ),
        isA<ClaimReserved>(),
      );
    },
  );

  test('after 24 h a key no longer replays: it is a new claim', () async {
    final s = store(now);
    await s.claim(
      accountId: 'acc1',
      route: '/r',
      key: k('k6'),
      fingerprint: 'f',
    );
    await s.complete(
      accountId: 'acc1',
      route: '/r',
      key: k('k6'),
      status: 201,
      body: '{}',
    );
    clock = clock.add(const Duration(hours: 24, minutes: 1));
    expect(
      await s.claim(
        accountId: 'acc1',
        route: '/r',
        key: k('k6'),
        fingerprint: 'f',
      ),
      isA<ClaimReserved>(),
    );
  });

  test('prune removes what is older than the window, keeps the rest', () async {
    final s = store(now);
    await s.claim(
      accountId: 'acc1',
      route: '/r',
      key: k('old'),
      fingerprint: 'f',
    );
    await s.complete(
      accountId: 'acc1',
      route: '/r',
      key: k('old'),
      status: 201,
      body: '{}',
    );
    clock = clock.add(const Duration(hours: 25));
    await s.claim(
      accountId: 'acc1',
      route: '/r',
      key: k('new'),
      fingerprint: 'f',
    );
    await s.complete(
      accountId: 'acc1',
      route: '/r',
      key: k('new'),
      status: 201,
      body: '{"n":1}',
    );
    expect(await s.prune(const Duration(hours: 24)), greaterThanOrEqualTo(1));
    final kept = await s.claim(
      accountId: 'acc1',
      route: '/r',
      key: k('new'),
      fingerprint: 'f',
    );
    expect(kept, isA<ClaimReplay>());
  });

  test('an account’s erasure removes its keys only', () async {
    final s = store(now);
    for (final acc in ['gone', 'stays']) {
      await s.claim(
        accountId: acc,
        route: '/r',
        key: k('k7'),
        fingerprint: 'f',
      );
      await s.complete(
        accountId: acc,
        route: '/r',
        key: k('k7'),
        status: 201,
        body: '{}',
      );
    }
    await s.deleteForAccount('gone');
    expect(
      await s.claim(
        accountId: 'gone',
        route: '/r',
        key: k('k7'),
        fingerprint: 'f',
      ),
      isA<ClaimReserved>(),
    );
    expect(
      await s.claim(
        accountId: 'stays',
        route: '/r',
        key: k('k7'),
        fingerprint: 'f',
      ),
      isA<ClaimReplay>(),
    );
  });
}
