import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/moderation_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/reviews/hidden` — currently-hidden reviews (the "Avis masqués"
/// view; restore entry point), paginated. Design: docs/design/admin-console.md §12.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final q = context.request.uri.queryParameters;
  final page = (int.tryParse(q['page'] ?? '') ?? 1).clamp(1, 1 << 30);
  final pageSize = (int.tryParse(q['pageSize'] ?? '') ?? 20).clamp(1, 100);
  final r = await context.read<ModerationService>().hiddenQueue(
    page: page,
    pageSize: pageSize,
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
