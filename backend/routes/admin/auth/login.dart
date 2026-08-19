import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/auth/login` — staff email + password → admin token pair.
/// Rate-limited (lockout) on repeated failures. Design: docs/design/admin-console.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final email = body['email'];
  final password = body['password'];
  if (email is! String ||
      password is! String ||
      email.isEmpty ||
      password.isEmpty ||
      // **RFC 5321's maximum, and a boundary this route never had.** The email
      // is the caller's own input on an unauthenticated endpoint, and it
      // becomes a throttle key — unknown addresses are counted deliberately, so
      // `locked_out` cannot become an admin-address oracle. Without a cap a
      // 1 MB address is a legal request, and the key set is unbounded in WIDTH
      // as well as in count. The hash bounds the stored row; this bounds what
      // has to be hashed. docs/design/backend-admin-login-throttle.md
      email.length > 254) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final r = await context.read<AdminAuthRepository>().login(email, password);
  if (r.ok) {
    final t = r.tokens!;
    return Response.json(
      body: {
        'accessToken': t.accessToken,
        'refreshToken': t.refreshToken,
        'expiresAt': t.expiresAt.toIso8601String(),
      },
    );
  }
  if (r.error == 'locked_out') {
    return jsonError(HttpStatus.tooManyRequests, 'locked_out');
  }
  // **Ours, not the caller's.** The throttle store could not answer, so the
  // login was refused rather than letting the only brute-force bound on this
  // credential lapse silently. A code of its OWN, not `locked_out`: telling an
  // operator at 2am that someone guessed too often, when the truth is that
  // Postgres is sick, is the confusion `storageUnavailable()` exists to
  // prevent. 503 + Retry-After, because it is a retryable outage rather than a
  // verdict about the caller.
  // docs/design/backend-admin-login-throttle.md
  if (r.error == 'throttle_unavailable') {
    return jsonError(
      HttpStatus.serviceUnavailable,
      'throttle_unavailable',
      null,
      const {'retry-after': '5'},
    );
  }
  return jsonError(HttpStatus.unauthorized, 'invalid_credentials');
}
