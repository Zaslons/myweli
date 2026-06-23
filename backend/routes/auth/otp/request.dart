import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/otp/request` — dispatch a one-time code for a phone number.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final phone = (body['phoneNumber'] as String?)?.trim() ?? '';
  if (!isValidE164(phone)) {
    return jsonError(HttpStatus.badRequest, 'invalid_phone');
  }

  final result = await context.read<AuthRepository>().requestOtp(phone);
  if (!result.ok) {
    return jsonError(HttpStatus.tooManyRequests, result.error!);
  }

  return Response.json(
    statusCode: HttpStatus.accepted,
    body: {
      'expiresInSeconds': result.expiresInSeconds,
      if (result.devCode != null) 'devCode': result.devCode,
    },
  );
}
