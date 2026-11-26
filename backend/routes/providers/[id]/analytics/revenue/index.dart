import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/analytics/revenue_analytics_service.dart';
import 'package:myweli_backend/src/analytics/revenue_query_parser.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /providers/{id}/analytics/revenue` — the salon's revenue analytics:
/// one period and its comparison, the figures by currency, the chart, and
/// the revenue by collaborateur, prestation and channel. Owner-only
/// (`finances.view`, threat T85). Design:
/// docs/design/pro-revenue-analytics.md §7.1.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final query = parseRevenueQuery(context.request.uri.queryParameters);
  if (query == null) return jsonError(HttpStatus.badRequest, 'invalid_input');

  final r = await context.read<RevenueAnalyticsService>().revenue(
    principal.userId,
    id,
    query,
  );
  if (!r.ok) return resultResponse(ok: false, error: r.error, body: null);
  return Response.json(body: r.data, headers: kRevenueNoStore);
}
