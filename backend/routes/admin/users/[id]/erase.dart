import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_user_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `DELETE /admin/users/{id}/erase` — erase a consumer account. Audited,
/// irreversible.
///
/// Runs the same cascade as `DELETE /me` (`UserErasureService`, threat T59).
/// Exists because an erasure request arrives by e-mail, from someone who may no
/// longer be able to sign in — the privacy policy promises erasure to them too.
///
/// **DELETE on a sub-path, not on `/admin/users/{id}`.** That path already
/// serves the read-only support view, and putting an irreversible action on the
/// same URL a support agent loads to *look* at someone is how a mis-typed verb
/// becomes an incident. The verb is still DELETE, because that is what it does.
///
/// Design: docs/design/account-deletion-erasure.md §12.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.delete) return methodNotAllowed();

  Map<String, dynamic> body = const {};
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    // reason is optional — same shape as ban.
  }

  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<AdminUserService>().erase(
    adminId,
    id,
    body['reason'],
  );
  if (r.ok) return Response(statusCode: HttpStatus.noContent);

  // Same mapping as `DELETE /me`: an unsettled agenda is a CONFLICT the admin
  // can resolve by cancelling, not a missing resource.
  return r.error == 'future_bookings'
      ? jsonError(HttpStatus.conflict, 'future_bookings')
      : jsonError(HttpStatus.notFound, r.error ?? 'not_found');
}
