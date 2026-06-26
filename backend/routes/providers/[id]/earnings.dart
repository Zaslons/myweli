import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/provider_earnings_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /providers/{id}/earnings?startDate=&endDate=` — the salon's realized
/// earnings (total + transactions, completed only). Provider-only and
/// ownership-scoped. Design: docs/design/provider-earnings.md.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final q = context.request.uri.queryParameters;
  DateTime? start;
  DateTime? end;
  if (q['startDate'] != null) {
    start = DateTime.tryParse(q['startDate']!);
    if (start == null) return jsonError(HttpStatus.badRequest, 'invalid_input');
  }
  if (q['endDate'] != null) {
    end = DateTime.tryParse(q['endDate']!);
    if (end == null) return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final r = await context.read<ProviderEarningsService>().earningsFor(
    principal.userId,
    id,
    startDate: start?.toUtc(),
    endDate: end?.toUtc(),
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
