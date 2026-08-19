// no-rate-limit: reads ReviewsService to LIST, never to submit. Reading a
// limited service is not the same as calling its limited method.
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/reviews_service.dart';
import 'package:myweli_backend/src/salon_visibility.dart';

/// `GET /providers/{id}/reviews?page=&pageSize=` — public, paginated, newest
/// first. Design: docs/design/consumer-reviews.md.
///
/// **Decision C: hidden AND unknown both 404, and that symmetry is the point.**
/// This route had no provider read at all, so an unknown id answered
/// `200 {items: []}`. Closing only the hidden case would have made 404 mean
/// « exists but hidden » — the enumeration oracle T51 forbids, on a route that
/// takes the salon id in its path. Moving the unknown id is a behaviour change
/// for existing callers, flagged in the contract.
///
/// The gate lives HERE and not in `ReviewsService.list`, which is shared with
/// `GET /me/provider/reviews`: a draft salon can hold reviews (T53 erasure, T54
/// billing unpublish) and its owner must keep reading them.
/// no-upload-claim: this route only LISTS reviews. The claim lives in
/// `POST /appointments/{id}/review`, which maps the code itself.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final salon = await context.read<ProvidersRepository>().byId(id);
  if (!isPublicSalon(salon)) {
    return jsonError(HttpStatus.notFound, 'not_found');
  }

  final q = context.request.uri.queryParameters;
  final page = int.tryParse(q['page'] ?? '') ?? 1;
  final pageSize = int.tryParse(q['pageSize'] ?? '') ?? 20;

  final r = await context.read<ReviewsService>().list(
    id,
    page: page,
    pageSize: pageSize,
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
