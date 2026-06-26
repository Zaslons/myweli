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
      password.isEmpty) {
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
  return jsonError(HttpStatus.unauthorized, 'invalid_credentials');
}
