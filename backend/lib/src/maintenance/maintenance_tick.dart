/// The daily housekeeping (`POST /internal/cron/maintenance`, job
/// `myweli-maintenance` at 03:30 UTC): two security prunes, the kept answers'
/// prune and the demo-salon reset. They rode the subscriptions cron until a
/// fourth arrived — the rule its comment set — and moved here together
/// (docs/design/infra-cron-maintenance.md).
///
/// **The tasks are handed in, not looked up**, so the order, the counts and the
/// failures are testable without a database or a clock. The composition root
/// (`dependencies.dart`) builds it with the real ones and their windows.
class MaintenanceTick {
  MaintenanceTick({
    required this.pruneThrottle,
    required this.pruneRateLimits,
    required this.pruneIdempotency,
    required this.demoReset,
  });

  /// `admin_login_throttle` (migration 0035). **A security parameter**, not
  /// housekeeping: the prune is what gives a lockout counter its decay
  /// (docs/design/backend-admin-login-throttle.md).
  final Future<int?> Function() pruneThrottle;

  /// `identity_rate_limits` (0034): every new client address writes a row
  /// since the per-IP auth buckets, so without this the table only grows
  /// (docs/design/infra-cloudflare-front-door.md §4). `null` = the prune
  /// failed and said so on one line.
  final Future<int?> Function() pruneRateLimits;

  /// `idempotency_keys` (0040): 24 h is a promise of
  /// docs/design/write-idempotency.md §6 — the kept answers may hold what a
  /// booking answered. `null` = the prune failed and said so on one line.
  final Future<int?> Function() pruneIdempotency;

  /// The demo-salon reset (T69), due-gated to every 7 days inside its service:
  /// a no-op six days out of seven. Answers WHY it did not run — `not_due`,
  /// `no_snapshot`, `refused:not_demo_owned` — or `ran` (B6.9). A throw is
  /// left to escape — a 500 the cron alert sees, exactly as when it rode the
  /// subscriptions cron.
  final Future<String> Function(DateTime now) demoReset;

  /// Runs the four, in the order they ran before the move, and answers each
  /// count as it came: **a prune nobody can see is the shape this repo keeps
  /// finding**, so every outcome is in the response, not only in a log.
  Future<Map<String, Object?>> run(DateTime now) async {
    final throttle = await pruneThrottle();
    final windows = await pruneRateLimits();
    final keys = await pruneIdempotency();
    final demo = await demoReset(now);
    return {
      'throttleRowsPruned': throttle,
      'rateLimitWindowsPruned': windows,
      'idempotencyKeysPruned': keys,
      'demoReset': demo,
    };
  }
}
