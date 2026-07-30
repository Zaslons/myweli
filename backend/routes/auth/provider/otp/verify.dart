import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/provider/otp/verify` — verify a code; returns the provider
/// NOTE (module `access` R2b): the invitation bridge does NOT apply here —
/// invitations are EMAIL-keyed and a phone OTP proves no email. Dormant
/// route (AUTH_METHODS gates phone off at launch).
/// account + a signed access token (role `provider`).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  // Dormant at launch (auth overhaul): SMS-OTP is gated by AUTH_METHODS.
  if (!context.read<AuthMethods>().contains('phone')) {
    return jsonError(HttpStatus.notFound, 'auth_method_disabled');
  }

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

  final result = await context.read<ProviderAuthRepository>().verifyOtp(
    phone,
    code,
  );
  if (!result.ok) {
    final status = result.error == 'provider_not_found'
        ? HttpStatus.notFound
        : HttpStatus.badRequest;
    return jsonError(status, result.error!);
  }

  final tokens = result.tokens!;
  return Response.json(
    body: {
      'provider': result.provider!.toJson(),
      'accessToken': tokens.accessToken,
      'refreshToken': tokens.refreshToken,
      'expiresAt': tokens.expiresAt.toIso8601String(),
    },
  );
}
