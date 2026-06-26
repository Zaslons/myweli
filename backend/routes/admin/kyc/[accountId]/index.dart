import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_kyc_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/kyc/{accountId}` — full account + submitted docs with short-lived
/// signed-GET view URLs. Design: docs/design/admin-console.md.
Future<Response> onRequest(RequestContext context, String accountId) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final r = await context.read<AdminKycService>().detail(accountId);
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
