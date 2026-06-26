import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/moderation_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/reviews/{id}/hide` — hide a review (optional `{reason}`); it
/// leaves the public feed + rating, and its open reports are resolved. Audited.
/// Design: docs/design/admin-console.md.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  Map<String, dynamic> body = const {};
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    // reason is optional
  }
  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<ModerationService>().hide(
    adminId,
    id,
    body['reason'],
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
