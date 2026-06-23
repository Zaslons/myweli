import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/appointments/appointment_lifecycle_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /appointments/{id}/reschedule` — move the caller's booking to a new
/// time. Deposit + balance carry over unchanged.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }
  final raw = body['newDateTime'] as String?;
  final newDateTime = raw == null ? null : DateTime.tryParse(raw);
  if (newDateTime == null) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final result = await context.read<AppointmentLifecycleService>().reschedule(
    id,
    principal.userId,
    newDateTime,
  );
  if (result.ok) return Response.json(body: result.appointment);
  switch (result.error) {
    case 'not_found':
      return jsonError(HttpStatus.notFound, 'not_found');
    case 'forbidden':
      return jsonError(HttpStatus.forbidden, 'forbidden');
    default:
      return jsonError(HttpStatus.conflict, result.error!);
  }
}
