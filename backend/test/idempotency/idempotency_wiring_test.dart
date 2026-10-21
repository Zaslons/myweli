import 'dart:io';

import 'package:myweli_backend/src/idempotency/idempotency_store.dart';
import 'package:test/test.dart';

/// The wiring nothing behavioural can see (docs/design/write-idempotency.md
/// §3): every route test hands its context an in-memory store, so production
/// getting the in-memory twin, the cron never pruning, or an erasure service
/// built without the store would leave every other test green.
void main() {
  final deps = File('lib/src/dependencies.dart').readAsStringSync();

  test('production gets the Postgres store, shared across instances', () {
    expect(deps, contains('PostgresIdempotencyStore(_pool!)'));
  });

  test('every request can read it', () {
    expect(
      File('routes/_middleware.dart').readAsStringSync(),
      contains('provider<IdempotencyStore>((_) => idempotencyStore)'),
    );
  });

  test('both erasures are built with it — consumer and salon', () {
    expect(
      'idempotency: idempotencyStore'.allMatches(deps).length,
      2,
      reason: 'UserErasureService and ProviderAccountService',
    );
  });

  test('the daily cron prunes it after the window, and says how many', () {
    // The maintenance tick (docs/design/infra-cron-maintenance.md).
    expect(
      deps,
      contains(
        'pruneIdempotency: () => pruneIdempotencyKeys(kIdempotencyWindow)',
      ),
    );
    expect(kIdempotencyWindow, const Duration(hours: 24));
    expect(
      File('lib/src/maintenance/maintenance_tick.dart').readAsStringSync(),
      contains("'idempotencyKeysPruned'"),
      reason: 'a prune nobody can see is the shape this repo keeps finding',
    );
  });

  test('the four creating POSTs go through the helper', () {
    for (final route in [
      'routes/appointments/index.dart',
      'routes/providers/[id]/appointments.dart',
      'routes/providers/[id]/clients/[clientId]/notes/index.dart',
      'routes/me/provider/members/index.dart',
    ]) {
      expect(
        File(route).readAsStringSync(),
        contains('return idempotent('),
        reason: route,
      );
    }
  });
}
