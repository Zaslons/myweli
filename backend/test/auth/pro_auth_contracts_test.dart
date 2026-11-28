import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';

import 'pro_signup_code_contract.dart';
import 'pro_social_link_contract.dart';

/// The in-memory twin's run of [proSocialLinkContract] and
/// [proSignupCodeContract]; Postgres runs both in
/// `db/postgres_repositories_test.dart`. docs/design/auth-store-twins.md.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  InMemoryProviderAuthRepository repo() =>
      InMemoryProviderAuthRepository(tokens: tokens, echoDevCode: true);
  proSocialLinkContract(
    repo: repo,
    plantUnproven: (r, id) async =>
        (r as InMemoryProviderAuthRepository).plantUnprovenEmailForTest(id),
  );
  proSignupCodeContract(repo: repo);
}
