/// The POLICY: which surfaces are limited, and at what number.
///
/// Separate from `rate_limiter.dart`, which is the MECHANISM. The limiter takes
/// a limit and a window as parameters precisely so it never has to know that
/// bookings or uploads exist; this file is where that knowledge lives, and it is
/// the only file to edit when a number turns out to be wrong.
///
/// Design: docs/design/backend-identity-rate-limits.md §5
library;

/// Per-identity ceilings, per hour.
typedef IdentityLimits = ({
  int booking,
  int reviewSubmit,
  int signGallery,
  int signReview,
  int signKyc,
  int signDeposit,
  int signAvatar,
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
);

/// One hour, for every surface in v1.
///
/// An hourly-only booking limit still permits 240/day, and a second daily window
/// is the natural extension — [RateLimiter.hit] already takes the window as a
/// parameter, so adding one is strictly additive. Shipping a single window keeps
/// it to one row per identity per hour, one mechanism, one test. Recorded as an
/// open question rather than a gap.
const Duration kIdentityWindow = Duration(hours: 1);

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

/// The ceiling for a validated upload [purpose].
int signLimitFor(String purpose, IdentityLimits limits) => switch (purpose) {
  'gallery' => limits.signGallery,
  'review' => limits.signReview,
  'kyc' => limits.signKyc,
  'deposit' => limits.signDeposit,
  _ => limits.signAvatar,
};
