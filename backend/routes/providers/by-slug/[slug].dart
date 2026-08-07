import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/salon_visibility.dart';

/// `GET /providers/by-slug/{slug}` — public provider page read for the web
/// (`myweli.ci/<slug>`). Mirrors `GET /providers/{id}` but resolves by URL slug;
/// embeds the latest reviews. Design: docs/design/web-m1-backend-glue.md.
Future<Response> onRequest(RequestContext context, String slug) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'method_not_allowed'},
    );
  }

  final provider = await context.read<ProvidersRepository>().bySlug(slug);
  // Decision C. This was the third spelling of one rule, and the one that got
  // it wrong: it excluded `draft` only, so a SUSPENDED salon stayed publicly
  // readable by slug — the route the web salon page uses.
  if (!isPublicSalon(provider)) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'not_found'},
    );
  }

  final reviews = await context.read<ReviewsRepository>().recentForProvider(
    provider!['id'] as String,
    10,
  );
  return Response.json(body: {...provider, 'reviews': reviews});
}
