import 'auth/id_token_verifier.dart';

typedef CronAuthResult = ({bool ok, String? error});

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
/// ## The header is gone (2026-08-18)
///
/// It existed as a fallback because Cloud Scheduler's OIDC token, though always
/// sent, bought nothing until the routes verified it — and removing the header
/// before evidence that the token worked would have taken the crons down in the
/// least observable way possible.
///
/// That evidence was gathered rather than assumed
/// (docs/design/infra-cron-oidc-evidence.md):
///
/// * **staging** ran on OIDC alone — its jobs never carried the header at all —
///   answering 200, while an anonymous or junk-token call got 403;
/// * **production** ran 251 consecutive crons on revision `-00017-p4j` with
///   zero `cron_auth_legacy` log lines, so the fallback was already unused;
/// * then both production jobs had the header stripped **one at a time**, each
///   forced immediately afterwards: 200, no legacy line. That last step is the
///   one that proved OIDC works *through the load balancer*, which staging
///   cannot show.
///
/// **A failed OIDC verification is now a 403.** It used to fall through to the
/// secret so a misconfigured audience could not take the crons down; with the
/// fallback gone, an audience that stops matching `CRON_OIDC_AUDIENCE` fails
/// closed and loudly. That is the intended end state, and the alert policy
/// created alongside this (`infra/gcp/86-cron-auth-alert.sh`) is what makes a
/// regression visible.
class CronAuth {
  CronAuth({
    required IdTokenVerifier? oidcVerifier,
    required String? schedulerServiceAccount,
  }) : _oidc = oidcVerifier,
       _serviceAccount = schedulerServiceAccount?.trim().toLowerCase();

  final IdTokenVerifier? _oidc;
  final String? _serviceAccount;

  /// Whether the endpoint exists at all. Deny-by-default: unconfigured means
  /// the route 404s, so the surface is not merely unguarded-but-present.
  ///
  /// `dependencies.dart` builds the verifier as null unless BOTH
  /// `CRON_OIDC_AUDIENCE` and `CRON_SERVICE_ACCOUNT` are set, so this one check
  /// covers both — there is no state where the route exists but can never
  /// authenticate anyone.
  bool get isConfigured => _oidc != null;

  /// [bearer] is the raw `Authorization` header. Query parameters are
  /// deliberately not a parameter — see the class doc.
  Future<CronAuthResult> authenticate({String? bearer}) async {
    final token = _bearerToken(bearer);
    if (token != null && _oidc != null && _serviceAccount != null) {
      final res = await _oidc.verify(token);
      // The signature, `iss`, `aud` and `exp` are the verifier's job. Ours is
      // *which* Google principal this is — any Google account can mint a token
      // for an audience, so without this check the audience is a public string.
      if (res.ok && res.email?.trim().toLowerCase() == _serviceAccount) {
        return (ok: true, error: null);
      }
    }
    return (ok: false, error: 'forbidden');
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
}
