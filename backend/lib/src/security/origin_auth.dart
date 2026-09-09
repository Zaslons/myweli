/// The origin gate's configuration — resolved once at boot, pure, testable.
///
/// **Why this exists.** `api.myweli.com` is served by a Cloudflare Worker that
/// forwards to Cloud Run's `*.run.app` hostname
/// (docs/design/infra-cloudflare-front-door.md). For Cloudflare to reach the
/// service, production ingress opens to `all` — which reopens the direct
/// `run.app` door that `ingress: internal-and-cloud-load-balancing` used to
/// close. Anything arriving through that door has bypassed the edge rate limit
/// and could forge `CF-Connecting-IP`, so the origin refuses every request that
/// does not carry the secret header the Worker adds (threat T70). This file is
/// the decision; `origin_front_door.dart` is the enforcement.
///
/// **Why a pure resolver rather than a lazy `final` reading the environment.**
/// The `boot_config` idiom: `Platform.environment` is immutable, so a
/// production fail-fast can only be tested in-process if the raw strings are
/// arguments. Raw values in, a sealed decision out.
///
/// **Why "too short" REFUSES here when `SMOKE_OTP_SECRET` treats it as
/// absent.** For the smoke seam a weak secret means the feature stays off,
/// which is the safe direction. For a gate, a weak secret means the door is
/// guarded by something guessable — and treating it as absent would mean the
/// door is open, with the manifest looking configured. Both directions are
/// unsafe, so a short value is refused in every environment, dev included.
library;

/// Minimum length of `ORIGIN_AUTH_SECRET` (the generator in the spec produces
/// 64). Same floor as `kMinSmokeSecretLength`; the difference is what happens
/// below it (see the library comment).
const int kMinOriginAuthSecretLength = 32;

/// The resolved state of the origin gate.
sealed class OriginAuth {}

/// No secret configured off-production: the middleware is inert. Dev, CI's
/// `ENV=dev` jobs and staging (which has no Worker in front of it and keeps
/// its `run.app` door public by design — spec §5.6).
final class OriginAuthOff implements OriginAuth {
  const OriginAuthOff();
}

/// A secret is configured: every request but `GET /health` must carry it.
final class OriginAuthOn implements OriginAuth {
  const OriginAuthOn({required this.secret, required this.mode});

  final String secret;
  final OriginAuthMode mode;
}

/// What a request without the header gets.
///
/// `log` exists ONLY as the bounded rollout state of spec §9 (phase A, while
/// the load balancer still fronts the hostname and the direct door is being
/// counted) and for a secret rotation (§6.2). It is never the default.
enum OriginAuthMode { log, enforce }

/// Resolves `ORIGIN_AUTH_SECRET` + `ORIGIN_AUTH_MODE` into an [OriginAuth].
///
/// The five rules, each a named test in `test/security/origin_auth_test.dart`:
///
/// | secret | mode | prod? | result |
/// |---|---|---|---|
/// | unset/blank | – | no | [OriginAuthOff] |
/// | unset/blank | – | **yes** | `StateError` — once the load balancer is gone an unset secret in production is an open door, and « an unset value is what the guards exist to catch » |
/// | < 32 chars | – | any | `StateError` — see the library comment |
/// | set | unset | any | [OriginAuthOn] in `enforce` — the safe default; `log` must be written down in the manifest to exist |
/// | set | other | any | `StateError` — the `Env.parse` rule: an unknown spelling never silently means something |
///
/// Every message names the VARIABLE and never its value: the boot check prints
/// them into one aggregated log line.
OriginAuth resolveOriginAuth(
  String? secret,
  String? mode, {
  required bool isProd,
}) {
  // The mode is parsed even when the secret is absent: a misspelled
  // `ORIGIN_AUTH_MODE` on a target that will later gain the secret would
  // otherwise be discovered on the day the secret lands, not today.
  final parsedMode = _parseMode(mode);

  final s = secret?.trim();
  if (s == null || s.isEmpty) {
    if (isProd) {
      throw StateError(
        'ORIGIN_AUTH_SECRET is not set. Production ingress is open to all so '
        'that Cloudflare can reach the service, and this secret is the only '
        'thing that closes the direct run.app door. Refusing to serve without '
        'it (docs/design/infra-cloudflare-front-door.md §5.2).',
      );
    }
    return const OriginAuthOff();
  }
  if (s.length < kMinOriginAuthSecretLength) {
    throw StateError(
      'ORIGIN_AUTH_SECRET is shorter than $kMinOriginAuthSecretLength '
      'characters. Unlike SMOKE_OTP_SECRET, a weak value here is not "feature '
      'off" but "door guarded by something guessable", so it is refused in '
      'every environment. Generate one with the command in '
      'docs/design/infra-cloudflare-front-door.md §6.2.',
    );
  }
  return OriginAuthOn(secret: s, mode: parsedMode);
}

OriginAuthMode _parseMode(String? raw) {
  final v = raw?.trim().toLowerCase();
  if (v == null || v.isEmpty) return OriginAuthMode.enforce;
  return switch (v) {
    'log' => OriginAuthMode.log,
    'enforce' => OriginAuthMode.enforce,
    _ => throw StateError(
      'ORIGIN_AUTH_MODE is not a known mode — use "log" or "enforce" (unset '
      'means enforce). An unrecognised spelling is refused rather than '
      'defaulted, so a typo cannot silently pick a mode.',
    ),
  };
}
