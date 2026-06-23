import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /auth/refresh` — rotate a refresh token for a fresh pair.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final token = (body['refreshToken'] as String?)?.trim() ?? '';
  if (token.isEmpty) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final result = context.read<AuthRepository>().refresh(token);
  if (!result.ok) {
    return jsonError(HttpStatus.unauthorized, result.error!);
  }

  final tokens = result.tokens!;
  return Response.json(
    body: {
      'accessToken': tokens.accessToken,
      'refreshToken': tokens.refreshToken,
      'expiresAt': tokens.expiresAt.toIso8601String(),
    },
  );
}
