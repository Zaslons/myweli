import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_kyc_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/kyc/{accountId}/approve` — verify the provider (audited).
/// Design: docs/design/admin-console.md.
Future<Response> onRequest(RequestContext context, String accountId) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<AdminKycService>().approve(adminId, accountId);
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
