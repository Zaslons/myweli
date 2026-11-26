import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';

import 'account_email_contract.dart';

/// The in-memory twin's run of [accountEmailContract]; Postgres runs it in
/// `db/postgres_repositories_test.dart`. docs/design/account-email-change.md.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  accountEmailContract(
    repo: () => InMemoryAuthRepository(tokens: tokens, echoDevCode: true),
    plant: (r, id, email) async {
      await r.updateUser(id, email: email);
    },
  );
}
