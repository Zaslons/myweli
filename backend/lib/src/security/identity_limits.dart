/// The POLICY: which surfaces are limited, and at what number.
///
/// Separate from `rate_limiter.dart`, which is the MECHANISM. The limiter takes
/// a limit and a window as parameters precisely so it never has to know that
/// bookings or uploads exist; this file is where that knowledge lives, and it is
/// the only file to edit when a number turns out to be wrong.
///
/// Design: docs/design/backend-identity-rate-limits.md §5
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'rate_limiter.dart';

/// Per-identity ceilings, per hour.
typedef IdentityLimits = ({
  int booking,
  int reviewSubmit,
  int signGallery,
  int signReview,
  int signKyc,
  int signDeposit,
  int signAvatar,
  int signLogo,
});

/// **These are guesses, and saying so is the point.** Production holds 0
/// appointments, 0 salons and 5 users, so there is no volume to calibrate
/// against — the same position that made the Cloud Armor rule ship enforcing
/// rather than in preview, because preview would have learnt nothing while the
/// hole stayed open.
///
/// The sizing principle differs from the email budget's. `kDefaultCeilings.cold`
/// is ~100x real volume because it is GLOBAL and must absorb every user at once.
/// These are per-identity, so each only has to absorb one determined human.
///
/// - `booking` 10 — a real consumer books one appointment. The extreme honest
///   case, booking for a family while retrying through a bad mobile connection,
///   is maybe five. Against the measured pathology (23 accepted requests per
///   SECOND) this is roughly an 8,000x reduction.
/// - `reviewSubmit` 5 — the highest per-request cost by a wide margin: an upsert
///   plus `recomputeRatings`, which is two aggregates and a `providers` write on
///   a `db-f1-micro`. Honest volume is about one per completed visit, ever.
/// - `signGallery` 60 — the genuinely bursty legitimate case, a salon loading a
///   portfolio in one sitting.
/// - `signReview` 40 — **and this number is the interesting one.** A review may
///   carry up to six photos (`ReviewsService._maxPhotos`). At a naive 20, a user
///   submitting five reviews — exactly the `reviewSubmit` ceiling — needs up to
///   thirty signs and would be refused by a limit they never approached on the
///   surface they were using. **Two individually generous limits can compose
///   into a lockout**, and that produces a support ticket nobody can diagnose.
/// - `signKyc` / `signDeposit` / `signAvatar` 10 — a handful of documents, one
///   proof per booking, one photo; each with room to retry.
const IdentityLimits kDefaultIdentityLimits = (
  booking: 10,
  reviewSubmit: 5,
  signGallery: 60,
  signReview: 40,
  signKyc: 10,
  signDeposit: 10,
  signAvatar: 10,
  // One logo, room to retry — the avatar's sizing logic. A salon changes its
  // brand mark rarely; ten an hour is generous headroom, not a workflow.
  signLogo: 10,
);

/// One hour, for every surface in v1.
///
/// An hourly-only booking limit still permits 240/day, and a second daily window
/// is the natural extension — [RateLimiter.hit] already takes the window as a
/// parameter, so adding one is strictly additive. Shipping a single window keeps
/// it to one row per identity per hour, one mechanism, one test. Recorded as an
/// open question rather than a gap.
const Duration kIdentityWindow = Duration(hours: 1);

/// How long the daily prune keeps a window (`routes/internal/cron/subscriptions.dart`).
///
/// **Load-bearing since the invite buckets.** A window survives the prune only
/// while its START is newer than `now - kRateLimitRetention`; the hourly
/// buckets clear that by 23 hours, the daily invite buckets by nothing — a
/// one-day window starts at most one day ago, so it survives exactly.
/// `rate_limiter_test` pins kIdentityWindow, kInviteWindow and kIpAuthWindow
/// to this ceiling; a NEW window longer than a day must join that test, or
/// the prune deletes it mid-window.
const Duration kRateLimitRetention = Duration(days: 1);

/// Team invitations, per DAY (threat T37): per salon, and per salon and
/// address. docs/design/backend-team-invite-caps.md
typedef InviteLimits = ({int perSalon, int perAddress});

