import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/provider_account_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';

/// `GET /me/provider` — the signed-in provider's own account + the salon it
/// acts in + the caller's MEMBERSHIP (role, server-computed capabilities,
/// staff artist link — module `access` R4a). The salon DEFAULTS from the
/// account (owner) or the active membership (member); R6: an explicit
/// `?salonId=` selects among the caller's ACTIVE memberships — any invalid
/// selection (never-member, revoked-there, unknown) is a uniform 403
/// `forbidden` (no membership-existence oracle, threat T55) and never
/// auto-provisions. Anon → 401; non-provider or unlinked account → 403
/// `forbidden`; a REVOKED member on the NO-PARAM path (memberships exist,
/// none active) → 403 `not_a_member` (the session-level revoked signal —
/// a per-salon denial must never sign a user out of their other salons).
///
/// `DELETE /me/provider` — erase the ACCOUNT identity (audit 11.5, AUTH-004
/// for pros; threat T53): future pending/confirmed bookings → 409
/// `future_bookings`; the salon is UNPUBLISHED (`status → draft`, hidden by
/// T51 while history keeps resolving); the account row + OTP state + every
/// refresh token are deleted. Design:
/// docs/design/pro-account-deletion-export.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get &&
      context.request.method != HttpMethod.delete) {
    return methodNotAllowed();
  }

  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  if (context.request.method == HttpMethod.delete) {
    return _delete(context, principal.userId);
  }

  var account = await context.read<ProviderAuthRepository>().accountById(
    principal.userId,
  );
  if (account == null) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  final members = context.read<MembershipService>();
  final selectedSalonId = context.request.uri.queryParameters['salonId'] ?? '';
  String? providerId;
  if (selectedSalonId.isNotEmpty) {
    // R6 explicit selection: an ACTIVE membership in the selected salon or a
    // uniform 403 — no self-heal/provisioning, no not_a_member distinction.
    providerId = await members.salonForRequest(
      account.id,
      salonId: selectedSalonId,
    );
    if (providerId == null) {
      return jsonError(HttpStatus.forbidden, 'forbidden');
    }
  } else {
    // Self-heal: accounts registered before salon provisioning existed (or
    // after a partial failure) get their draft salon on first read
    // (docs/design/pro-salon-lifecycle.md §2). GUARD (module `access`
    // §2.3-1): an account that holds ANY membership is a team member, not an
    // ownerless owner — it must never get a salon auto-created; its salon
    // comes from the membership instead.
    providerId = account.providerId;
    var hadMembership = false;
    if (providerId == null) {
      if (await members.hasAnyMembership(account.id)) {
        hadMembership = true;
        providerId = await members.activeSalonFor(account.id);
      } else {
        account = await context.read<SalonProvisioningService>().ensureSalon(
          account,
        );
        providerId = account.providerId;
      }
    }
    if (providerId == null) {
      // Memberships exist but none is ACTIVE → a revoked member: the
      // distinct code lets the app sign out gracefully (« Votre accès a été
      // retiré »).
      return jsonError(
        HttpStatus.forbidden,
        hadMembership ? 'not_a_member' : 'forbidden',
      );
    }
  }

  final provider = await context.read<ProvidersRepository>().byId(providerId);
  if (provider == null) {
    return jsonError(HttpStatus.notFound, 'not_found');
  }

  // The caller's membership (R4a): role + server-computed capabilities +
  // the staff artist link. Owners resolve through the same path (self-heal).
  final member = await members.memberOf(account.id, providerId);
  if (member == null) {
    return jsonError(HttpStatus.forbidden, 'not_a_member');
  }
  String? artistName;
  if (member.artistId != null) {
    for (final a in (provider['artists'] as List? ?? const [])) {
      if (a is Map && a['id'] == member.artistId) {
        artistName = a['name'] as String?;
        break;
      }
    }
  }

  return Response.json(
    body: {
      'account': account.toJson(),
      'provider': provider,
      'membership': {
        'role': member.role,
        'capabilities': capabilitiesFor(member.role).toList()..sort(),
        if (member.artistId != null) 'artistId': member.artistId,
        if (artistName != null) 'artistName': artistName,
      },
    },
  );
}

Future<Response> _delete(RequestContext context, String accountId) async {
  final r = await context.read<ProviderAccountService>().deleteAccount(
    accountId,
  );
  if (!r.ok) {
    return r.error == 'future_bookings'
        ? jsonError(HttpStatus.conflict, 'future_bookings')
        : jsonError(HttpStatus.forbidden, 'forbidden');
  }
  return Response(statusCode: HttpStatus.noContent);
}
