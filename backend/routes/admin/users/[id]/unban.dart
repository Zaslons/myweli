import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_user_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/users/{id}/unban` — restore login. Audited.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<AdminUserService>().unban(adminId, id);
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
