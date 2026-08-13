import 'dart:convert';

import 'auth/id_token_verifier.dart';

/// How a cron call authenticated, for the log line.
enum CronAuthMethod { oidc, sharedSecret }

typedef CronAuthResult = ({bool ok, CronAuthMethod? method, String? error});

/// Authenticates a call to `/internal/cron/*` (docs/design/infra-staging.md §7,
/// finding 2).
///
/// ## Why this exists as a service rather than four lines in each route
///
/// Both cron routes authenticated identically and independently:
///
/// ```dart
/// final provided = context.request.headers['x-cron-secret']
///     ?? context.request.uri.queryParameters['secret'];
/// if (provided != secret) return jsonError(HttpStatus.forbidden, 'forbidden');
/// ```
///
/// Three problems, and duplicating them was the fourth:
///
/// 1. **The secret is a literal header on the Cloud Scheduler job.** Cloud
///    Scheduler has no Secret Manager reference for headers, so `gcloud
///    scheduler jobs describe` prints it verbatim to anyone with
///    `cloudscheduler.jobs.get` — which today includes the **default compute
///    service account**, since it holds `roles/editor`.
/// 2. **It was also accepted as `?secret=`**, which writes a production
///    credential into access logs, load-balancer logs and anything that records
///    a URL. Removed outright: nothing legitimate used it.
/// 3. **`!=` on a `String` is not constant-time.**
///
/// ## Why the header still works
///
/// Cloud Scheduler already sends a Google-signed OIDC token on both jobs — it
/// simply bought nothing, because Cloud Run grants `roles/run.invoker` to
/// `allUsers` (it must: the same service serves the public API) and the routes
/// never looked at it. So the token is verified here **first**, and the header
/// remains as a fallback until a real scheduled run is observed passing on the
/// token. Removing it before that evidence exists would take the reminder and
/// subscription crons down in the least observable way possible.
class CronAuth {
  CronAuth({
    required IdTokenVerifier? oidcVerifier,
    required String? schedulerServiceAccount,
    required String? sharedSecret,
  }) : _oidc = oidcVerifier,
       _serviceAccount = schedulerServiceAccount?.trim().toLowerCase(),
       _secret = sharedSecret;

  final IdTokenVerifier? _oidc;
  final String? _serviceAccount;
  final String? _secret;

  /// Whether the endpoint exists at all. Deny-by-default: with neither
  /// mechanism configured the route 404s, so the surface is not merely
  /// unguarded-but-present.
  bool get isConfigured => _oidc != null || _secret != null;

  /// [bearer] is the raw `Authorization` header; [headerSecret] the
  /// `X-Cron-Secret` one. Query parameters are deliberately not a parameter —
  /// see the class doc.
  Future<CronAuthResult> authenticate({
    String? bearer,
    String? headerSecret,
  }) async {
    final token = _bearerToken(bearer);
    if (token != null && _oidc != null && _serviceAccount != null) {
      final res = await _oidc.verify(token);
      // The signature, `iss`, `aud` and `exp` are the verifier's job. Ours is
      // *which* Google principal this is — any Google account can mint a token
      // for an audience, so without this check the audience is a public string.
      if (res.ok && res.email?.trim().toLowerCase() == _serviceAccount) {
        return (ok: true, method: CronAuthMethod.oidc, error: null);
      }
      // Fall through to the secret rather than rejecting: during the
      // transition a misconfigured audience must not take the crons down.
    }

    final secret = _secret;
    if (secret != null &&
        headerSecret != null &&
        _constantTimeEquals(headerSecret, secret)) {
      return (ok: true, method: CronAuthMethod.sharedSecret, error: null);
    }
    return (ok: false, method: null, error: 'forbidden');
  }

  static String? _bearerToken(String? header) {
    if (header == null) return null;
    const prefix = 'Bearer ';
    if (header.length <= prefix.length) return null;
    if (!header
        .substring(0, prefix.length)
        .toLowerCase()
        .startsWith('bearer')) {
      return null;
    }
    final token = header.substring(prefix.length).trim();
    return token.isEmpty ? null : token;
  }

  /// Compares in time proportional to the inputs, not to how far they match.
  ///
  /// The lengths are compared first and the result folded in, rather than
  /// returned early — an early return leaks the secret's length, which is the
  /// one thing a timing attacker gets for free otherwise.
  ///
  /// **`utf8.encode`, not `codeUnits`.** `Uint8List.fromList` truncates each
  /// UTF-16 code unit to 8 bits, so characters above U+00FF collapse onto their
  /// low byte and distinct secrets compare EQUAL — `'Ł'` (U+0141) matched `'A'`.
  /// Found while porting this routine to the messaging webhook.
  static bool _constantTimeEquals(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    var diff = ab.length ^ bb.length;
    final n = ab.length < bb.length ? ab.length : bb.length;
    for (var i = 0; i < n; i++) {
      diff |= ab[i] ^ bb[i];
    }
    return diff == 0;
  }
}
