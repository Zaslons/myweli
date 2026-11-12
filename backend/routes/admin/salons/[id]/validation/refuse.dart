import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validation/salon_validation_service.dart';

/// `POST /admin/salons/{id}/validation/refuse` `{code, note?}` — MyWeli
/// refuses the request, with a reason the salon reads (B0.18,
/// docs/design/salon-go-live-approval.md §3.3, §4.3).
///
/// 200 `{validation}`. 400 `invalid_body` (not a JSON object) ·
/// `invalid_input` (a code outside the closed list, or a note that is not
/// text) · `note_required` (`other` without a note) · `note_too_long` (over
/// 500 code points). 404. 409 `validation_not_pending` (only a `pending`
/// request can be refused; another decision won). Audited (`salon.refuse`,
/// the CODE only — never the note). Admin-only by the `/admin` middleware
/// (T17).
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
  final r = await context.read<SalonValidationService>().refuse(
    id,
    code: body['code'],
    note: body['note'],
    adminId: adminId,
  );
  return salonValidationResponse(r);
}
