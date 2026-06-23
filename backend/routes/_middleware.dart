import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/dependencies.dart';
import 'package:myweli_backend/src/providers_repository.dart';

/// Provides the process-wide singletons into every request's context, so
/// handlers share state and the repository impls can be swapped in one place
/// (the composition root) without touching routes.
Handler middleware(Handler handler) {
  return handler
      .use(provider<AuthRepository>((_) => authRepository))
      .use(provider<ProviderAuthRepository>((_) => providerAuthRepository))
      .use(provider<TokenService>((_) => tokenService))
      .use(provider<ProvidersRepository>((_) => providersRepository));
}
