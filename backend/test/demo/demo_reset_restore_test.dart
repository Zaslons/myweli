import 'package:myweli_backend/src/demo/demo_snapshot_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/salon_time.dart';
import 'package:test/test.dart';

import 'demo_reset_restore_contract.dart';
import 'demo_snapshot_contract.dart';

/// The in-memory runs of [demoSnapshotContract] and
/// [demoResetRestoreContract]; the Postgres runs are in
/// `db/postgres_repositories_test.dart`. docs/design/demo-reset-restore.md
/// §5.4 (B16.2).
void main() {
  setUpAll(initSalonTime);

  group('InMemoryDemoSnapshotRepository — the twin contract', () {
    demoSnapshotContract(repo: InMemoryDemoSnapshotRepository.new);
  });

  group('the demo reset restores the curated salon — in memory', () {
    demoResetRestoreContract(
      providers: () => InMemoryProvidersRepository([]),
      snapshots: InMemoryDemoSnapshotRepository.new,
      created: (_) {},
    );
  });
}
