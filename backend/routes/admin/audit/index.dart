import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /admin/audit` — the append-only admin action log (paginated, filterable
/// by actor/action). Design: docs/design/admin-console.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final q = context.request.uri.queryParameters;
  final page = (int.tryParse(q['page'] ?? '') ?? 1).clamp(1, 1 << 30);
  final pageSize = (int.tryParse(q['pageSize'] ?? '') ?? 20).clamp(1, 100);
  final r = await context.read<AuditLogRepository>().list(
    page: page,
    pageSize: pageSize,
    actor: q['actor'],
    action: q['action'],
  );
  return Response.json(
    body: {
      'items': r.items,
      'page': page,
      'pageSize': pageSize,
      'total': r.total,
    },
  );
}
