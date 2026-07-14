import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/deposit_service.dart';
import 'package:myweli_backend/src/messaging/booking_notifier.dart';
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/messaging/salon_notifier.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /appointments/{id}/deposit` — the consumer attaches (or replaces) the
/// deposit-payment screenshot on their own pending booking (pay-later). Body:
/// `{ "screenshotKey": "deposit/{userId}/…" }` (uploaded via
/// `POST /uploads/sign?purpose=deposit`). Design: docs/design/consumer-deposit.md.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'user') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return jsonError(HttpStatus.badRequest, 'invalid_body');
  }

  final r = await context.read<DepositService>().submit(
    principal.userId,
    id,
    body['screenshotKey'],
  );
  if (r.ok) {
    unawaited(
      context.read<BookingNotifier>().notify(
        r.data as Map<String, dynamic>?,
        MessageTemplate.depositReceived,
      ),
    );
    // The salon must know a justificatif landed — it gates the confirmation.
    unawaited(
      context.read<SalonNotifier>().notify(
        r.data as Map<String, dynamic>?,
        SalonEvent.depositSubmitted,
      ),
    );
    return Response.json(body: r.data);
  }
  switch (r.error) {
    case 'not_found':
      return jsonError(HttpStatus.notFound, 'not_found');
    case 'forbidden':
      return jsonError(HttpStatus.forbidden, 'forbidden');
    case 'invalid_state':
      return jsonError(HttpStatus.conflict, 'invalid_state');
    default:
      return jsonError(HttpStatus.badRequest, r.error ?? 'invalid_input');
  }
}
