import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/providers/{id}/subscription/paid` `{months, reason?}` —
/// record a manual payment (T54: `paid_until` flips only through this
/// audited action). Republishes a billing-unpublished salon when the
/// publish gate passes. The /admin middleware guarantees the admin role.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  final adminId = principalOf(context)!.userId;
  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    body = const {};
  }
  final r = await context.read<AdminProviderService>().markSubscriptionPaid(
    adminId,
    id,
    body['months'],
    reason: body['reason'],
  );
  return resultResponse(ok: r.ok, error: r.error, body: r.data);
}
