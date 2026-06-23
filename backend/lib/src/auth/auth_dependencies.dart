import 'dart:io';

import 'auth_repository.dart';
import 'tokens.dart';

/// Process-wide auth singletons, built from env (docs/BACKEND.md §3.5).
/// Provided into request context by `routes/_middleware.dart`.

bool get _isProd => (Platform.environment['ENV'] ?? 'dev') == 'prod';

String _resolveSecret() {
  final secret = Platform.environment['JWT_SECRET'];
  if (secret != null && secret.isNotEmpty) return secret;
  if (_isProd) {
    throw StateError('JWT_SECRET must be set in production');
  }
  // Dev-only fallback so local runs work without setup; never used in prod.
  return 'dev-insecure-secret-change-me';
}

final TokenService tokenService = TokenService(secret: _resolveSecret());

final AuthRepository authRepository = AuthRepository(
  tokens: tokenService,
  isProd: _isProd,
);
