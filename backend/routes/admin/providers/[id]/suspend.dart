import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/providers/{id}/suspend` — hide from discovery + block new
/// bookings (optional `{reason}`); login still works. Audited.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  Map<String, dynamic> body = const {};
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    // reason is optional
  }
  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<AdminProviderService>().suspend(
    adminId,
    id,
    body['reason'],
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
