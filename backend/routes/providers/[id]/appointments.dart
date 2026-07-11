import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validators.dart';

/// `POST /providers/{id}/appointments` — a **salon-entered** booking (walk-in,
/// logged-after-the-fact, or a phone booking for a future date). Provider-only
/// and ownership-scoped; server-priced; created `confirmed` with no online
/// deposit. Design: docs/design/pro-manual-booking.md.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  // Authorize (module `access` R1): manual booking = whole-journal manage.
  final allowed = await context.read<MembershipService>().can(
    principal.userId,
    id,
    Cap.journalManageAll,
  );
  if (!allowed) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final serviceIds =
      (body['serviceIds'] as List?)?.whereType<String>().toList() ?? const [];
  final dateRaw = body['appointmentDateTime'] as String?;
  final dateTime = dateRaw == null ? null : DateTime.tryParse(dateRaw);
  if (serviceIds.isEmpty || dateTime == null) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final clientName = (body['clientName'] as String?)?.trim();
  final clientPhone = (body['clientPhone'] as String?)?.trim();
  if (clientPhone != null &&
      clientPhone.isNotEmpty &&
      !isValidE164(clientPhone)) {
    return jsonError(HttpStatus.badRequest, 'invalid_phone');
  }

  final result = await context.read<BookingService>().bookManual(
    providerId: id,
    serviceIds: serviceIds,
    appointmentDateTime: dateTime,
    artistId: (body['artistId'] as String?)?.trim(),
    clientName: (clientName == null || clientName.isEmpty) ? null : clientName,
    clientPhone: (clientPhone == null || clientPhone.isEmpty)
        ? null
        : clientPhone,
    notes: body['notes'] as String?,
  );
  if (!result.ok) {
    final status = switch (result.error) {
      'provider_not_found' => HttpStatus.notFound,
      'slot_unavailable' => HttpStatus.conflict,
      'provider_suspended' => HttpStatus.conflict,
      _ => HttpStatus.badRequest,
    };
    return jsonError(status, result.error!);
  }
  return Response.json(
    statusCode: HttpStatus.created,
    body: result.appointment,
  );
}
