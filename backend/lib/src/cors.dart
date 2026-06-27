import 'package:dart_frog/dart_frog.dart';

/// CORS for the browser web app(s). Allowlisted by exact `Origin` (never `*`
/// alongside credentials). Preflight `OPTIONS` short-circuits to 204; a
/// disallowed origin gets **no** CORS headers (the browser then blocks the read).
/// CORS is a browser convenience, not authz — endpoints keep their own checks.
/// Design: docs/design/web-m1-backend-glue.md.
Middleware corsMiddleware(List<String> allowedOrigins) {
  return (handler) {
    return (context) async {
      final origin =
          context.request.headers['Origin'] ??
          context.request.headers['origin'];
      final allowOrigin = (origin != null && allowedOrigins.contains(origin))
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