/// - `perSalon` 20 — the number the process-local counter carried since R2b,
///   now shared by every instance instead of granted to each of them.
/// - `perAddress` 3 — an honest owner re-invites one person after a mistake
///   (wrong role, revoked by accident), not three times in a day. Each
///   invitation carries at most four emails (itself and three resends), so
///   one mailbox receives at most 3 × 4 = 12 a UTC day from one salon, plus up
///   to 3 resends of an invitation sent the day before — 15.
const InviteLimits kDefaultInviteLimits = (perSalon: 20, perAddress: 3);

/// One day, floored to the epoch — midnight UTC, which is midnight in Abidjan.
const Duration kInviteWindow = Duration(days: 1);

/// The salon's daily invitation bucket. [providerId] comes from the server's
/// own salon resolution, never from the request body — a closed set.
String inviteSalonBucket(String providerId) => 'invite:salon:$providerId';

/// The (salon, address) daily bucket.
///
/// **Pseudonymous, not secret.** The address never appears in clear — not in
/// `identity_rate_limits`, and not in the `rate_limited bucket=…` line logged
/// on every refusal — and the salon id is inside the hashed input, so one
/// address gives a different digest in each salon. But the hash is unkeyed:
/// someone holding a CANDIDATE address can confirm it for a given salon. That
/// is the stated goal (no contact data in the logs), not anonymity.
///
/// Keyed on [canonicalInviteAddress], so the aliases of one mailbox share a
/// bucket. [emailKey] must already be trimmed and lowercased.
///
/// An OPEN set — any address — which is why the service hits
/// [inviteSalonBucket] first: a salon refused there writes no address row.
String inviteAddressBucket(String providerId, String emailKey) {
  final canonical = canonicalInviteAddress(emailKey);
  final digest = sha256.convert(utf8.encode('$providerId\n$canonical'));
  return 'invite:addr:$providerId:${digest.toString().substring(0, 32)}';
}

/// The mailbox behind an address, for COUNTING only — what is stored and
/// sent stays exactly what the owner typed.
///
/// A `+tag` is dropped for every domain (most providers deliver
/// `ama+x@…` to `ama@…`; where one does not, two addresses differing only by
/// a tag share a bucket — a tighter cap, never a looser one), and Gmail
/// ignores dots in the local part and answers to `googlemail.com` too.
/// Without this, `victim+1@gmail.com`, `v.ictim@gmail.com`, … were each a
/// fresh bucket, and the per-address cap bounded nothing (found in review).
/// Catch-all or custom-alias domains remain out of reach; the salon cap
/// bounds them. docs/design/backend-team-invite-caps.md §5.1
String canonicalInviteAddress(String emailKey) {
  final at = emailKey.lastIndexOf('@');
  if (at <= 0) return emailKey;
  var local = emailKey.substring(0, at);
  var domain = emailKey.substring(at + 1);
  final plus = local.indexOf('+');
  if (plus > 0) local = local.substring(0, plus);
  if (domain == 'gmail.com' || domain == 'googlemail.com') {
    local = local.replaceAll('.', '');
    domain = 'gmail.com';
  }
  return '$local@$domain';
}

/// The bucket for a booking attempt.
///
/// **Deliberately omits the role.** Including it could only ever SPLIT a budget,
/// never merge one, and splitting is a weakening. Consumer ids are minted
/// `user_…` and provider account ids `provider_…`, so the prefixes are already
/// disjoint and the role adds no information. It also stays correct whichever
/// way the missing role gate on `POST /appointments` is eventually resolved.
String bookingBucket(String sub) => 'book:$sub';

/// The bucket for a review submission. Unambiguous — the route hard-gates
/// `role == 'user'`, so [sub] is always a consumer id.
///
/// **Not per-appointment.** That would let a user with N completed appointments
/// multiply by N, and the expensive part — `recomputeRatings` — is per-PROVIDER,
/// not per-appointment.
String reviewBucket(String sub) => 'review:$sub';

/// The bucket for an upload signature.
///
/// **[purpose] must already be validated when this is called.** It arrives from
/// the client and `UploadSigningService` checks it against a closed set of five
/// literals; building the key before that check would let an attacker send a
/// fresh random purpose per request, which both evaporates the limit and makes
/// every miss write a new row — turning the limiter into the amplifier they
/// wanted. **A rate-limit key may only be built from a closed set.**
///
/// **Includes the purpose**, unlike the role in [bookingBucket], and for a
/// reason that does not apply there: the five purposes are gated to disjoint
/// role sets and have wildly different honest volumes. Splitting lets each carry
/// its own number rather than a share of a total.
///
/// **The salon id is deliberately not the key for `gallery`** — it would make a
/// whole salon team share one budget, so a colleague's portfolio upload would
/// refuse yours. Bounding storage cost is T61's job, at claim time.
String signBucket(String purpose, String sub) => 'sign:$purpose:$sub';

