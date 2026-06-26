import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/analytics_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/analytics/north-star?weeks=12` — completed bookings per week ×
/// commune (read-only). Design: docs/design/admin-console.md §13.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final weeks =
      int.tryParse(context.request.uri.queryParameters['weeks'] ?? '') ?? 12;
  final r = await context.read<AnalyticsService>().northStar(weeks: weeks);
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
