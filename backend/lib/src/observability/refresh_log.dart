import 'package:dart_frog/dart_frog.dart';

import '../auth/auth_repository.dart';
import 'request_middleware.dart';

/// Whose refresh token was exchanged — the three refresh routes.
enum RefreshPrincipal { consumer, provider, admin }

/// The one structured line each refresh route prints
/// (docs/design/backend-refresh-rotation-atomic.md §6):
///
///     INFO: auth_refresh principal=consumer outcome=grace request_id=…
///
/// Until this existed a revocation was invisible in production: nothing logged
/// a refresh outcome at all. `reused` is the security event worth an alert;
/// `grace` counts how often clients race.
///
/// Takes the OUTCOME only — never the token, its hash, the owner's id or any
/// other PII (BACKEND.md §3.6), so there is nothing here that could leak one.
void logRefreshOutcome(
  RequestContext context,
  RefreshPrincipal principal,
  RefreshOutcome outcome,
) {
  // ignore: avoid_print — structured, and the container log is where an
  // operator actually looks.
  print(
    'INFO: auth_refresh principal=${principal.name} '
    'outcome=${outcome.name} '
    'request_id=${logSafeRequestId(requestIdOf(context))}',
  );
}

/// The request id as it may appear in a log line. The id can come from the
/// CLIENT (`X-Request-Id`, reused verbatim by the middleware), so without this
/// a caller could append `outcome=reused principal=admin` and forge — or, for
/// a last-key-wins parser, hide — the security event an alert keys on.
/// Anything but a plain token of letters, digits and dashes (≤ 64) is
/// replaced, never echoed.
String logSafeRequestId(String id) =>
    RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(id) ? id : 'invalid';
