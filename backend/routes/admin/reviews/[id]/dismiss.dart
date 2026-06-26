import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/moderation_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/reviews/{id}/dismiss` — the review is fine: resolve its open
/// reports without hiding it. Audited. Design: docs/design/admin-console.md.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<ModerationService>().dismissReports(adminId, id);
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
