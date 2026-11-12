import 'package:test/test.dart';

import 'validation_reads_contract.dart';
import 'validation_world.dart';

/// The in-memory twins under the stage-2 reads contract; the Postgres twins
/// run the same contract in `test/db/postgres_repositories_test.dart`.
void main() {
  late ValidationWorld w;

  setUp(() => w = ValidationWorld());

  validationReadsContract(
    providers: () => w.providers,
    members: () => w.members,
    accounts: () => w.auth,
    salon: ({withOwner = true}) async {
      if (withOwner) return (await w.salon()).id;
      final s = await w.providers.createSalon(
        name: 'Salon Seul',
        category: 'salon',
        phoneNumber: '+2250700000011',
      );
      return s['id'] as String;
    },
  );
}
