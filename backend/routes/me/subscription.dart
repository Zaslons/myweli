import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/subscription/subscription.dart';

/// `GET /me/subscription` — the signed-in provider's plan & trial status,
/// **derived** from the account's signup date (no billing state in V1).
/// Self-scoped to the token's provider account; provider role required.
/// Design: docs/design/pro-subscription.md (FR-PRO-SUB-001).
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

  final sub = computeSubscription(
    accountCreatedAt: account.createdAt,
    now: DateTime.now().toUtc(),
  );
  return Response.json(body: sub.toJson());
}
