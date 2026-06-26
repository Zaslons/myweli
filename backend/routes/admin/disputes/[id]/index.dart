import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/dispute_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/disputes/{id}` — the dispute + its booking + a signed
/// deposit-screenshot URL (evidence). Design: docs/design/admin-console.md §12.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<DisputeService>().detail(adminId, id);
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
