import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/client_version/client_version_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /client-version?app=&platform=&build=&version=` — may this client keep
/// running?
///
/// Unauthenticated: the check runs at startup, before any login. Takes no user
/// data and returns none. Design: docs/design/client-version-gate.md §4.
///
/// **`no-store`, not the `/localities` `max-age=3600`.** The whole value of this
/// lever is the latency between deciding to retire a client and that decision
/// reaching phones; an hour of cache spends it. The response is four integers
/// from a four-row table — there is nothing here worth caching.
///
/// **Everything malformed is answered `ok`, never 400.** An unknown flavour, a
/// typo'd platform or a missing build must not be indistinguishable from an
/// outage: the client fails open on errors, so answering 400 would produce the
/// same behaviour by a more confusing route. The service owns that rule; this
/// handler just passes what it was given.
///
/// `version` is accepted and ignored — it rides along for the access log, which
/// is the only client-version telemetry we have (no request carries one today).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final q = context.request.uri.queryParameters;
  final verdict = await context.read<ClientVersionService>().check(
    appId: q['app'],
    platform: q['platform']?.toLowerCase(),
    build: int.tryParse(q['build'] ?? ''),
  );

  return Response.json(
    body: {
      'status': verdict.status.wire,
      if (verdict.updateUrl != null) 'updateUrl': verdict.updateUrl,
    },
    headers: {'Cache-Control': 'no-store'},
  );
}
