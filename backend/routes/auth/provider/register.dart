import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/apple_tokens.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:myweli_backend/src/localities/localities_service.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /auth/provider/register` — create a salon account with the identity
/// proof INLINE (auth overhaul: one submit registers AND signs in):
///   - Google: `{ idToken, businessName, businessType, phoneNumber, … }`
///   - Apple:  `{ identityToken, nonce?, … }` (seam)
///   - Email:  `{ email, code, … }` (code from /auth/provider/email/otp/request)
/// The contact `phoneNumber` is REQUIRED (a salon must be reachable — decision
/// 2026-07-03). Returns a live ProviderSession (201). 400s: `invalid_body`
/// (not an object, or a field of the wrong JSON type), `invalid_input`
/// (business name/type, or no usable identity proof), `invalid_phone`,
/// `invalid_area`.
/// Design: docs/design/pro-auth-social.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  // Every field read by type before any rule runs — and before the identity
  // verifiers and the account write below — so a wrong JSON type is one
  // `400 invalid_body` whichever field carries it, and whichever identity
  // proof is used (docs/design/phone-leftovers.md §3).
  final phone = optionalString(body, 'phoneNumber')?.trim() ?? '';
  final businessName = optionalString(body, 'businessName')?.trim() ?? '';
  final businessType = optionalString(body, 'businessType') ?? '';
  final rawAddress = optionalString(body, 'address')?.trim();
  final areaIdRaw = optionalString(body, 'areaId')?.trim();
  final idToken = optionalString(body, 'idToken')?.trim();
  final identityToken = optionalString(body, 'identityToken')?.trim();
  final nonce = optionalString(body, 'nonce')?.trim();
  final email = optionalString(body, 'email')?.trim() ?? '';
  final code = optionalString(body, 'code')?.trim() ?? '';
  // B6.7 — the Apple branch's code (docs/design/backend-integrity-batch6.md
  // §13), read by type with the rest.
  final appleCode = appleCodeOf(body);

  if (businessName.isEmpty ||
      businessName.runes.length >
          SalonProvisioningService.maxBusinessNameChars ||
      !SalonProvisioningService.businessTypes.contains(businessType)) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }
  // The phone has a code of its own, so a client can put the fault under that
  // field rather than « Informations invalides. » for the whole form
  // (docs/design/phone-leftovers.md §2). After the name and the type — the
  // order `POST /me/salons` uses.
  if (!isValidPhoneNumber(phone)) {
    return jsonError(HttpStatus.badRequest, 'invalid_phone');
  }
  final address = (rawAddress == null || rawAddress.isEmpty)
      ? null
      : rawAddress;
  // Multi-pays MP1: an optional locality pick — validated against the tree,
  // the salon's market facts derive from it (threat T57).
  SalonMarket? market;
  if (areaIdRaw != null && areaIdRaw.isNotEmpty) {
    market = await context.read<LocalitiesService>().resolveArea(areaIdRaw);
    if (market == null) {
      return jsonError(HttpStatus.badRequest, 'invalid_area');
    }
  }
  // T72: NO salon link from the client. The body used to carry an optional
  // `providerId`, stored as the account's salon and then made an ACTIVE owner
  // row by the provisioning step — anyone who could prove any identity could
  // claim any salon by its public id. No client ever sent it; a new account
  // always gets its own draft salon from `ensureSalon`.
  // docs/design/backend-register-salon-link.md

  final methods = context.read<AuthMethods>();
  final repo = context.read<ProviderAuthRepository>();

  // --- Identity: Google ------------------------------------------------------
  if (idToken != null && idToken.isNotEmpty) {
    if (!methods.contains('google')) {
      return jsonError(HttpStatus.notFound, 'auth_method_disabled');
    }
    final claims = await context.read<GoogleIdTokenVerifier>().verify(idToken);
    if (!claims.ok) return verifierError(claims.error!);
    return providerSessionResponse(
      await _provisioned(
        context,
        market,
        await repo.register(
          businessName: businessName,
          businessType: businessType,
          phoneNumber: phone,
          email: claims.email!,
          authProvider: 'google',
          googleSub: claims.sub,
          address: address,
        ),
      ),
      successStatus: HttpStatus.created,
    );
  }

  // --- Identity: Apple (seam) ------------------------------------------------
  if (identityToken != null && identityToken.isNotEmpty) {
    if (!methods.contains('apple')) {
      return jsonError(HttpStatus.notFound, 'auth_method_disabled');
    }
    final verifier = context.read<AppleIdTokenVerifier>();
    final claims = await verifier.verify(
      identityToken,
      nonce: (nonce != null && nonce.isNotEmpty) ? nonce : null,
    );
    if (!claims.ok) return verifierError(claims.error!);
    if (claims.email == null) {
      return jsonError(HttpStatus.unauthorized, 'token_rejected');
    }
    final result = await _provisioned(
      context,
      market,
      await repo.register(
        businessName: businessName,
        businessType: businessType,
        phoneNumber: phone,
        email: claims.email!,
        authProvider: 'apple',
        appleSub: claims.sub,
        address: address,
      ),
    );
    // B6.7 — kept under the NEW account, which its deletion revokes.
    if (result.ok) {
      await keepAppleSignInCode(
        apple: appleCode,
        identityToken: identityToken,
        verifier: verifier,
        sub: claims.sub!,
        kind: 'provider',
        accountId: result.provider!.id,
        tokens: context.read<AppleTokenService>,
      );
    }
    return providerSessionResponse(result, successStatus: HttpStatus.created);
  }

  // --- Identity: email + code ------------------------------------------------
  if (isValidEmail(email) && isValidOtpCode(code)) {
    if (!methods.contains('email')) {
      return jsonError(HttpStatus.notFound, 'auth_method_disabled');
    }
    // The demo identity (T69): the same mint-and-consume dance as the verify
    // route, used exactly once ever — the one-time provisioning of the demo
    // salon THROUGH the real product (design §9). Seam absent → false, and
    // the demo address registers like any other, i.e. fails on the code.
    var emailCode = code;
    if (context.read<DemoSeam>().allows(email: email, otp: code)) {
      final minted = await repo.requestEmailOtp(email);
      if (!minted.ok) {
        return jsonError(HttpStatus.tooManyRequests, minted.error!);
      }
      await repo.refundEmailOtpResend(email);
      emailCode = minted.code!;
    }
    return providerSessionResponse(
      await _provisioned(
        context,
        market,
        await repo.register(
          businessName: businessName,
          businessType: businessType,
          phoneNumber: phone,
          email: email,
          authProvider: 'email',
          emailCode: emailCode,
          address: address,
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
  SalonMarket? market,
  ProviderVerifyResult result,
) async {
  if (!result.ok) return result;
  final account = await context.read<SalonProvisioningService>().ensureSalon(
    result.provider!,
    market: market,
  );
  return (ok: true, error: null, provider: account, tokens: result.tokens);
}
