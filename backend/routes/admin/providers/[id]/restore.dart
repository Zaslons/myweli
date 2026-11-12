import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/providers/{id}/restore` — « Lever la suspension » (B0.18,
/// docs/design/salon-go-live-approval.md §3.4). Audited.
///
/// 200 `{status, reason}`: `active` only when the suspension interrupted a
/// live salon that MyWeli validated and took live, with an active owner and
/// a live offer, not unpublished for non-payment — `reason` null; otherwise
/// `draft`, with the first reason that held it back (`not_validated`,
/// `no_owner`, `offer_not_live`, `unpaid`, `unknown_prior`). 404. 409
/// `not_suspended` — it never publishes a salon that was not suspended.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  final adminId = principalOf(context)!.userId; // /admin guard guarantees admin
  final r = await context.read<AdminProviderService>().restore(adminId, id);
  return salonValidationResponse(r);
}
