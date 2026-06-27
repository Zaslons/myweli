import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/providers_repository.dart';

/// `GET /sitemap/providers` — public: the slugs of all listable (non-suspended)
/// providers, so the Next.js web can build `sitemap.xml`. Reuses `query()`
/// (which already hides suspended). Design: docs/design/web-m1-backend-glue.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'method_not_allowed'},
    );
  }

  final providers = await context.read<ProvidersRepository>().query();
  final items = [
    for (final p in providers)
      if (p['slug'] != null) {'slug': p['slug']},
  ];
  return Response.json(body: {'items': items});
}
