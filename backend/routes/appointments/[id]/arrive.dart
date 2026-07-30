import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/appointments/pro_appointment_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /appointments/{id}/arrive` — « Client arrivé » (journal J2).
/// Provider-only + ownership; CONFIRMED bookings, on their calendar day
/// (UTC) only; idempotent. Threat T43. Design: journal-j1-grid.md §2.2.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final r = await context.read<ProAppointmentService>().arrive(
    id,
    principal.userId,
  );
  if (r.ok) return Response.json(body: r.appointment);
  return switch (r.error) {
    'not_found' => jsonError(HttpStatus.notFound, 'not_found'),
    'forbidden' => jsonError(HttpStatus.forbidden, 'forbidden'),
    // Wrong state or wrong day — both are calendar-truth conflicts.
    _ => jsonError(HttpStatus.conflict, r.error!),
  };
}
