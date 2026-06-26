import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_user_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/users/{id}` — read-only support view: the user + recent bookings.
/// Design: docs/design/admin-console.md §12.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final r = await context.read<AdminUserService>().detail(id);
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
