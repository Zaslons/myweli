import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/appointments/journal_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /providers/{id}/journal?date=YYYY-MM-DD` — the journal day view in
/// one payload (module `journal` J1). Provider-only + ownership (threat T41).
/// Design: docs/design/journal-j1-grid.md §2.1.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final raw = context.request.uri.queryParameters['date'];
  final date = raw == null ? null : DateTime.tryParse(raw);
  if (date == null) {
    return jsonError(HttpStatus.badRequest, 'invalid_date');
  }

  final r = await context.read<JournalService>().dayFor(
    principal.userId,
    id,
    date,
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
