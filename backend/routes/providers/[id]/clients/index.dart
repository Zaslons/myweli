import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `/providers/{id}/clients` — the salon client base (module `clients` C1).
/// `GET` lists (paginated, `?query=&tag=`); `POST` adds a client manually
/// (phone REQUIRED — the dedupe/linking key). Provider-only + ownership
/// (capability `clients.view`); list reads are audited. Design:
/// docs/design/clients-c1.md.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  switch (context.request.method) {
    case HttpMethod.get:
      return _list(context, principal.userId, id);
    case HttpMethod.post:
      return _create(context, principal.userId, id);
    default:
      return methodNotAllowed();
  }
}

Future<Response> _list(
  RequestContext context,
  String accountId,
  String providerId,
) async {
  final params = context.request.uri.queryParameters;
  final r = await context.read<ClientsService>().list(
    accountId,
    providerId,
    query: params['query'],
    tag: params['tag'],
    page: int.tryParse(params['page'] ?? '') ?? 1,
    pageSize: int.tryParse(params['pageSize'] ?? '') ?? 20,
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}

Future<Response> _create(
  RequestContext context,
  String accountId,
  String providerId,
) async {
  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final name = (body['name'] as String?)?.trim() ?? '';
  final phone = (body['phone'] as String?)?.trim() ?? '';
  if (name.isEmpty) return jsonError(HttpStatus.badRequest, 'invalid_input');
  if (!isValidE164(phone)) {
    return jsonError(HttpStatus.badRequest, 'invalid_phone');
  }

  final r = await context.read<ClientsService>().addClient(
    accountId,
    providerId,
    name: name,
    phone: phone,
    note: body['note'] as String?,
  );
  if (!r.ok) {
    if (r.error == 'client_exists') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'client_exists', ...?r.data},
      );
    }
    return resultResponse(ok: false, error: r.error, body: null);
  }
  return Response.json(statusCode: HttpStatus.created, body: r.data);
}
