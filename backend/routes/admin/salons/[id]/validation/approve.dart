import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validation/salon_validation_service.dart';

/// `POST /admin/salons/{id}/validation/approve` `{from}` — MyWeli validates
/// the salon, and it goes public (B0.18, docs/design/salon-go-live-approval.md
/// §3.2). `from` is the state the admin saw: `pending`, `refused` (correcting
/// a refusal from « Refusés »), or `approved` (« Validation à terminer »:
/// finishing a validation interrupted before it went live).
///
/// 200 `{salonStatus: active, validation}`. 400 `invalid_body` (not a JSON
/// object) · `invalid_input` (`from` missing or unknown). 404. 409 — nothing
/// public: `provider_suspended`, `incomplete` + `missing` (the gate re-run
/// now; `offer` for an offer that is no longer live), `validation_not_pending`
/// (another decision won, or it already went live), `no_owner`,
/// `invalid_state`. Audited (`salon.approve`) by the single winner.
/// Admin-only by the `/admin` middleware (T17).
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  final Object? body;
  try {
    body = await context.request.json();
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  if (body is! Map<String, dynamic>) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<SalonValidationService>().approve(
    id,
    from: body['from'],
    adminId: adminId,
  );
  return salonValidationResponse(r);
}
