import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

import 'profile_filters_contract.dart';

/// The in-memory run of [profileFiltersContract]; the Postgres run is in
/// `db/postgres_repositories_test.dart`. docs/design/provider-category-column.md §5.3.
void main() {
  group('InMemoryProvidersRepository — updateProfile reaches every filter', () {
    profileFiltersContract(
      repo: () => InMemoryProvidersRepository([]),
      created: (_) {},
    );
  });
}
