import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:test/test.dart';

import 'display_names_contract.dart';

/// The in-memory twin under the contract Postgres runs too
/// (`db/postgres_repositories_test.dart`).
void main() {
  group('InMemoryClientsRepository', () {
    displayNamesContract(repo: InMemoryClientsRepository.new);
  });
}
