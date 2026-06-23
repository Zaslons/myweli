import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/providers_repository.dart';

/// `GET /providers/{id}` — full provider detail; backs `getProviderById`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'method_not_allowed'},
    );
  }

  final provider = await context.read<ProvidersRepository>().byId(id);
  if (provider == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'not_found'},
    );
  }

  return Response.json(body: provider);
}
