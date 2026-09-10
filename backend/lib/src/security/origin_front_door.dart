/// The origin gate and the per-IP auth limit — one root middleware.
///
/// **What it closes.** With production ingress open to `all` (so that the
/// Cloudflare Worker can reach Cloud Run), the direct `*.run.app` door is
/// public again. Every request that did not come through the Worker — which
/// adds `X-Myweli-Origin-Auth` from the shared secret — is refused here with
/// 403 `origin_required`, except `GET /health` (threat T70). This is what
/// replaced `ingress: internal-and-cloud-load-balancing`, and what makes the
/// edge rate limit un-bypassable.
///
/// **What it finally enforces.** The per-IP limit on `/auth/*` and
/// `/admin/auth/*` that Cloud Armor used to apply at the load balancer (10 per
/// minute per address — threat T71). `docs/design/backend-rate-limiting.md`
/// §4 kept this layer inert because its key was unverified: the app never knew
/// which `X-Forwarded-For` position to trust. Here the key is verified **by
/// construction**: `CF-Connecting-IP` is read only AFTER the origin header
/// matched, and behind the gate that header was set by Cloudflare on a Worker
/// subrequest the Worker cannot alter. No depth to measure, nothing to wait
/// for. `clientIpFrom` (the depth resolver) stays unwired.
///
/// **Two callbacks, not two values** — the `corsMiddleware` rule: dart_frog
/// builds this chain before the custom entrypoint runs, and a value would
/// evaluate the env-derived `final` here, pre-empting the aggregated boot
/// check that prints every misconfiguration in one line.
///
/// Design: docs/design/infra-cloudflare-front-door.md §5.2
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';

import '../auth/smoke_seam.dart' show constantTimeEquals;
import '../responses.dart';
import 'origin_auth.dart';
import 'rate_limiter.dart';

/// The header the Worker adds to every subrequest, read lowercase (shelf
/// lower-cases header names; the Worker sends `X-Myweli-Origin-Auth`).
const String kOriginAuthHeader = 'x-myweli-origin-auth';

/// Set by Cloudflare itself on every Worker subrequest to a non-Cloudflare
/// origin — « the Worker cannot alter it ». Trusted only after [kOriginAuthHeader]
/// verified, never before: on the direct door anyone can send it.
const String kClientIpHeader = 'cf-connecting-ip';

/// Path-EXACT exemption. Cloud Run's liveness probe GETs `/health` on the
/// container directly (no Worker, no header) every 30 s, and the deploy verify
/// step curls it. A prefix match would exempt `/healthz-anything`.
const String kOriginAuthExemptPath = '/health';

/// Cloud Armor's numbers, carried over: 10 per minute per address.
const int kIpAuthLimit = 10;
const Duration kIpAuthWindow = Duration(minutes: 1);

/// Cloud Armor's two expressions, verbatim (`87-rate-limit-policy.sh` rule
/// 1000 and `89-admin-auth-rate-limit.sh` rule 1100).
bool isIpLimitedPath(String path) =>
    path.startsWith('/auth/') || path.startsWith('/admin/auth/');

