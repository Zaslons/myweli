import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_lifecycle_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/http/body_fields.dart';
import 'package:myweli_backend/src/messaging/booking_notifier.dart';
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/messaging/salon_notifier.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /appointments/{id}/reschedule` — move a booking to a new time.
/// **Role-aware** (design: docs/design/pro-reschedule.md): a `user` reschedules
/// their own booking; a `provider` reschedules one of its own salon's bookings
/// (ownership by linked `providerId`). Both re-validate the new slot; deposit +
/// balance carry over unchanged.
///
/// Notifications: the client always hears (`BookingNotifier` « Rendez-vous
/// reporté »). The SALON hears only when the CLIENT moved it — with the slot it
/// left (docs/design/salon-client-reschedule-notify.md §2); a salon moving its
/// own booking never notifies itself, the rule manual bookings already follow.
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
  final raw = optionalString(body, 'newDateTime');
  // Drag across the journal grid's columns (J1); validated in the service.
  // Read with the date — before any rule or lookup — so a wrong JSON type is
  // refused the same way whoever sends it (docs/design/phone-leftovers.md §3).
  final artistId = optionalString(body, 'artistId')?.trim();
  final newDateTime = raw == null ? null : DateTime.tryParse(raw);
  if (newDateTime == null) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final lifecycle = context.read<AppointmentLifecycleService>();
  final LifecycleResult result;
  // Set on the client's own move only — the one the salon is told about.
  RescheduleResult? clientMove;
  if (principal.role == 'provider') {
    // Module `access` R1: the acting salon comes from the membership layer;
    // the lifecycle service re-checks it against the appointment.
    final members = context.read<MembershipService>();
    // R6: `?salonId=` selects among the caller's ACTIVE memberships (T55);
    // the lifecycle service still cross-checks the appointment's salon.
    final managedProviderId = await members.salonForRequest(
      principal.userId,
      salonId: context.request.uri.queryParameters['salonId'],
    );
    if (managedProviderId == null ||
        !await members.can(
          principal.userId,
          managedProviderId,
          Cap.journalManageAll,
        )) {
      return jsonError(HttpStatus.forbidden, 'forbidden');
    }
    result = await lifecycle.rescheduleByProvider(
      id,
      managedProviderId,
      newDateTime,
      artistId: artistId,
    );
  } else {
    final move = clientMove = await lifecycle.reschedule(
      id,
      principal.userId,
      newDateTime,
    );
    result = (ok: move.ok, error: move.error, appointment: move.appointment);
  }
  if (result.ok) {
    unawaited(
      context.read<BookingNotifier>().notify(
        result.appointment,
        MessageTemplate.rescheduled,
      ),
    );
    if (clientMove != null) {
      unawaited(
        context.read<SalonNotifier>().notify(
          result.appointment,
          SalonEvent.clientRescheduled,
          previousAppointmentDate: clientMove.previousAppointmentDate,
        ),
      );
    }
    return Response.json(body: result.appointment);
  }
  switch (result.error) {
    case 'not_found':
      return jsonError(HttpStatus.notFound, 'not_found');
    case 'forbidden':
      return jsonError(HttpStatus.forbidden, 'forbidden');
    case 'invalid_artist':
      return jsonError(HttpStatus.badRequest, 'invalid_artist');
    default:
      return jsonError(HttpStatus.conflict, result.error!);
  }
}
