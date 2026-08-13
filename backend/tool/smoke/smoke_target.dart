/// Which server the funnel smoke harness is allowed to point at.
///
/// **This harness WRITES.** It creates users, salons and bookings, and in phase
/// 7 it **suspends a salon**. Today one hostname is plausible, so a wrong
/// `SMOKE_BASE_URL` is theoretical. Staging creates a second, and the moment two
/// plausible values exist, a transposed one points a salon-suspending test at
/// production — an action with real consequences and no undo button in CI.
///
/// So the rule is enforced here rather than in the workflow that happens to call
/// it. A workflow-level check protects one caller; this protects every caller,
/// including a laptop — and the realistic accident is someone running the
/// documented command with a copied URL, a path that never touches CI at all.
/// Design: docs/design/infra-staging.md §3.4.
///
/// ## Production was once a legitimate target, and this does not pretend otherwise
///
/// The Q1b smoke seam (`docs/design/backend-q1b-smoke-seam.md`) exists precisely
/// so this harness *could* authenticate against `ENV=prod`, as the one-time
/// acceptance gate for the Cloud Run cutover. That gate has served its purpose,
/// and the same document's §7 recorded the follow-up as a decision owed: the
/// harness creates a salon, services, staff and bookings, so as a *recurring*
/// gate against production it leaves junk in the real marketplace, and option 3
/// was "move the recurring gate to a staging database once one exists."
///
/// One now does. So this file resolves that decision: **the recurring gate runs
/// against staging.** Running it against production again is not impossible, it
/// is *deliberate* — it takes an edit to this file, reviewed, exactly as
/// mounting `SMOKE_OTP_SECRET` into `service.yaml` takes an edit, reviewed.
/// There is no environment variable that unlocks it, because an override is
/// simply the bypass with extra steps.
library;

/// Hosts the harness may target — **deny by default**, like everything else in
/// this codebase's security model. A denylist would have to enumerate every
/// production address that exists now and every one added later; this states the
/// two shapes that are legitimate and refuses the rest.
///
///   · **loopback** — CI boots its own server on `localhost:<port>`, and so does
///     a developer.
///   · **the staging Cloud Run service** — a `*.run.app` host whose service name
///     is `myweli-api-staging` (see infra/gcp/service-staging.yaml).
///
/// Both of production's addresses fall out as refusals rather than as entries in
/// a list that could go stale: `api.myweli.com` is not `.run.app`, and
/// production's own `myweli-api-<suffix>.…run.app` does not carry the `-staging`
/// service name. Production's ingress makes that second address unreachable
/// anyway — but a guard that depends on a *separate* setting staying correct is
/// the kind that stops working quietly, so it is not relied on here.
String resolveSmokeBaseUrl(String? raw) {
  // Fail-closed. An unset base URL must stop the run, never quietly pass: a
  // smoke that skips itself is worse than no smoke, because the job stays green
  // and nobody looks again.
  if (raw == null || raw.trim().isEmpty) {
    throw StateError(
      'SMOKE_BASE_URL is unset. This harness asserts against a running server; '
      'refusing to pass vacuously.',
    );
  }
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw StateError(
      'SMOKE_BASE_URL="$trimmed" is not an absolute URL with a host.',
    );
  }
  if (!_isPermittedHost(uri.host)) {
    throw StateError(
      'SMOKE_BASE_URL="$trimmed" is not a permitted target.\n'
      'This harness WRITES — it creates users, salons and bookings, and it '
      'SUSPENDS a salon. It may only run against a loopback server or the '
      'staging Cloud Run service (a *.run.app host named myweli-api-staging). '
      'Everything else, production included, is refused by default.',
    );
  }
  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// The environments the harness may write to, as the **target itself reports
/// them** on `GET /health`.
///
/// The host rule above is a check on the *spelling* of the target. It cannot see
/// an IP literal, a CNAME, a tunnel, or a staging-looking hostname pointed at
/// the production service — and the consequence of being wrong is real rows in
/// the real marketplace. This is the same rule asked of the server instead of
/// the string, and it lives beside the host rule so that re-enabling production
/// is one decision in one file rather than two that can drift apart.
const permittedEnvs = {'dev', 'staging'};

bool _isPermittedHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h == '127.0.0.1' || h == '::1') return true;
  if (!h.endsWith('.run.app')) return false;
  // Cloud Run hostnames are `<service>-<generated>.<region>.run.app` (and the
  // older `<service>-<hash>-<code>.a.run.app`). Either way the service name
  // leads the first label, so a prefix match on the first label identifies the
  // service without depending on which URL form Cloud Run hands back — it
  // publishes two for the same service.
  final firstLabel = h.split('.').first;
  return firstLabel.startsWith('myweli-api-staging');
}
