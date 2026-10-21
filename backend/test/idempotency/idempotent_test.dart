import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/idempotency/idempotency_store.dart';
import 'package:myweli_backend/src/idempotency/idempotent.dart';
import 'package:test/test.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// The route helper (docs/design/write-idempotency.md §3): a creating POST
/// with an `Idempotency-Key` runs once; its success is kept and replayed for
/// the same key; a refusal frees the key; without a key nothing changes.
void main() {
  late InMemoryIdempotencyStore store;
  late int runs;

  setUp(() {
    store = InMemoryIdempotencyStore();
    runs = 0;
  });

  RequestContext ctx({
    String? key,
    String body = '{"slot":"10:00"}',
    String path = '/appointments',
  }) {
    final context = _MockRequestContext();
    when(() => context.request).thenReturn(
      Request.post(
        Uri.parse('http://localhost$path'),
        headers: {if (key != null) 'Idempotency-Key': key},
        body: body,
      ),
    );
    when(() => context.read<IdempotencyStore>()).thenReturn(store);
    return context;
  }

  Future<Response> created() async {
    runs++;
    return Response.json(
      statusCode: HttpStatus.created,
      body: {'id': 'a$runs'},
    );
  }

  test(
    'no key: the write runs as today, and the store is never read',
    () async {
      final context = ctx();
      final res = await idempotent(context, accountId: 'acc1', run: created);
      expect(res.statusCode, HttpStatus.created);
      expect(runs, 1);
      verifyNever(() => context.read<IdempotencyStore>());
    },
  );

  test(
    'a malformed key → 400 invalid_idempotency_key, nothing written',
    () async {
      for (final bad in [
        'short',
        'has space in it',
        'x' * 129,
        'é-accented-key',
      ]) {
        final res = await idempotent(
          ctx(key: bad),
          accountId: 'acc1',
          run: created,
        );
        expect(res.statusCode, HttpStatus.badRequest, reason: bad);
        expect(await res.json(), {'error': 'invalid_idempotency_key'});
      }
      expect(runs, 0);
    },
  );

  test(
    'the same key twice: ONE write, and the second answer is the first, replayed',
    () async {
      final first = await idempotent(
        ctx(key: 'key-000000000001'),
        accountId: 'acc1',
        run: created,
      );
      final second = await idempotent(
        ctx(key: 'key-000000000001'),
        accountId: 'acc1',
        run: created,
      );
      expect(runs, 1);
      expect(first.statusCode, HttpStatus.created);
      expect(second.statusCode, HttpStatus.created);
      expect(await second.json(), {'id': 'a1'});
      expect(second.headers['idempotent-replayed'], 'true');
      expect(first.headers['idempotent-replayed'], isNull);
    },
  );

  test('the first answer is still readable after it was kept', () async {
    final first = await idempotent(
      ctx(key: 'key-000000000002'),
      accountId: 'acc1',
      run: created,
    );
    expect(await first.json(), {'id': 'a1'});
  });

  test('a refused write frees the key: a new try runs again', () async {
    var refuse = true;
    Future<Response> maybe() async {
      runs++;
      return refuse
          ? Response.json(
              statusCode: HttpStatus.conflict,
              body: {'error': 'slot_unavailable'},
            )
          : Response.json(statusCode: HttpStatus.created, body: {'id': 'ok'});
    }

    final refused = await idempotent(
      ctx(key: 'key-000000000003'),
      accountId: 'acc1',
      run: maybe,
    );
    expect(refused.statusCode, HttpStatus.conflict);
    refuse = false;
    final retried = await idempotent(
      ctx(key: 'key-000000000003'),
      accountId: 'acc1',
      run: maybe,
    );
    expect(retried.statusCode, HttpStatus.created);
    expect(runs, 2);
  });

  test('a write that throws frees the key too', () async {
    await expectLater(
      idempotent(
        ctx(key: 'key-000000000004'),
        accountId: 'acc1',
        run: () async => throw StateError('db down'),
      ),
      throwsStateError,
    );
    final retried = await idempotent(
      ctx(key: 'key-000000000004'),
      accountId: 'acc1',
      run: created,
    );
    expect(retried.statusCode, HttpStatus.created);
  });

  test(
    'the same key while the first is still running → 409 request_in_progress',
    () async {
      await store.claim(
        accountId: 'acc1',
        route: '/appointments',
        key: 'key-000000000005',
        fingerprint: fingerprintOf('{"slot":"10:00"}'),
      );
      final res = await idempotent(
        ctx(key: 'key-000000000005'),
        accountId: 'acc1',
        run: created,
      );
      expect(res.statusCode, HttpStatus.conflict);
      expect(await res.json(), {'error': 'request_in_progress'});
      expect(runs, 0);
    },
  );

  test('the same key with another body → 422 idempotency_key_reused', () async {
    await idempotent(
      ctx(key: 'key-000000000006'),
      accountId: 'acc1',
      run: created,
    );
    final res = await idempotent(
      ctx(key: 'key-000000000006', body: '{"slot":"11:00"}'),
      accountId: 'acc1',
      run: created,
    );
    expect(res.statusCode, HttpStatus.unprocessableEntity);
    expect(await res.json(), {'error': 'idempotency_key_reused'});
    expect(runs, 1);
  });

  test(
    'another account with the same key gets its own write, never the first answer',
    () async {
      await idempotent(
        ctx(key: 'key-000000000007'),
        accountId: 'acc1',
        run: created,
      );
      final other = await idempotent(
        ctx(key: 'key-000000000007'),
        accountId: 'acc2',
        run: created,
      );
      expect(runs, 2);
      expect(await other.json(), {'id': 'a2'});
    },
  );
}
