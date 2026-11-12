import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/validation/salon_validation_service.dart';

/// `GET /admin/salons/{id}/validation` — the request's detail (B0.18,
/// docs/design/salon-go-live-approval.md §3.5, §4.3): the salon as the admin
/// provider detail reads it (photos, services, hours, address, area,
/// country, pin, phone), its offer, the owner (contact, account age, KYC
/// status and document count, other salons), the validation — with the
/// admin who decided, for the console only — and its history. `validation`
/// is null for a salon that never asked. 404 `not_found`. Admin-only by the
/// `/admin` middleware (T17).
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();
  final r = await context.read<SalonValidationService>().detail(id);
  return salonValidationResponse(r);
}
