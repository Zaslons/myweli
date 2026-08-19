/// The admin-login failure lockout: after [LoginThrottle.maxAttempts] failures a
/// key is refused for a further [LoginThrottle.lockout].
///
/// **Not a rate limit, and the difference is why `RateLimiter` is not reused.**
/// A lockout is a penalty measured from the triggering failure; a rate limit is
/// a budget measured from the clock. Five failures at 10:59:50 would be
/// forgiven at 11:00:00 by an hourly window, and that window's documented
/// `2 x limit` boundary property would hand out nine consecutive guesses
/// against a budget of five. `RateLimiter` also has no `reset` — adding one
/// would put an attacker-callable budget refund on booking and uploads, where
/// nothing gates it — and its only decision-grade call increments, while
/// [isLocked] must be a pure read taken BEFORE bcrypt.
///
/// Design: docs/design/backend-admin-login-throttle.md
library;

/// Five failures, then fifteen minutes.
///
/// Carried over from the in-memory original deliberately rather than revisited:
/// this change is about WHERE the state lives, and moving the numbers at the
/// same time would make a regression indistinguishable from a policy change.
/// Not environment-configurable, unlike the send budget's ceilings — the
/// argument there is that a launch changes the right number, and 5-in-15 for a
/// staff password is not a number launch traffic moves.
const int kDefaultMaxAttempts = 5;
const Duration kDefaultLockout = Duration(minutes: 15);

/// The throttle key, in one place so a third call site cannot drift.
///
/// Dropping `.toLowerCase()` silently doubles the guess budget — `Admin@x` and
/// `admin@x` become separate keys — which is a mutation worth watching go red.
String adminThrottleKey(String email) => email.trim().toLowerCase();

/// Runs a throttle operation, returning `null` if the store could not answer.
///
/// **Fail CLOSED is the caller's job, and these are what make it one line.** The
/// booking limiter fails open, and its justification does not transfer: there,
/// *"every real control still holds without the limiter"* — slot uniqueness,
/// ownership, the role gates. Here the password and this throttle are the
/// complete control set, so letting a store failure through would remove the
/// only brute-force bound on the staff credential, silently.
///
/// The objection — *"then a database incident locks every admin out"* — mostly
/// dissolves: the throttle and the `admins` table share one pool, so a TOTAL
/// outage already blocks login whatever this returns. Only PARTIAL failure
/// differs, and there the choice is between an unavailable internal console and
/// unlimited silent guessing.
///
/// A `null` must become a code of its OWN, never `locked_out`: conflating "you
/// guessed too often" with "our database is sick" is the defect
/// `storageUnavailable()` exists to prevent.
Future<T?> throttleValue<T>(Future<T> Function() op) async {
  try {
    return await op();
  } catch (_) {
    return null;
  }
}

/// The `void` twin of [throttleValue] — reports whether the write landed.
///
/// Separate because a `Future<void>` makes `T` void, and `void` cannot be
/// compared to null. Two small functions rather than one clever one.
Future<bool> throttleOk(Future<void> Function() op) async {
  try {
    await op();
    return true;
  } catch (_) {
    return false;
  }
}

/// Refuses a key that has failed too often, and forgives one that succeeds.
abstract interface class LoginThrottle {
  /// Whether [key] is currently locked. **A pure read**, consulted before the
  /// password is verified, so a locked caller costs no bcrypt and learns
  /// nothing about the account.
  Future<bool> isLocked(String key);

  /// Counts one failure, and locks once the count reaches `maxAttempts`.
  ///
  /// Called for **unknown addresses too**, deliberately: if only real admin
  /// addresses were counted, `locked_out` would appear only for them and the
  /// endpoint would become an admin-address oracle.
  Future<void> recordFailure(String key);

  /// Forgives everything for [key].
  ///
  /// Called only after a SUCCESSFUL password check, which is what makes it
  /// safe — the caller paid the credential to earn it. Without it, a wrong
  /// password on Monday and another on Friday accumulate toward a lockout
  /// across weeks.
  Future<void> reset(String key);
}

/// In-memory implementation for dev, CI and tests.
///
/// **Not for a deployed service.** Per-instance counters on a `maxScale: 4`
/// service mean N times the budget and a reset on every cold start — which for
/// a lockout on the only staff credential meant roughly 20 guesses per 15
/// minutes, forgiven by any scale-down. This class *was* the production
/// implementation, and its old doc comment ("move to a shared store if the API
/// is ever horizontally scaled") is the deadline-in-a-comment that
/// `migrations.dart` and `dependencies.dart` both cite as the cautionary tale.
///
/// Behaviour is byte-for-byte what it always was; only the signatures are
/// async, so the Postgres one can implement the same interface.
class InMemoryLoginThrottle implements LoginThrottle {
  InMemoryLoginThrottle({
    this.maxAttempts = kDefaultMaxAttempts,
    this.lockout = kDefaultLockout,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration lockout;
  final DateTime Function() _clock;
  final Map<String, ({int count, DateTime? until})> _state = {};

  @override
  Future<bool> isLocked(String key) async {
    final s = _state[key];
    if (s?.until == null) return false;
    // Lazy expiry, and it clears the COUNT as well as the lock — which is what
    // makes the counter restart at 1 afterwards rather than at N+1.
    if (_clock().toUtc().isAfter(s!.until!)) {
      _state.remove(key);
      return false;
    }
    return true;
  }

  @override
  Future<void> recordFailure(String key) async {
    final count = (_state[key]?.count ?? 0) + 1;
    _state[key] = (
      count: count,
      until: count >= maxAttempts ? _clock().toUtc().add(lockout) : null,
    );
  }

  @override
  Future<void> reset(String key) async => _state.remove(key);
}
