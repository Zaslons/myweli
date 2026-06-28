import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /me/provider` — the signed-in provider's own account + the salon it
/// manages. Provider-scoped: the salon id is resolved from the account (never a
/// client-supplied id), so a provider only ever reads its own (BACKEND.md §3.3,
/// threat T29). Anon → 401; non-provider or unlinked account → 403; missing
/// salon → 404.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

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
  final providerId = account?.providerId;
  if (account == null || providerId == null) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final provider = await context.read<ProvidersRepository>().byId(providerId);
  if (provider == null) {
    return jsonError(HttpStatus.notFound, 'not_found');
  }

  return Response.json(
    body: {'account': account.toJson(), 'provider': provider},
  );
}
