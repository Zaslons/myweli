import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';

/// The salon's offer (pricing pivot — docs/design/team-access-r2a-offers.md).
///
/// `GET /providers/{id}/subscription` — the derived state (tier, status
/// trial/paid/grace/expired, clocks, seats), or 404 while the salon is in
/// the free setup state (no offer chosen yet).
/// `PUT /providers/{id}/subscription` `{tier}` — choose/switch the offer;
/// the FIRST choice starts the salon's ONE 3-month trial. Owner-only
/// (`subscription.manage`, threat T54).
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final subscriptions = context.read<SalonSubscriptionService>();

  switch (context.request.method) {
    case HttpMethod.get:
      if (!await context.read<MembershipService>().can(
        principal.userId,
        id,
        Cap.subscriptionManage,
      )) {
        return jsonError(HttpStatus.forbidden, 'forbidden');
      }
      final state = await subscriptions.stateFor(id);
      if (state == null) return jsonError(HttpStatus.notFound, 'not_found');
      return Response.json(body: state);

    case HttpMethod.put:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      final r = await subscriptions.chooseOffer(
        principal.userId,
        id,
        body['tier'],
      );
      if (!r.ok) {
        return switch (r.error) {
          'forbidden' => jsonError(HttpStatus.forbidden, 'forbidden'),
          'trial_used' => jsonError(HttpStatus.conflict, 'trial_used'),
          _ => jsonError(HttpStatus.badRequest, r.error ?? 'invalid_input'),
        };
      }
      return Response.json(body: r.data);

    default:
      return methodNotAllowed();
  }
}
