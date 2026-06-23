import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `/appointments` — the signed-in user's appointments.
/// `POST` books one (server-priced, created `pending`); `GET` lists their own.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }

  switch (context.request.method) {
    case HttpMethod.post:
      return _book(context, principal.userId);
    case HttpMethod.get:
      final status = context.request.uri.queryParameters['status'];
      final items = await context.read<AppointmentRepository>().listForUser(
        principal.userId,
        status: status,
      );
      return Response.json(
        body: {
          'items': items,
          'page': 1,
          'pageSize': items.length,
          'total': items.length,
        },
      );
    default:
      return methodNotAllowed();
  }
}

Future<Response> _book(RequestContext context, String userId) async {
  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final providerId = (body['providerId'] as String?)?.trim() ?? '';
  final serviceIds =
      (body['serviceIds'] as List?)?.whereType<String>().toList() ?? const [];
  final dateRaw = body['appointmentDateTime'] as String?;
  final dateTime = dateRaw == null ? null : DateTime.tryParse(dateRaw);
  if (providerId.isEmpty || serviceIds.isEmpty || dateTime == null) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final result = await context.read<BookingService>().book(
    userId: userId,
    providerId: providerId,
    serviceIds: serviceIds,
    appointmentDateTime: dateTime,
    artistId: (body['artistId'] as String?)?.trim(),
    notes: body['notes'] as String?,
    depositScreenshotUrl: body['depositScreenshotUrl'] as String?,
  );
  if (!result.ok) {
    final status = switch (result.error) {
      'provider_not_found' => HttpStatus.notFound,
      'slot_unavailable' => HttpStatus.conflict,
      _ => HttpStatus.badRequest,
    };
    return jsonError(status, result.error!);
  }
  return Response.json(
    statusCode: HttpStatus.created,
    body: result.appointment,
  );
}