/// What of an address is actually keyed on, before hashing.
///
/// **IPv6 is collapsed to its /64.** A residential or cloud IPv6 allocation is
/// a /64 as a rule, which hands an attacker 2^64 distinct addresses for free;
/// keyed on the full address, every request would land in a fresh bucket at
/// 1/10 and the per-source bound would be nothing at all (found in review).
/// One /64 is one subscriber, the mapping the identity-limits design calls
/// « one human, one bucket ». IPv4 is keyed on its canonical dotted form, so
/// two spellings of one address share a bucket. An unparsable string is keyed
/// verbatim — it can only ever be its own bucket.
///
/// The Cloudflare edge rule keys on `ip.src`, the full address; the Free plan
/// offers nothing coarser, so this collapse is the app limiter's alone and the
/// reason it is the authoritative one (spec §5.4, §6.1 T71).
String ipAuthKeySource(String ip) {
  final parsed = InternetAddress.tryParse(ip);
  if (parsed == null) return ip;
  if (parsed.type == InternetAddressType.IPv6) {
    final prefix = parsed.rawAddress.sublist(0, 8);
    return 'v6/64:${prefix.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
  return parsed.address;
}

/// `ip:auth:` + the first 32 hex characters of SHA-256 of [ipAuthKeySource].
///
/// Hashed, so the `identity_rate_limits` column holds a bounded 32-character
/// key whatever the client sends, and no address is stored in clear — the two
/// things the identity-limits design demands of an open-set key (spec §4).
/// The same reason `admin_login_throttle` keys on a digest.
String ipAuthBucket(String ip) =>
    'ip:auth:${sha256.convert(utf8.encode(ipAuthKeySource(ip))).toString().substring(0, 32)}';

/// Four ordered steps per request (spec §5.2), and the order is the security:
///
/// 1. `path == '/health'` → pass.
/// 2. [OriginAuthOff] → pass.
/// 3. Header present and constant-time equal → **verified**. Otherwise log
///    `origin_auth_missing method=<m> path=<p>` (the path only — never the
///    query string, never any header value: the request-id middleware's own
///    rule) and: `log` mode → pass, unverified; `enforce` → 403.
/// 4. **Only if verified** and the path is under `/auth/` or `/admin/auth/`:
///    read the client IP. Absent → log `origin_client_ip_missing path=<p>` and
///    pass — « unknown must never silently collapse into one shared bucket ».
///    Present → one hit against `ip:auth:<digest>`; refused → log
///    `rate_limited bucket=… hits=… limit=…` and 429 `rate_limited`. No 80 %
///    warning line for IP buckets: 8 of 10 in a minute is a person
///    double-tapping, not a signal.
Middleware originFrontDoorMiddleware(
  OriginAuth Function() config,
  RateLimiter Function() limiter, {
  void Function(String) log = print,
}) {
  return (handler) {
    return (context) async {
      final request = context.request;
      final path = request.uri.path;

      // 1. The probe's door. Exact, not a prefix — see kOriginAuthExemptPath.
      if (path == kOriginAuthExemptPath) return handler(context);

      // 2. Nothing configured: dev, CI, staging.
      final auth = config();
      final on = switch (auth) {
        OriginAuthOff() => null,
        OriginAuthOn() => auth,
      };
      if (on == null) return handler(context);

      // 3. The gate. Constant-time, so a byte-by-byte guess cannot be timed
      // against a 64-character secret one prefix at a time.
      final provided = request.headers[kOriginAuthHeader]?.trim();
      final verified =
          provided != null && constantTimeEquals(on.secret, provided);
      if (!verified) {
        // A verb outside dart_frog's enum (PROPFIND, TRACE, PURGE…) makes
        // `request.method` throw, and the observability catch would then throw
        // again reading it — a bare 500 with a stack trace on the direct door
        // instead of a refusal (found in review). 405 is what such a verb gets
        // anywhere else here.
        final String verb;
        try {
          verb = request.method.value;
        } on Exception {
          // dart_frog's UnsupportedHttpMethodException, which the package
          // does not export; nothing else in `.method.value` can throw.
          return jsonError(HttpStatus.methodNotAllowed, 'method_not_allowed');
        }
        log('origin_auth_missing method=$verb path=$path');
        if (on.mode == OriginAuthMode.enforce) {
          return jsonError(
            HttpStatus.forbidden,
            'origin_required',
            'Requests must come through api.myweli.com.',
          );
        }
        // Log mode: the rollout's measurement window. Unverified, so the IP
        // below is NOT read — a forged CF-Connecting-IP on the direct door
        // must not reach the limiter even while the door is being counted.
        return handler(context);
      }

      // 4. Verified — and only now — the per-IP auth limit.
      if (isIpLimitedPath(path)) {
        final ip = request.headers[kClientIpHeader]?.trim();
        if (ip == null || ip.isEmpty) {
          log('origin_client_ip_missing path=$path');
          return handler(context);
        }
        final bucket = ipAuthBucket(ip);
        final RateVerdict verdict;
        try {
          verdict = await limiter().hit(
            bucket,
            limit: kIpAuthLimit,
            window: kIpAuthWindow,
          );
        } catch (_) {
          // Failing open is the wrapper's job — `FailOpenRateLimiter` already
          // prints `rate_limit_unavailable bucket=` and answers ok — so this
          // arm is not reached in production. It exists so that a limiter
          // handed over WITHOUT the wrapper cannot turn a Postgres blip into
          // a 500 on every sign-in, and it prints nothing on purpose: a
          // second copy of the wrapper's line would page the same alert twice.
          return handler(context);
        }
        if (!verdict.ok) {
          log(
            'rate_limited bucket=$bucket '
            'hits=${verdict.hits} limit=${verdict.limit}',
          );
          return jsonError(HttpStatus.tooManyRequests, 'rate_limited');
        }
      }
      return handler(context);
    };
  };
}
