import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validation/salon_validation_service.dart';

/// `GET /admin/salon-validations?state=pending|refused|approved&page=&pageSize=`
/// — « Salons à valider » (B0.18, docs/design/salon-go-live-approval.md
/// §3.5, §4.2): one tab of the queue, `{ items, page, pageSize, total }`.
///
/// `state` defaults to `pending` (oldest request first, suspended salons
/// left out — the same number as the overview's
/// `providers.pendingValidation`, which the sidebar reads here with
/// `pageSize=1`); any other value → 400 `invalid_input`. `page` ≥ 1 and
/// `pageSize` 1..100 (default 50, the console's page) are clamped like the
/// other admin lists. Admin-only by the `/admin` middleware (T17).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final q = context.request.uri.queryParameters;
  final state = q['state'] ?? '';
  final page = (int.tryParse(q['page'] ?? '') ?? 1).clamp(1, 1 << 30);
  final pageSize = (int.tryParse(q['pageSize'] ?? '') ?? 50).clamp(1, 100);
  final r = await context.read<SalonValidationService>().queue(
    state: state.isEmpty ? 'pending' : state,
    page: page,
    pageSize: pageSize,
  );
  return salonValidationResponse(r);
}
