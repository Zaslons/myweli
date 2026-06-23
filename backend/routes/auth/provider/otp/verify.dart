import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/provider/otp/verify` — verify a code; returns the provider
/// account + a signed access token (role `provider`).
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

  return Response.json(
    body: {
      'provider': result.provider!.toJson(),
      'accessToken': result.accessToken,
    },
  );
}
