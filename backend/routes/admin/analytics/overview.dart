import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/analytics_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/analytics/overview` — marketplace-health KPI snapshot
/// (read-only). Design: docs/design/admin-console.md §13.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final r = await context.read<AnalyticsService>().overview();
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
