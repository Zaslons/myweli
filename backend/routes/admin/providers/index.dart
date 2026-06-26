import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/providers?status=&q=` — provider management list (incl.
/// suspended), paginated. Design: docs/design/admin-console.md §12.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final p = context.request.uri.queryParameters;
  final page = (int.tryParse(p['page'] ?? '') ?? 1).clamp(1, 1 << 30);
  final pageSize = (int.tryParse(p['pageSize'] ?? '') ?? 20).clamp(1, 100);
  final r = await context.read<AdminProviderService>().list(
    status: p['status'],
    q: p['q'],
    page: page,
    pageSize: pageSize,
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
