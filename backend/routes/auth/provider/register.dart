import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

const _businessTypes = {
  'salon',
  'barber',
  'spa',
  'nailSalon',
  'massage',
  'other',
};

/// `POST /auth/provider/register` — create a provider account and send a code.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final phone = (body['phoneNumber'] as String?)?.trim() ?? '';
  final businessName = (body['businessName'] as String?)?.trim() ?? '';
  final businessType = (body['businessType'] as String?) ?? '';
  final address = (body['address'] as String?)?.trim();
  if (!isValidE164(phone) ||
      businessName.isEmpty ||
      !_businessTypes.contains(businessType)) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final providerIdRaw = (body['providerId'] as String?)?.trim();
  final result = await context.read<ProviderAuthRepository>().register(
    phoneNumber: phone,
    businessName: businessName,
    businessType: businessType,
    address: (address == null || address.isEmpty) ? null : address,
    providerId: (providerIdRaw == null || providerIdRaw.isEmpty)
        ? null
        : providerIdRaw,
  );
  if (!result.ok) {
    return jsonError(HttpStatus.conflict, result.error!);
  }

  return Response.json(
    statusCode: HttpStatus.created,
    body: {
      'provider': result.provider!.toJson(),
      'expiresInSeconds': result.expiresInSeconds,
      if (result.devCode != null) 'devCode': result.devCode,
    },
  );
}