/// The fill level worth a warning: 80% of the ceiling.
///
/// A deliberate twin of `warnThreshold` in `email/send_budget.dart` rather than
/// an import of it: a security primitive should not reach into the email domain
/// for one line of arithmetic, and moving the original would touch code that is
/// live in production. Same rule of three as the counter table — if a third
/// caller appears, extract it then.
int warnAt(int limit) => limit * 4 ~/ 5;

/// Consumes one unit against [bucket] and reports whether to proceed.
///
/// **The 80% line is the half that arrives in time.** A ceiling that only
/// announces itself on exhaustion tells you a user was refused; this one tells
/// you a threshold is wrong while everything still works. Compared with `==`,
/// never `>=`, so it fires exactly once per bucket per window — safe across
/// instances precisely because the upsert hands each caller a distinct
/// post-increment value.
///
/// A null [limiter] means no limit — the shape that lets every existing
/// construction site keep compiling, and the reason `dependencies.dart` has a
/// source-level test proving it supplies one.
///
/// [window] defaults to the hourly [kIdentityWindow]; the invite buckets pass
/// [kInviteWindow]. [warn] turns the 80% line off for a ceiling so small that
/// 80% is an honest everyday count (`warnAt(3) == 2`: the per-address invite
/// bucket would page on every second invitation of one person).
Future<bool> allowUnderLimit(
  RateLimiter? limiter,
  String bucket,
  int limit, {
  void Function(String)? log,
  Duration window = kIdentityWindow,
  bool warn = true,
}) async {
  if (limiter == null) return true;
  final v = await limiter.hit(bucket, limit: limit, window: window);
  final emit = log ?? print;
  if (!v.ok) {
    // **The refusal, and it is not symmetric with the warning above.**
    //
    // The warning fires once per window, because its job is to say "a threshold
    // is close" and repeating that is noise. This fires EVERY time, because its
    // job is to say "someone was turned away" — and the count is the whole
    // signal. One line in an hour is a person who hit a ceiling; three hundred
    // is an attacker the limit is holding.
    //
    // **Why this matters more than it looks.** The per-identity limits can be
    // provoked on staging, where the Q1b seam can mint a token, and NOT on
    // production, where that seam is deliberately absent — a standing
    // OTP-disclosure path on the real thing is a permanent invitation, and it
    // was removed on purpose. So production cannot be probed, and without this
    // line a limit that fires there would be invisible: the caller sees a 429,
    // and we see nothing. Observability is what replaces the probe.
    emit('rate_limited bucket=$bucket hits=${v.hits} limit=${v.limit}');
  }
  // `v.hits > 0` guards the FAIL-OPEN verdict, which fabricates `hits: 0`
  // without having counted anything. With every shipped ceiling `warnAt` is at
  // least 4, so 0 can never equal it — but a ceiling of 0 or 1 makes
  // `warnAt` == 0, and every failed hit during a database outage would then
  // announce a threshold nobody crossed. The ceilings are settable from the
  // environment, so that is a configuration away rather than a code change.
  if (warn && v.hits > 0 && v.hits == warnAt(v.limit)) {
    // The bucket carries a pseudonymous id, not contact data — unlike the send
    // budget's recipient, which its own test forbids logging. It is also the
    // only actionable field: without it the line says a threshold is close and
    // not whose.
    emit('rate_limit_warning bucket=$bucket hits=${v.hits} limit=${v.limit}');
  }
  return v.ok;
}

/// The ceiling for a validated upload [purpose].
int signLimitFor(String purpose, IdentityLimits limits) => switch (purpose) {
  'gallery' => limits.signGallery,
  'review' => limits.signReview,
  'kyc' => limits.signKyc,
  'deposit' => limits.signDeposit,
  // Explicit, though the default arm would return the same NUMBER today: a
  // new purpose silently inheriting the avatar ceiling is the trap this
  // switch's shape invites, and the wiring test pins signLogo != signAvatar
  // in its fixture precisely so this arm cannot be deleted unnoticed.
  'logo' => limits.signLogo,
  _ => limits.signAvatar,
};
