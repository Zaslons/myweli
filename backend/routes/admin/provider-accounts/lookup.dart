import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_provider_account_service.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/provider-accounts/lookup` `{email}` — find the Pro account
/// behind one EXACT address, before a support erase (B0.25's server half).
/// Read-only, not audited.
///
/// **POST, the address in the body:** a `GET ?email=` would put it in Cloud
/// Run's request log, which keeps the URL.
///
/// 200 `{accountId, email, createdAt, ownedSalons, memberships}` — nothing
/// else: no name, phone, address or KYC. 400 `invalid_body` (not a JSON
/// object, or `email` not a string) · `invalid_input` (trimmed, 3–254
/// characters, exactly one `@`). 401 / 403 (the `/admin` gate). 404
/// `not_found` (no account at that address — never a prefix, never a list).
///
/// Design: docs/design/admin-pro-account-erase.md §3.2; threat T83.
Future<Response> onRequest(RequestContext context) async {
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
  final email = optionalString(body, 'email');

  final r = await context.read<AdminProviderAccountService>().lookup(email);
  if (r.ok) return Response.json(body: r.data);
  return switch (r.error) {
    'invalid_input' => jsonError(HttpStatus.badRequest, 'invalid_input'),
    'not_found' => jsonError(HttpStatus.notFound, 'not_found'),
    final other => throw StateError('unmapped lookup outcome: $other'),
  };
}
