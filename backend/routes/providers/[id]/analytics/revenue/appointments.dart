import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/analytics/revenue_analytics_service.dart';
import 'package:myweli_backend/src/analytics/revenue_query_parser.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /providers/{id}/analytics/revenue/appointments` — the bookings behind
/// one revenue figure, a page at a time, with the salon's name for each
/// client only for a caller who also holds `clients.view`. Owner-only
/// (`finances.view`, threat T85). Design:
/// docs/design/pro-revenue-analytics.md §7.2.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final params = context.request.uri.queryParameters;
  final query = parseRevenueQuery(params);
  final ledger = parseRevenueLedgerParams(params);
  if (query == null || ledger == null) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final r = await context.read<RevenueAnalyticsService>().ledger(
    principal.userId,
    id,
    query,
    status: ledger.status,
    page: ledger.page,
    pageSize: ledger.pageSize,
    asOf: ledger.asOf,
  );
  if (!r.ok) return resultResponse(ok: false, error: r.error, body: null);
  return Response.json(body: r.data, headers: kRevenueNoStore);
}
