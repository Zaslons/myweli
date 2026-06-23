import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /appointments/{id}` — the caller's own appointment. Ownership enforced:
/// another user's appointment is 403, not 404-leaked (docs/BACKEND.md §3.3).
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final appointment = await context.read<AppointmentRepository>().byId(id);
  if (appointment == null) {
    return jsonError(HttpStatus.notFound, 'not_found');
  }
  if (appointment['userId'] != principal.userId) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  return Response.json(body: appointment);
}
