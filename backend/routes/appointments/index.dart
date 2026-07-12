import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `/appointments`.
/// `POST` books one (server-priced, created `pending`). `GET` lists the
/// caller's — a **user** sees their own bookings; a **provider** sees its
/// salon's (scoped to the account's linked `providerId`; an unlinked provider
/// → 403). Optional `?status=` filter.
Future<Response> onRequest(RequestContext context) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }

  switch (context.request.method) {
    case HttpMethod.post:
      return _book(context, principal.userId);
    case HttpMethod.get:
      return _list(context, principal);
    default:
      return methodNotAllowed();
  }
}

Future<Response> _list(RequestContext context, Principal principal) async {
  final status = context.request.uri.queryParameters['status'];
  final repo = context.read<AppointmentRepository>();

  List<Map<String, dynamic>> items;
  if (principal.role == 'provider') {
    // Resolve the caller's acting salon via the membership layer (module
    // `access` R1) and the journal read scope (R4a). Deny by default;
    // own-scope members (Collaborateur, T40) get their artist's bookings
    // only, with off-day contact masking (§11.2).
    final members = context.read<MembershipService>();
    final providerId = await members.activeSalonFor(principal.userId);
    if (providerId == null) {
      return jsonError(HttpStatus.forbidden, 'forbidden');
    }
    final scope = await members.journalScope(
      principal.userId,
      providerId,
      manage: false,
    );
    if (!scope.all && scope.ownArtistId == null) {
      return jsonError(HttpStatus.forbidden, 'forbidden');
    }
    var rows = await repo.listForProvider(providerId, status: status);
    if (!scope.all) {
      rows = [
        for (final a in rows)
          if (a['artistId'] == scope.ownArtistId) a,
      ];
    }
    items = await context.read<ClientsService>().enrichForProvider(
      providerId,
      rows,
    );
    if (!scope.all) {
      items = ClientsService.maskContactsOffDay(items);
    }
  } else {
    // Auto-sync (FR-APPT-008): also surface provider-entered bookings made to
    // this account's **verified** phone (resolved server-side — never from
    // the request). Unverified contact phones don't match (auth overhaul:
    // phone is contact data until proven via SMS). Design:
    // docs/design/appointment-auto-sync.md + auth-social-email.md.
    final account = await context.read<AuthRepository>().userById(
      principal.userId,
    );
    items = await repo.listForUser(
      principal.userId,
      status: status,
      matchPhone: (account?.phoneVerified ?? false)
          ? account?.phoneNumber
          : null,
    );
  }

  return Response.json(
    body: {
      'items': items,
      'page': 1,
      'pageSize': items.length,
      'total': items.length,
    },
  );
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
