import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/moderation_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /me/provider/reviews/{id}/report` `{reason?}` — the salon reports a
/// review of ITS salon (B6.6, decision 20 — App Store 1.2 asks for a way to
/// report user content, and the Pro « Avis » had none). The same admin queue
/// as a client's report, marked « Signalé par le salon ».
///
/// The salon is resolved like `GET /me/provider/reviews` (the account's, or
/// `?salonId=` against an ACTIVE membership); only the Propriétaire and the
/// Gérant may report (`profile.manage`) — 403 otherwise. A review of another
/// salon is 404. Idempotent per review and salon.
/// Design: docs/design/backend-integrity-batch6.md §2.6.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  final account = await context.read<ProviderAuthRepository>().accountById(
    principal.userId,
  );
  if (account == null) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final members = context.read<MembershipService>();
  final selected = context.request.uri.queryParameters['salonId']?.trim() ?? '';
  final providerId = selected.isNotEmpty
      ? await members.salonForRequest(account.id, salonId: selected)
      : (account.providerId ?? await members.activeSalonFor(account.id));
  // Deny by default: the capability check is what authorizes the report.
  if (providerId == null ||
      !await members.can(account.id, providerId, Cap.profileManage)) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  // The reason is optional — an absent or empty body is a report too, as on
  // the client's route.
  Map<String, dynamic> body = const {};
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    // tolerated: no reason
  }

  final r = await context.read<ModerationService>().reportBySalon(
    providerId,
    id,
    body['reason'],
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
