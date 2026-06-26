import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/auth/refresh` — rotate an admin refresh token. Reuse of an
/// already-rotated token revokes the whole family. Design: docs/design/admin-console.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final token = (body['refreshToken'] as String?)?.trim() ?? '';
  if (token.isEmpty) return jsonError(HttpStatus.badRequest, 'invalid_input');

  final r = await context.read<AdminAuthRepository>().refresh(token);
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
  return jsonError(HttpStatus.unauthorized, r.error ?? 'refresh_invalid');
}
