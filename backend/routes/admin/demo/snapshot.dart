import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/demo/demo_reset_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `POST /admin/demo/snapshot` — capture the demo salon's current state as
/// the canonical snapshot the weekly reset restores (T69). Admin-gated by
/// `/admin/_middleware.dart` like every admin surface. Takes NO body: the
/// target is derived server-side from the compile-time demo identity, so an
/// operator cannot aim it at a real salon — and a salon whose owner
/// membership is not the demo identity is refused (409 `not_demo_owned`).
/// Also puts the demo salon on its live Pro offer (created if absent —
/// docs/design/pro-companion-path.md §3.3), so the reviewer never meets the
/// setup state. Audited (`demo.snapshot`, T17).
/// Design: docs/design/backend-demo-review-account.md §6.2.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return methodNotAllowed();
  final r = await context.read<DemoResetService>().capture(
    DateTime.now().toUtc(),
  );
  if (!r.ok) return jsonError(HttpStatus.conflict, r.error!);
  // Audited like every admin mutation (T17) — and since the companion path
  // this one also writes billing state (the demo's offer pin, which extends
  // `paid_until`), so T54's « paid_until moves only through an audited
  // action » holds for the admin half of the demo writer too.
  await context.read<AuditLogRepository>().append((
    actorAdminId: principalOf(context)!.userId,
    action: 'demo.snapshot',
    targetType: 'provider',
    targetId: r.providerId,
    reason: null,
    metadata: const {},
  ));
  return Response.json(body: {'providerId': r.providerId});
}
