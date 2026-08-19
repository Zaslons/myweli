/// A per-identity rate limit, shared across instances.
///
/// **Why this exists when Cloud Armor already runs.**
/// `docs/design/backend-rate-limiting.md` §1 measured two gaps on 2026-08-18.
/// The auth one — 23 accepted OTP requests/second from a single client by
/// rotating the identifier — was closed by a per-IP rule at the load balancer.
/// The other row in that table, `Booking routes — no limit of any kind`, was
/// not, and `POST /appointments`, `POST /appointments/{id}/review` and
/// `POST /uploads/sign` still return no 429 of any kind.
///
/// **Why this can enforce when the per-IP limiter deliberately cannot.** §4 of
/// that document keeps layer 2 inert because its KEY is unverified: the app has
/// never resolved a client IP, `X-Forwarded-For` has a different shape in
/// production (behind a load balancer) than on staging (direct), and a limiter
/// that hardcodes a position is either trivially spoofed or lumps all traffic
/// into one bucket. None of that applies to a key the server derives from an
/// HMAC-verified JWT: a caller cannot choose another's `sub` without the
/// signing key, and no two callers collapse together. There is nothing to
/// measure, so there is nothing to wait for.
///
/// It is also a smaller thing to get wrong. A mis-set per-IP threshold locks
/// out everyone behind one address; a mis-set per-identity one locks out one
/// account.
///
/// **This does not replace layer 2**, which still owes the anonymous surface —
/// §1's other finding was 100/100 unauthenticated reads accepted at 42 req/s,
/// and no identity key can touch those.
///
/// Design: docs/design/backend-identity-rate-limits.md
library;

/// The outcome of one attempt against a bucket.
///
/// Carries [hits] and [limit] rather than a bare verdict so a caller can watch
/// a budget FILLING rather than only the moment it is full — the same reason
/// `SendReservation` does, and the reason [warnThreshold] is worth reusing.
typedef RateVerdict = ({bool ok, int hits, int limit});

/// Consumes one unit against an opaque [bucket] and reports where that left it.
///
/// **The limit and the window are parameters, not implementation state** —
/// unlike `SendBudget`, which owns its two ceilings because they belong to the
/// email domain. There are six thresholds here across three unrelated domains,
/// and baking them in would make a security primitive import knowledge of
/// bookings, reviews and uploads.
///
/// **Count attempts, not successes.** Callers consume budget before the work is
/// authorized, because an attacker chooses whether their attempt succeeds and
/// so must not be allowed to choose whether they are counted. A booking refused
/// for `slot_unavailable` leaves no row and still cost the round trip.
abstract interface class RateLimiter {
  Future<RateVerdict> hit(
    String bucket, {
    required int limit,
    required Duration window,
  });

  /// For diagnostics — never a decision, because between reading this and
  /// acting on it another instance may have spent the difference.
  Future<int> used(String bucket, {required Duration window});
}

/// The start of the window [now] falls in, floored to the epoch.
///
/// Epoch-flooring rather than calendar arithmetic so that ANY duration works
/// uniformly and every instance agrees on the boundary without coordinating.
///
/// **This is a fixed window, and that has a stated cost:** at a boundary a
/// caller can spend `2 x limit` across two adjacent windows. `email_send_budget`
/// has the identical property and never says so. If it ever matters the answer
/// is a shorter window, not a sliding one — sliding needs a row per request,
/// which is the write amplification this design exists to avoid.
DateTime windowStart(DateTime now, Duration window) =>
    DateTime.fromMillisecondsSinceEpoch(
      (now.toUtc().millisecondsSinceEpoch ~/ window.inMilliseconds) *
          window.inMilliseconds,
      isUtc: true,
    );

/// In-memory implementation for dev, CI and tests.
///
/// **Not for a deployed service.** Per-instance counters on a `maxScale: 4`
/// service mean N times the budget and a reset on every cold start — the defect
/// `LoginThrottle` and `TeamService._inviteCounts` still carry, recorded at
/// `dependencies.dart`'s `sendBudget` block. It is here so the whole path is
/// exercised without a database, and it is the same shape the Postgres one
/// implements.
class InMemoryRateLimiter implements RateLimiter {
  InMemoryRateLimiter({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, int> _counts = {};

  String _key(String bucket, Duration window) =>
      '$bucket|${windowStart(_clock(), window).toIso8601String()}';

  @override
  Future<RateVerdict> hit(
    String bucket, {
    required int limit,
    required Duration window,
  }) async {
    final k = _key(bucket, window);
    final next = (_counts[k] ?? 0) + 1;
    _counts[k] = next;
    return (ok: next <= limit, hits: next, limit: limit);
  }

  @override
  Future<int> used(String bucket, {required Duration window}) async =>
      _counts[_key(bucket, window)] ?? 0;
}

/// A limiter that cannot answer, and therefore does not refuse.
///
/// **Fail open, deliberately, and it is the opposite call from
/// `UploadVerificationService`** — which fails closed because there, letting an
/// unverified object through means paying for arbitrary bytes: the failure IS
/// the harm. Here every real control still holds without the limiter — slot
/// uniqueness, ownership, the `role == 'user'` gate, the role-to-purpose gate,
/// T61's claim-time size check — so failing open costs a temporarily absent
/// abuse ceiling, while failing closed turns a Postgres blip into nobody being
/// able to book.
class FailOpenRateLimiter implements RateLimiter {
  FailOpenRateLimiter(this._inner, {void Function(String)? log})
    : _log = log ?? print;

  final RateLimiter _inner;
  final void Function(String) _log;

  @override
  Future<RateVerdict> hit(
    String bucket, {
    required int limit,
    required Duration window,
  }) async {
    try {
      return await _inner.hit(bucket, limit: limit, window: window);
    } catch (_) {
      // The bucket, not the exception: a stack trace from the pool says
      // nothing a reader of this line needs, and the bucket says which surface
      // is currently unbounded.
      _log('rate_limit_unavailable bucket=$bucket');
      return (ok: true, hits: 0, limit: limit);
    }
  }

  @override
  Future<int> used(String bucket, {required Duration window}) async {
    try {
      return await _inner.used(bucket, window: window);
    } catch (_) {
      return 0;
    }
  }
}
