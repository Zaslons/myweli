import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/reviews_service.dart';

/// `GET /providers/{id}/reviews?page=&pageSize=` — public, paginated, newest
/// first. Design: docs/design/consumer-reviews.md.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final q = context.request.uri.queryParameters;
  final page = int.tryParse(q['page'] ?? '') ?? 1;
  final pageSize = int.tryParse(q['pageSize'] ?? '') ?? 20;

  final r = await context.read<ReviewsService>().list(
    id,
    page: page,
    pageSize: pageSize,
  );
  return Response.json(
    body: {
      'items': r.items,
      'page': r.page,
      'pageSize': r.pageSize,
      'total': r.total,
    },
  );
}
