import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_enrichment.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/messaging/salon_notifier.dart';
import 'package:myweli_backend/src/providers_repository.dart';
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
    // R6: `?salonId=` selects among the caller's ACTIVE memberships (T55).
    final providerId = await members.salonForRequest(
      principal.userId,
      salonId: context.request.uri.queryParameters['salonId'],
    );
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
      // « Today » is the SALON's calendar day (multi-pays MP1).
      final salon = await context.read<ProvidersRepository>().byId(providerId);
      items = ClientsService.maskContactsOffDay(
        items,
        tzName: salon?['timezone'] as String?,
      );
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
    // The salon's facts ride the payload — identity, contact, deposit
    // coordinates, booking window and `providerStatus`. This route owns the
    // relationship (it is scoped to the caller's own bookings), so it is the
    // one place that may serve them for a salon the public read hides
    // (`salon-state-and-refusals.md` §5, Decision C).
    items = await withProviderFacts(context.read<ProvidersRepository>(), items);
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

  // **Shape before cast.** Every `as String?` below sits OUTSIDE the try above,
  // which only wraps `request.json()` — so `{"notes": 5}` threw a TypeError
  // into the observability middleware and came back as a 500 plus a Sentry
  // event, for what is plainly a bad request. Checked as a set rather than
  // per-field so a future field cannot be added without one.
  for (final k in const [
    'providerId',
    'appointmentDateTime',
    'artistId',
    'notes',
    'depositScreenshotUrl',
  ]) {
    if (body[k] != null && body[k] is! String) {
      return jsonError(HttpStatus.badRequest, 'invalid_input');
    }
  }
  if (body['serviceIds'] != null && body['serviceIds'] is! List) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
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
    // **Written FIRST this time.** Not reachable on this branch — it becomes so
    // the moment the booking-time deposit proof is claimed here (the promotion
    // can fail on an unreachable bucket) — but the two comments below record
    // the last two codes that shipped as bad requests precisely because their
    // arm was written second. This switch has now burned that twice.
    if (result.error == 'storage_unavailable') return storageUnavailable();
    final status = switch (result.error) {
      'provider_not_found' => HttpStatus.notFound,
      'slot_unavailable' => HttpStatus.conflict,
      'provider_suspended' => HttpStatus.conflict,
      // A14d. Explicit, because the fallback below is a 400 — the
      // 409-for-invalid_state convention lives in responses.dart and this
      // switch does not use it, so a new conflict code added without its own
      // case silently ships as a bad request.
      'beyond_horizon' => HttpStatus.conflict,
      'too_soon' => HttpStatus.conflict,
      // Row 82, and the comment above earned itself: this arm was written
      // second, after the gate caught the new code shipping as a 400.
      'provider_not_published' => HttpStatus.conflict,
      // Per-identity rate limit. Written before anything can emit it, which is
      // the whole reason this arm exists — the three codes above each shipped
      // as a 400 first because their case was written second.
      // docs/design/backend-identity-rate-limits.md §6.
      'rate_limited' => HttpStatus.tooManyRequests,
      _ => HttpStatus.badRequest,
    };
    return jsonError(status, result.error!);
  }
  // The salon team learns about the new (pending) request — this is the
  // CLIENT's booking route; salon-entered bookings ride
  // `POST /providers/{id}/appointments` and never notify the salon itself.
  unawaited(
    context.read<SalonNotifier>().notify(
      result.appointment,
      SalonEvent.newBooking,
    ),
  );
  return Response.json(
    statusCode: HttpStatus.created,
    body: result.appointment,
  );
}
