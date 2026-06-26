import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_kyc_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/kyc` — the queue of providers awaiting verification (paginated).
/// Design: docs/design/admin-console.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final q = context.request.uri.queryParameters;
  final page = (int.tryParse(q['page'] ?? '') ?? 1).clamp(1, 1 << 30);
  final pageSize = (int.tryParse(q['pageSize'] ?? '') ?? 20).clamp(1, 100);
  final r = await context.read<AdminKycService>().queue(
    page: page,
    pageSize: pageSize,
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
