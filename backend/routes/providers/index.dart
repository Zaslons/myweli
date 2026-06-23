import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/providers_repository.dart';

/// `GET /providers` — search/list, paginated. Backs `getProviders` /
/// `getFeaturedProviders` (the latter just reads the first page sorted by
/// rating) in the app's `ProviderServiceInterface`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'method_not_allowed'},
    );
  }

  final params = context.request.uri.queryParameters;
  final page = (int.tryParse(params['page'] ?? '') ?? 1).clamp(1, 100000);
  final pageSize = (int.tryParse(params['pageSize'] ?? '') ?? 20).clamp(1, 50);

  final all = await context.read<ProvidersRepository>().query(
    q: params['q'],
    commune: params['commune'],
    category: params['category'],
  );

  final start = (page - 1) * pageSize;
  final items = start >= all.length
      ? const <Map<String, dynamic>>[]
      : all.sublist(start, (start + pageSize).clamp(0, all.length));

  return Response.json(
    body: {
      'items': items,
      'page': page,
      'pageSize': pageSize,
      'total': all.length,
    },
  );
}
