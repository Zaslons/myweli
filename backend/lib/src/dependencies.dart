import 'dart:io';

import 'auth/auth_repository.dart';
import 'auth/tokens.dart';
import 'providers_repository.dart';

/// Composition root: process-wide singletons built from env
/// (docs/BACKEND.md §3.5), provided into request context by
/// `routes/_middleware.dart`. Everything is in-memory today; B3b switches the
/// repository impls to Postgres **here** when `DATABASE_URL` is set — routes,
/// services, and tests are unchanged.

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

final AuthRepository authRepository = InMemoryAuthRepository(
  tokens: tokenService,
  isProd: _isProd,
);

final ProvidersRepository providersRepository = InMemoryProvidersRepository();
