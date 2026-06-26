import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';

/// `GET /providers/{id}` — full provider detail; backs `getProviderById`. The
/// latest reviews are embedded (a bounded preview); the full paginated list is
/// `GET /providers/{id}/reviews`. Design: docs/design/consumer-reviews.md.
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

  final reviews = await context.read<ReviewsRepository>().recentForProvider(
    id,
    10,
  );
  return Response.json(body: {...provider, 'reviews': reviews});
}
