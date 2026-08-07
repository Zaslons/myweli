/// The production OTP-disclosure seam (Q1b).
///
/// **This is the only place in the codebase where production may hand an OTP
/// back over HTTP.** It exists so the Q1 funnel smoke — 47 assertions over real
/// HTTP — can act as the acceptance gate for a deployment, which
/// `docs/design/infra-gcp-migration.md` §8 requires and which was not possible
/// before: the harness reads `devCode`, and production suppresses it
/// (`auth_repository.dart:224`).
///
/// That suppression is correct and is **not** weakened here. Instead disclosure
/// requires two independent conditions, and the second is the load-bearing one.
///
/// Design + threat model (T36): docs/design/backend-q1b-smoke-seam.md.
library;

/// Reserved by **RFC 2606 §2** and guaranteed never to be delegated in the
/// public DNS — an address here can never receive mail, so it can never be a
/// real person's address.
///
/// **A compile-time constant on purpose.** If this were configurable, an
/// operator error could widen it to a real domain; as written, no value of any
/// environment variable can make `owner@gmail.com` disclosable. That is what
/// bounds the blast radius if [smokeDisclosureAllowed]'s secret ever leaks:
/// the holder can authenticate as throwaway identities at an unroutable domain,
/// and nothing else.
const String kSmokeIdentitySuffix = '.test';

/// Below this, a configured secret is treated as **absent** — so
/// `SMOKE_OTP_SECRET=test` cannot enable disclosure in production.
const int kMinSmokeSecretLength = 32;

/// Whether this request may receive the OTP inline **in production**.
///
/// False means the seam is *absent*, not merely closed: with `SMOKE_OTP_SECRET`
/// unset there is no behavioural change anywhere, which is how production runs
/// except while a cutover gate is being executed.
///
/// Off-prod behaviour does not route through here at all — `devCode` is still
/// echoed unconditionally, so CI and local development need no secret.
bool smokeDisclosureAllowed({
  required String? configuredSecret,
  required String? providedSecret,
  required String identifier,
}) {
  final configured = configuredSecret?.trim();
  // Absent, blank, or too weak to be worth honouring.
  if (configured == null || configured.length < kMinSmokeSecretLength) {
    return false;
  }

  final provided = providedSecret?.trim();
  if (provided == null || provided.isEmpty) return false;
  if (!constantTimeEquals(configured, provided)) return false;

  // `endsWith`, never `contains`: a substring test would accept
  // `x@smoke.test.evil.com`, an attacker-controlled domain.
  return identifier.toLowerCase().endsWith(kSmokeIdentitySuffix);
}

/// Compares two strings without short-circuiting on the first difference.
///
/// A plain `==` returns as soon as it finds a mismatch, so response time leaks
/// how many leading characters an attacker has guessed — which turns a
/// brute-force over the whole secret into a character-at-a-time search.
///
/// The length check below is deliberately allowed to short-circuit: the length
/// of a secret is not the secret, and the alternative (comparing against a
/// padded copy) hides a subtler bug for no real gain.
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Injectable wrapper so the seam can be provided through `dart_frog`'s
/// `provider<T>` with a distinct type (a bare `String` would collide with every
/// other string dependency) and stubbed in handler tests.
class SmokeSeam {
  const SmokeSeam(this.secret);

  /// `SMOKE_OTP_SECRET`, or null when the seam is absent.
  final String? secret;

  /// True only in the deliberate, configured case — see
  /// [smokeDisclosureAllowed].
  bool allows({required String? providedSecret, required String identifier}) =>
      smokeDisclosureAllowed(
        configuredSecret: secret,
        providedSecret: providedSecret,
        identifier: identifier,
      );

  /// Whether this seam is switched on at all. Used for the boot-time warning:
  /// a disclosure path quietly left enabled is the failure mode worth
  /// engineering against, so it announces itself in the deploy log.
  bool get isActive => (secret?.trim().length ?? 0) >= kMinSmokeSecretLength;
}
