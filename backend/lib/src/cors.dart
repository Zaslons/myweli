import 'package:dart_frog/dart_frog.dart';

/// CORS for the browser web app(s). Allowlisted by exact `Origin` (never `*`
/// alongside credentials). Preflight `OPTIONS` short-circuits to 204; a
/// disallowed origin gets **no** CORS headers (the browser then blocks the read).
/// CORS is a browser convenience, not authz — endpoints keep their own checks.
/// Design: docs/design/web-m1-backend-glue.md.
///
/// **Takes a callback, not a list**, for the same reason `observabilityMiddleware`
/// does: dart_frog builds the whole middleware chain in `buildRootHandler()`,
/// which the generated `server.dart` runs BEFORE the custom entrypoint. Passing
/// `webOrigins` by value evaluates it there — so when `WEB_ORIGINS` is unset, it
/// throws at chain-build time and pre-empts
/// `_assertConfiguredDependenciesResolve()`, which exists precisely to report
/// every missing variable in one error. The operator then fixes one, redeploys,
/// and meets the other four. Deferring the read restores the aggregate.
Middleware corsMiddleware(List<String> Function() allowedOrigins) {
  return (handler) {
    return (context) async {
      final origin =
          context.request.headers['Origin'] ??
          context.request.headers['origin'];
      final allowOrigin = (origin != null && allowedOrigins().contains(origin))
          ? origin
          : null;

      if (context.request.method == HttpMethod.options) {
        return Response(
          statusCode: 204,
          headers: allowOrigin == null ? const {} : _headers(allowOrigin),
        );
      }

      final response = await handler(context);
      if (allowOrigin == null) return response;
      return response.copyWith(
        headers: {...response.headers, ..._headers(allowOrigin)},
      );
    };
  };
}

Map<String, String> _headers(String origin) => {
  'Access-Control-Allow-Origin': origin,
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
  'Access-Control-Allow-Credentials': 'true',
  'Vary': 'Origin',
};
