import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/observability/refresh_log.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /auth/provider/refresh` — rotate a provider refresh token for a fresh
/// pair. Mirrors `/auth/refresh`: a second presentation within 30 s of the
/// rotation gets a sibling pair; after that, replaying a rotated token revokes
/// the family. Logs one `auth_refresh` outcome line.
/// Design: docs/design/backend-refresh-rotation-atomic.md.
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

  final result = await context.read<ProviderAuthRepository>().refresh(token);
  logRefreshOutcome(context, RefreshPrincipal.provider, result.outcome);
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
