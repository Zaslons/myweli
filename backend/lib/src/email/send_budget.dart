/// The classes of outbound mail, and why there are exactly two.
///
/// **A single global ceiling would be worse than none.** An attacker exhausts
/// it in a minute, and every legitimate email for the rest of the window is
/// dropped — booking confirmations, subscription notices, invitations. Spam
/// prevention becomes a cheaper availability attack: the attacker no longer
/// needs volume, only to be first.
///
/// The split is by **who chose the recipient**.
enum EmailClass {
  /// An anonymous caller picked the address. OTP to anything someone types.
  /// This is the entire attack surface, and it gets the tight ceiling.
  cold,

  /// An authenticated actor, about their own thing — a salon's subscription
  /// notice, an invitation to its own colleague. Starving these is the DoS
  /// above, so the ceiling here guards against a loop in our own code, not
  /// against an attacker.
  warm;

  String get bucket => name;
}

/// Reserves room to send, atomically, across every instance.
///
/// Design: docs/design/backend-email-send-budget.md §3.
abstract interface class SendBudget {
  /// Consumes one unit and reports where that left the budget.
  ///
  /// **Reserve-before-send.** A failed send still consumes budget, which is the
  /// correct direction: a provider outage must not become an unbounded retry
  /// loop, and over-counting fails closed.
  Future<SendReservation> reserve(EmailClass cls);

  /// For diagnostics — never a decision, because between reading this and
  /// acting on it another instance may have spent the difference.
  Future<int> used(EmailClass cls);
}

/// The outcome of one reservation.
///
/// It carries [sent] and [ceiling] rather than a bare verdict so a caller can
/// watch the budget FILLING, not only the moment it is full. That distinction
/// is the whole value of the warning below: an alarm that fires on exhaustion
/// arrives after users have already been turned away.
typedef SendReservation = ({bool ok, int sent, int ceiling});

/// The fill level worth a warning: 80% of the ceiling.
///
/// Callers compare with `==`, never `>=`, so exactly ONE reservation per window
/// per class crosses it and the log line cannot become a flood. That is safe
/// across instances precisely because of how [SendBudget.reserve] is
/// implemented: the upsert hands each caller a distinct post-increment value,
/// so the 48th send is seen by exactly one request, whichever instance it
/// landed on.
///
/// A ceiling below 5 yields 0 and therefore never warns, since `sent` starts at
/// 1 — deliberate, because at that size exhaustion is the only signal that
/// means anything.
int warnThreshold(int ceiling) => ceiling * 4 ~/ 5;

/// Ceilings, in sends per hour.
typedef SendCeilings = ({int cold, int warm});

/// Today's real volume is ~37 `/auth/*` requests in SEVEN DAYS, so 60/hour is
/// roughly 100x headroom for launch while bounding a runaway to 1,440/day
/// rather than two million. `warm` is deliberately far higher: it must never be
/// the thing that drops a booking confirmation.
const SendCeilings kDefaultCeilings = (cold: 60, warm: 1000);

/// In-memory implementation for dev, CI and tests.
///
/// **Not for a deployed service** — see the migration's comment. It is here so
/// the whole path is exercised without a database, and it is the same shape the
/// Postgres one implements.
class InMemorySendBudget implements SendBudget {
  InMemorySendBudget({
    this.ceilings = kDefaultCeilings,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SendCeilings ceilings;
  final DateTime Function() _clock;
  final Map<String, int> _counts = {};

  String _key(EmailClass c) {
    final n = _clock().toUtc();
    return '${c.bucket}|${DateTime.utc(n.year, n.month, n.day, n.hour).toIso8601String()}';
  }

  int _ceiling(EmailClass c) =>
      c == EmailClass.cold ? ceilings.cold : ceilings.warm;

  @override
  Future<SendReservation> reserve(EmailClass cls) async {
    final k = _key(cls);
    final next = (_counts[k] ?? 0) + 1;
    _counts[k] = next;
    final ceiling = _ceiling(cls);
    return (ok: next <= ceiling, sent: next, ceiling: ceiling);
  }

  @override
  Future<int> used(EmailClass cls) async => _counts[_key(cls)] ?? 0;
}
