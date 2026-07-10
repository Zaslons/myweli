import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/validators.dart';

const _businessTypes = {
  'salon',
  'barber',
  'spa',
  'nailSalon',
  'massage',
  'other',
};

/// `POST /auth/provider/register` — create a salon account with the identity
/// proof INLINE (auth overhaul: one submit registers AND signs in):
///   - Google: `{ idToken, businessName, businessType, phoneNumber, … }`
///   - Apple:  `{ identityToken, nonce?, … }` (seam)
///   - Email:  `{ email, code, … }` (code from /auth/provider/email/otp/request)
/// The contact `phoneNumber` is REQUIRED (a salon must be reachable — decision
/// 2026-07-03). Returns a live ProviderSession (201).
/// Design: docs/design/pro-auth-social.md.
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
  final rawAddress = (body['address'] as String?)?.trim();
  if (!isValidE164(phone) ||
      businessName.isEmpty ||
      !_businessTypes.contains(businessType)) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }
  final address = (rawAddress == null || rawAddress.isEmpty)
      ? null
      : rawAddress;
  final providerIdRaw = (body['providerId'] as String?)?.trim();
  final providerId = (providerIdRaw == null || providerIdRaw.isEmpty)
      ? null
      : providerIdRaw;

  final methods = context.read<AuthMethods>();
  final repo = context.read<ProviderAuthRepository>();

  // --- Identity: Google ------------------------------------------------------
  final idToken = (body['idToken'] as String?)?.trim();
  if (idToken != null && idToken.isNotEmpty) {
    if (!methods.contains('google')) {
      return jsonError(HttpStatus.notFound, 'auth_method_disabled');
    }
    final claims = await context.read<GoogleIdTokenVerifier>().verify(idToken);
    if (!claims.ok) return verifierError(claims.error!);
    return providerSessionResponse(
      await _provisioned(
        context,
        await repo.register(
          businessName: businessName,
          businessType: businessType,
          phoneNumber: phone,
          email: claims.email!,
          authProvider: 'google',
          googleSub: claims.sub,
          address: address,
          providerId: providerId,
        ),
      ),
      successStatus: HttpStatus.created,
    );
  }

  // --- Identity: Apple (seam) ------------------------------------------------
  final identityToken = (body['identityToken'] as String?)?.trim();
  if (identityToken != null && identityToken.isNotEmpty) {
    if (!methods.contains('apple')) {
      return jsonError(HttpStatus.notFound, 'auth_method_disabled');
    }
    final nonce = (body['nonce'] as String?)?.trim();
    final claims = await context.read<AppleIdTokenVerifier>().verify(
      identityToken,
      nonce: (nonce != null && nonce.isNotEmpty) ? nonce : null,
    );
    if (!claims.ok) return verifierError(claims.error!);
    if (claims.email == null) {
      return jsonError(HttpStatus.unauthorized, 'token_rejected');
    }
    return providerSessionResponse(
      await _provisioned(
        context,
        await repo.register(
          businessName: businessName,
          businessType: businessType,
          phoneNumber: phone,
          email: claims.email!,
          authProvider: 'apple',
          appleSub: claims.sub,
          address: address,
          providerId: providerId,
        ),
      ),
      successStatus: HttpStatus.created,
    );
  }

  // --- Identity: email + code ------------------------------------------------
  final email = (body['email'] as String?)?.trim() ?? '';
  final code = (body['code'] as String?)?.trim() ?? '';
  if (isValidEmail(email) && isValidOtpCode(code)) {
    if (!methods.contains('email')) {
      return jsonError(HttpStatus.notFound, 'auth_method_disabled');
    }
    return providerSessionResponse(
      await _provisioned(
        context,
        await repo.register(
          businessName: businessName,
          businessType: businessType,
          phoneNumber: phone,
          email: email,
          authProvider: 'email',
          emailCode: code,
          address: address,
          providerId: providerId,
        ),
      ),
      successStatus: HttpStatus.created,
    );
  }

  // No usable identity proof.
  return jsonError(HttpStatus.badRequest, 'invalid_input');
}

/// A new account gets its DRAFT salon right away (docs/design/
/// pro-salon-lifecycle.md §2) — the dashboard works from second one. A
/// failure here is tolerable: /me/provider self-heals on first read.
Future<ProviderVerifyResult> _provisioned(
  RequestContext context,
  ProviderVerifyResult result,
) async {
  if (!result.ok) return result;
  final account = await context.read<SalonProvisioningService>().ensureSalon(
    result.provider!,
  );
  return (ok: true, error: null, provider: account, tokens: result.tokens);
}
