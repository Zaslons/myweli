import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/privacy/user_erasure_service.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `/me` — the signed-in user's own account. Protected: the principal comes
/// from the access token, so a caller can only ever read/mutate themselves
/// (docs/BACKEND.md §3.3). GET reads the profile; PATCH updates profile fields;
/// DELETE erases it — future pending/confirmed bookings → 409
/// `future_bookings` (settle the agenda first, exactly as `/me/provider`
/// does). See `UserErasureService` for what erasure means, and
/// docs/design/account-deletion-erasure.md for why each table gets the verb
/// it gets.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }

  final repo = context.read<AuthRepository>();

  switch (context.request.method) {
    case HttpMethod.get:
      final user = await repo.userById(principal.userId);
      if (user == null) {
        return jsonError(HttpStatus.notFound, 'not_found');
      }
      return Response.json(body: user.toJson());

    case HttpMethod.patch:
      final Map<String, dynamic> body;
      try {
        body = await context.request.json() as Map<String, dynamic>;
      } catch (_) {
        return jsonError(HttpStatus.badRequest, 'invalid_body');
      }
      // Contact phone (auth overhaul: phone is a contact attribute, not the
      // identity — unverified until proven via SMS later). '' clears it.
      final phone = body['phone'] as String?;
      if (phone != null && phone.isNotEmpty && !isValidE164(phone)) {
        return jsonError(HttpStatus.badRequest, 'invalid_phone');
      }
      final updated = await repo.updateUser(
        principal.userId,
        name: body['name'] as String?,
        email: body['email'] as String?,
        avatarUrl: body['avatarUrl'] as String?,
        phone: phone,
      );
      if (updated == null) {
        return jsonError(HttpStatus.notFound, 'not_found');
      }
      return Response.json(body: updated.toJson());

    case HttpMethod.delete:
      // **Consumers only, and the gate is not cosmetic.** `device_tokens` and
      // `notifications` hold PROVIDER rows too — `user_id` is whatever the
      // token's `sub` is, with a `role` column beside it — so a cascade keyed on
      // `user_id` alone would reach across the consumer/pro boundary if a pro
      // token ever arrived here. Pros delete through `/me/provider`, which
      // settles their agenda and unpublishes their salons first.
      if (principal.role != 'user') {
        return jsonError(HttpStatus.forbidden, 'forbidden');
      }
      // The whole cascade lives in the service (L1, threat T59) — including the
      // T48 client-base anonymisation this route used to run itself, which sat
      // AFTER the identity delete and could therefore be orphaned by a throw.
      final res = await context.read<UserErasureService>().eraseUser(
        principal.userId,
      );
      if (!res.ok) {
        // Same mapping as `/me/provider` (`me/provider/index.dart:139-141`):
        // an unsettled agenda is a CONFLICT the caller can resolve, not a
        // missing resource. Anything else here is a vanished user.
        return res.error == 'future_bookings'
            ? jsonError(HttpStatus.conflict, 'future_bookings')
            : jsonError(HttpStatus.notFound, res.error ?? 'not_found');
      }
      return Response(statusCode: HttpStatus.noContent);

    default:
      return methodNotAllowed();
  }
}
