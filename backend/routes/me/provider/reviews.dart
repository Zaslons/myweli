import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/reviews_service.dart';

/// `GET /me/provider/reviews?page=&pageSize=` — the salon's OWN « Avis »,
/// resolved BY ACCOUNT.
///
/// **Why this exists rather than the public route.** Both pro « Avis » surfaces
/// read `GET /providers/{id}/reviews`, which is anonymous and takes the salon
/// id from the caller: mobile went through the *consumer* review service with
/// no token at all, and web's `/api/pro/reviews` forwarded whatever
/// `providerId` the browser sent. PR1b moved four pro surfaces off the
/// anonymous door and its source pin could not see these two — they named none
/// of the forbidden tokens because the leak crossed a *service* boundary rather
/// than a directory one. Decision C closes the public reviews route, and a
/// `draft` salon can hold reviews (T53 erasure and T54 billing unpublish both
/// write `status → draft` over a salon with history), so without this the
/// owner being asked to pay would lose the page showing what their clients
/// said.
///
/// Scoping is `MembershipService.salonForRequest` — the same primitive
/// `/me/provider` uses, so the R6 `?salonId=` selection behaves identically and
/// an invalid selection is the same uniform 403 (no membership-existence
/// oracle, T55). Membership alone is the gate: every active member of a salon
/// may read what clients wrote about it; there is no narrower capability
/// because there is nothing narrower to protect — the reviews are public while
/// the salon is live.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final account = await context.read<ProviderAuthRepository>().accountById(
    principal.userId,
  );
  if (account == null) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final members = context.read<MembershipService>();
  final q = context.request.uri.queryParameters;
  final selected = q['salonId']?.trim() ?? '';
  // No self-heal here, unlike `/me/provider`: a salon that does not exist yet
  // has no reviews, and provisioning is that route's job, not this one's.
  final providerId = selected.isNotEmpty
      ? await members.salonForRequest(account.id, salonId: selected)
      : (account.providerId ?? await members.activeSalonFor(account.id));
  if (providerId == null) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  // Deny by default: the owner path above trusts `account.providerId`, so the
  // membership check is what actually authorizes the read.
  if (await members.memberOf(account.id, providerId) == null) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final r = await context.read<ReviewsService>().list(
    providerId,
    page: int.tryParse(q['page'] ?? '') ?? 1,
    pageSize: int.tryParse(q['pageSize'] ?? '') ?? 20,
  );
  return Response.json(
    body: {
      'items': r.items,
      'page': r.page,
      'pageSize': r.pageSize,
      'total': r.total,
    },
  );
}
