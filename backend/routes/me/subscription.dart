import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';

/// `GET /me/subscription` — LEGACY compat (the app/web consume this shape
/// verbatim): `{tier: free|pro, status: trial|free, trialEndsAt,
/// trialDaysLeft}`, now derived from the SALON's offer (pricing pivot —
/// docs/design/team-access-r2a-offers.md); accounts without a salon/offer
/// fall back to the old account-age derivation. The real model lives at
/// `GET /providers/{id}/subscription`.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final account = await context.read<ProviderAuthRepository>().accountById(
    principal.userId,
  );
  if (account == null) return jsonError(HttpStatus.notFound, 'not_found');

  final sub = await context
      .read<SalonSubscriptionService>()
      .legacySubscriptionFor(principal.userId);
  return Response.json(body: sub.toJson());
}
