import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_auth_repository.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/auth/password` — an authenticated admin changes their own
/// password, proving possession of the current one.
///
/// **This route authenticates ITSELF, and that is the trap worth naming.** The
/// `/admin` middleware exempts everything under `/admin/auth` — login and
/// refresh must be reachable without a token — so the deny-by-default gate that
/// covers every other admin route does **not** cover this one. Reading
/// `_middleware.dart` and concluding "the gate has me" would ship an
/// unauthenticated password-change endpoint. A test calls it anonymously.
///
/// Exists because rotating the credential by redeploying `ADMIN_PASSWORD` is a
/// no-op: the seeder is insert-only, so the value is read and discarded on
/// every database that already holds the admin.
/// Design: docs/design/backend-admin-password-change.md
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'admin') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final current = body['currentPassword'];
  final next = body['newPassword'];
  if (current is! String ||
      next is! String ||
      current.isEmpty ||
      next.length < kAdminPasswordMinLength ||
      // bcrypt truncates at 72 bytes, so anything beyond it is not part of the
      // password — accepting a 1 MB body would hash the first 72 characters and
      // report success over a secret the caller does not actually have to know.
      next.length > 72 ||
      current.length > 72) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final r = await context.read<AdminAuthRepository>().changePassword(
    adminId: principal.userId,
    currentPassword: current,
    newPassword: next,
  );

  if (r.ok) {
    // Audited like every other privileged action, and carrying **no password
    // material** — not the old hash, not a prefix, not a length.
    await context.read<AuditLogRepository>().append((
      actorAdminId: principal.userId,
      action: 'admin.password_changed',
      targetType: 'admin',
      targetId: principal.userId,
      reason: null,
      metadata: const {'refreshTokensRevoked': true},
    ));
    return Response(statusCode: HttpStatus.noContent);
  }
  return switch (r.error) {
    'locked_out' => jsonError(HttpStatus.tooManyRequests, 'locked_out'),
    // A code of its OWN, never `locked_out`: telling an operator that someone
    // guessed too often when the truth is that Postgres is sick is the
    // confusion this separation exists to prevent. Retryable, so 503.
    'throttle_unavailable' => jsonError(
      HttpStatus.serviceUnavailable,
      'throttle_unavailable',
      null,
      const {'retry-after': '5'},
    ),
    'weak_password' ||
    'password_unchanged' => jsonError(HttpStatus.badRequest, r.error!),
    // `not_found` lands here too: a valid token for a deleted admin is not a
    // 404 worth distinguishing from a bad credential.
    _ => jsonError(HttpStatus.unauthorized, 'invalid_credentials'),
  };
}
