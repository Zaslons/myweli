import 'package:dart_frog/dart_frog.dart';

import 'tokens.dart';

/// The authenticated caller resolved from a verified access token.
typedef Principal = ({String userId, String role});

/// Resolves the bearer principal from the request, or `null` when the token is
/// absent/malformed/invalid/expired — callers then deny by default
/// (docs/BACKEND.md §3.3). Requires `TokenService` in the context.
Principal? principalOf(RequestContext context) {
  final header =
      context.request.headers['Authorization'] ??
      context.request.headers['authorization'];
  if (header == null || !header.startsWith('Bearer ')) return null;

  final jwt = context.read<TokenService>().verifyAccessToken(
    header.substring(7),
  );
  final subject = jwt?.subject;
  final payload = jwt?.payload;
  final role = payload is Map ? payload['role'] : null;
  if (subject == null || role is! String) return null;

  return (userId: subject, role: role);
}
