import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_dependencies.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';

/// Provides the process-wide auth singletons into every request's context, so
/// handlers share OTP/refresh state and can verify access tokens.
Handler middleware(Handler handler) {
  return handler
      .use(provider<AuthRepository>((_) => authRepository))
      .use(provider<TokenService>((_) => tokenService));
}
