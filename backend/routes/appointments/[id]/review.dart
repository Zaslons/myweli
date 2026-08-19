import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/principal.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/reviews_service.dart';

/// `POST /appointments/{appointmentId}/review` — review a completed visit. The
/// appointment must be the caller's own and `completed`; the server derives the
/// provider, artist, service, reviewer, and `verified` from it (the client sets
/// only rating/text/photos). One review per appointment (resubmit replaces).
/// Design: docs/design/consumer-reviews.md.
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

  final r = await context.read<ReviewsService>().submitForAppointment(
    principal.userId,
    id,
    rating: body['rating'],
    text: body['text'],
    photoUrls: body['photoUrls'],
  );
  if (r.ok) {
    return Response.json(statusCode: HttpStatus.created, body: r.review);
  }
  switch (r.error) {
    case 'not_found':
      return jsonError(HttpStatus.notFound, 'not_found');
    case 'forbidden':
      return jsonError(HttpStatus.forbidden, 'forbidden');
    case 'not_completed':
      return jsonError(HttpStatus.forbidden, 'not_completed');
    // Ours, not the caller's — and the only one here worth retrying.
    case 'storage_unavailable':
      return storageUnavailable();
    // Per-identity rate limit, written before the emitter exists.
    // docs/design/backend-identity-rate-limits.md §6.
    case 'rate_limited':
      return jsonError(HttpStatus.tooManyRequests, 'rate_limited');
    default:
      return jsonError(HttpStatus.badRequest, r.error ?? 'invalid_input');
  }
}
