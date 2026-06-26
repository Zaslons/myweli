import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/appointments/appointment_lifecycle_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /appointments/{id}/reschedule` — move a booking to a new time.
/// **Role-aware** (design: docs/design/pro-reschedule.md): a `user` reschedules
/// their own booking; a `provider` reschedules one of its own salon's bookings
/// (ownership by linked `providerId`). Both re-validate the new slot; deposit +
/// balance carry over unchanged.
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

  final lifecycle = context.read<AppointmentLifecycleService>();
  final LifecycleResult result;
  if (principal.role == 'provider') {
    final account = await context.read<ProviderAuthRepository>().accountById(
      principal.userId,
    );
    final managedProviderId = account?.providerId;
    if (managedProviderId == null) {
      return jsonError(HttpStatus.forbidden, 'forbidden');
    }
    result = await lifecycle.rescheduleByProvider(
      id,
      managedProviderId,
      newDateTime,
    );
  } else {
    result = await lifecycle.reschedule(id, principal.userId, newDateTime);
  }
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
