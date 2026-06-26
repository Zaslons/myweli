import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/appointments/appointment_lifecycle_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/messaging/booking_notifier.dart';
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /appointments/{id}/cancel` — cancel the caller's own booking.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final result = await context.read<AppointmentLifecycleService>().cancel(
    id,
    principal.userId,
  );
  if (result.ok) {
    unawaited(
      context.read<BookingNotifier>().notify(
        result.appointment,
        MessageTemplate.cancelled,
      ),
    );
  }
  return _respond(result);
}

Response _respond(LifecycleResult result) {
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
