import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/access/capabilities.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';

/// `POST /providers/{id}/publish` — the owner ASKS to go live (B0.18,
/// docs/design/salon-go-live-approval.md §3.1; PRD FR-PRO-ONB-001's « go
/// live »): MyWeli validates each salon before it is public, so a request
/// is recorded and the salon stays `draft` until the admin decides.
/// Provider-only + ownership-scoped (`salon.publish`, T50); the
/// completeness gate is computed from SERVER state (profile · pin · ≥3
/// services · ≥3 photos · opening hours · a live offer when a row exists).
///
/// - **202** `{validation}` — the request is recorded, or was already (no
///   second event, no second e-mail to the admin), or the admin's validation
///   is finishing. No trial starts here any more: it starts at the
///   validation (§3.6).
/// - **200** the salon — already live (idempotent), or a validated salon
///   back from `draft` with a live offer (the republish).
/// - 403 `forbidden` (not the owner) · `demo_account_locked` (T69) ·
///   `provider_suspended` (T17) — nothing is recorded.
/// - 409 `incomplete` + the missing checklist keys (`offer` for an existing
///   row no longer live) · `validation_refused_final` (a final refusal,
///   §4.3: only the admin can still validate it).
/// - 404 `not_found` · 405.
Future<Response> onRequest(RequestContext context, String id) async {
  final principal = principalOf(context);
  if (principal == null) {
    return jsonError(HttpStatus.unauthorized, 'unauthorized');
  }
  if (principal.role != 'provider') {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }
  if (context.request.method != HttpMethod.post) return methodNotAllowed();

  // Module `access` R1 (sign-off: go-live is owner-only → salon.publish).
  final allowed = await context.read<MembershipService>().can(
    principal.userId,
    id,
    Cap.salonPublish,
  );
  if (!allowed) {
    return jsonError(HttpStatus.forbidden, 'forbidden');
  }

  final r = await context.read<SalonProvisioningService>().publish(id);
  if (r.ok) {
    // 202 for a request the admin has yet to decide — never a 200, which
    // every client reads as « en ligne » (Q8: released builds show their
    // generic error for a 202 instead of a false « en ligne »).
    return Response.json(
      statusCode: r.accepted ? HttpStatus.accepted : HttpStatus.ok,
      body: r.data,
    );
  }
  return switch (r.error) {
    'not_found' => jsonError(HttpStatus.notFound, 'not_found'),
    // T69: the demo review account may never publish — 403, not the 409 the
    // completeness arm below would otherwise dress it in.
    'demo_account_locked' => jsonError(
      HttpStatus.forbidden,
      'demo_account_locked',
    ),
    // T17: an admin suspension is lifted only by the admin restore. 403 like
    // the demo lock — not a 409 the clients would read as a missing step.
    'provider_suspended' => jsonError(
      HttpStatus.forbidden,
      'provider_suspended',
    ),
    // §4.3: a final refusal (outside_ci, test_salon) — asking again changes
    // nothing; the reason travels on the feed row and the e-mail.
    'validation_refused_final' => jsonError(
      HttpStatus.conflict,
      'validation_refused_final',
    ),
    // incomplete → 409 with the missing checklist keys.
    _ => Response.json(
      statusCode: HttpStatus.conflict,
      body: {
        'error': r.error ?? 'incomplete',
        ...(r.data as Map<String, dynamic>? ?? {}),
      },
    ),
  };
}
