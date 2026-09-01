import 'package:myweli_backend/src/db/database.dart';
import 'package:test/test.dart';

/// The pool must fit the instance it connects to (docs/design/infra-staging.md
/// §7, finding 5).
///
/// **This is arithmetic, not behaviour, and that is why it needs pinning.** The
/// old value of 8 was not wrong in isolation — it was wrong against
/// `service.yaml`'s `maxScale: 4` and a `db-f1-micro`'s default
/// `max_connections` of 25, two numbers that live in different files and neither
/// of which is visible from here. Nothing failed; the ceiling was simply
/// exceeded on paper, and the observed 30-day peak of 10 backends against a
/// single instance says the margin was already gone.
///
/// So the test states the relationship, and fails if someone raises the pool
/// without moving the tier.
void main() {
  // From infra/gcp/service.yaml — `autoscaling.knative.dev/maxScale`.
  const maxScale = 4;

  // Cloud SQL default for a db-f1-micro (0.6 GB): no `databaseFlags` override
  // is set on `myweli-db`, verified against the live instance.
  const instanceMaxConnections = 25;

  // Postgres keeps `superuser_reserved_connections` back for superusers, so the
  // application user never gets the full number.
  const superuserReserved = 3;
  const usable = instanceMaxConnections - superuserReserved;

  test('a fully scaled-out revision stays inside the usable ceiling', () {
    expect(
      kMaxConnectionsPerInstance * maxScale,
      lessThanOrEqualTo(usable),
      reason:
          'maxScale=$maxScale instances × $kMaxConnectionsPerInstance '
          'connections must fit in $usable usable slots. Raise the Cloud SQL '
          'tier before raising this.',
    );
  });

  test('a realistic rolling deploy fits', () {
    // `maxScale` is per REVISION, so a deploy runs two revisions at once. The
    // realistic shape is the NEW revision scaling to maxScale while the OLD one
    // drains at `minScale` — five instances, not eight.
    //
    // DELIBERATELY the LAUNCH value, not today's: prod temporarily runs
    // minScale 0 (pre-launch economy, LAUNCH.md §6.5 flips it back), and 0
    // would only WEAKEN this bound — testing the stricter launch posture
    // means the flip-back cannot break the connection math unnoticed.
    const minScale = 1;
    expect(
      kMaxConnectionsPerInstance * (maxScale + minScale),
      lessThanOrEqualTo(usable),
      reason: 'a deploy must not be the thing that exhausts the database',
    );
  });

  test('the pathological rollout is over the ceiling, knowingly', () {
    // Honesty rather than a tuned assertion: if BOTH revisions were
    // simultaneously at maxScale — 8 instances — the demand would be 32 against
    // 25, and no pool size above 3 avoids that.
    //
    // Accepted, because it requires sustained load on the OLD revision while
    // the new one also scales out, and this service has never approached it:
    // the 30-day peak across the whole instance is 10 backends, with
    // `minScale: 1` and no observed scaling past two instances.
    //
    // The test exists so the number is recorded rather than assumed. If traffic
    // grows to where a rollout genuinely runs both revisions hot, the fix is
    // the instance tier — `db-g1-small` raises max_connections to 50 and RAM to
    // 1.7 GB together — not a smaller pool.
    expect(
      kMaxConnectionsPerInstance * maxScale * 2,
      greaterThan(instanceMaxConnections),
      reason:
          'if this ever starts passing, the tier was raised — update the '
          'constants above and delete this test',
    );
  });

  test('the pool is still large enough to be a pool', () {
    // A guard in the other direction: 1 would serialise every request behind a
    // single connection, and the slot engine issues concurrent queries.
    expect(kMaxConnectionsPerInstance, greaterThanOrEqualTo(4));
  });
}
