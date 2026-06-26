import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/providers/{id}` — read-only support view: the provider + its
/// recent bookings. Design: docs/design/admin-console.md §12.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final r = await context.read<AdminProviderService>().detail(id);
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
