import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/appointments/pro_appointment_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /appointments/{id}/accept` — the salon confirms a pending booking.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final result = await context.read<ProAppointmentService>().accept(
    id,
    principal.userId,
  );
  return resultResponse(
    ok: result.ok,
    error: result.error,
    body: result.appointment,
  );
}
