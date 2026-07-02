import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `/me` — the signed-in user's own account. Protected: the principal comes
/// from the access token, so a caller can only ever read/mutate themselves
/// (docs/BACKEND.md §3.3). GET reads the profile; PATCH updates profile fields;
/// DELETE removes it.
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
      final ok = await repo.deleteUser(principal.userId);
      if (!ok) return jsonError(HttpStatus.notFound, 'not_found');
      return Response(statusCode: HttpStatus.noContent);

    default:
      return methodNotAllowed();
  }
}
