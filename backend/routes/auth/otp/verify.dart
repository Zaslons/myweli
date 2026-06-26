import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/otp/verify` — verify a code and issue a token pair + user.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final phone = (body['phoneNumber'] as String?)?.trim() ?? '';
  final code = (body['code'] as String?)?.trim() ?? '';
  if (!isValidE164(phone) || !isValidOtpCode(code)) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final result = await context.read<AuthRepository>().verifyOtp(phone, code);
  if (!result.ok) {
    final status = result.error == 'account_suspended'
        ? HttpStatus.forbidden
        : HttpStatus.badRequest;
    return jsonError(status, result.error!);
  }

  final tokens = result.tokens!;
  return Response.json(
    body: {
      'tokens': {
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
        'expiresAt': tokens.expiresAt.toIso8601String(),
      },
      'user': result.user!.toJson(),
    },
  );
}
