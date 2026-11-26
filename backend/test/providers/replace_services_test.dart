import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import 'replace_services_contract.dart';

/// The in-memory run of [replaceServicesContract]; the Postgres run is in
/// `db/postgres_repositories_test.dart`. docs/design/demo-reset-restore.md
/// §5.4.
void main() {
  group('InMemoryProvidersRepository — replaceServices, the twin contract', () {
    // One store per case: the contract's « [other salon] » and « [foreign
    // id] » need two salons in the SAME store, which `repo` gives each call.
    late InMemoryProvidersRepository store;
    setUp(() => store = InMemoryProvidersRepository([]));
    replaceServicesContract(repo: () => store, created: (_) {});
  });
}
