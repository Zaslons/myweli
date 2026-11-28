import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';

import 'user_list_contract.dart';

/// The in-memory twin's run of [userListContract]; Postgres runs it in
/// `db/postgres_repositories_test.dart`. docs/design/auth-store-twins.md §5.3.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  userListContract(
    repo: () => InMemoryAuthRepository(tokens: tokens, echoDevCode: true),
    plantCreatedAt: (r, ids, at) async {
      for (final id in ids) {
        (r as InMemoryAuthRepository).plantCreatedAtForTest(id, at);
      }
    },
  );
}
