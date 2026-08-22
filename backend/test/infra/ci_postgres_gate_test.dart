import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// **The Postgres-backed tests skip themselves when `DATABASE_URL` is unset —
/// silently, and by design.**
///
/// `postgres_admin_auth_test.dart` opens with a guard that turns the whole file
/// into one skipped test when the variable is missing, so a developer without a
/// database sees green. That is right for a laptop and dangerous for CI: drop
/// the `services: postgres` block or the `env: DATABASE_URL`, and every
/// integration test — including the only coverage of the `DELETE FROM
/// admin_refresh_tokens` that runs in production — stops executing while the
/// job stays green and the run reports MORE passing tests than before, not
/// fewer.
///
/// An audit named this exactly: "the gate that #479's new coverage sits behind
/// is itself pinned by nothing."
void main() {
  final ci = File('../.github/workflows/ci.yml');

  test('ci.yml is where this test thinks it is', () {
    expect(ci.existsSync(), isTrue, reason: '${ci.absolute.path} not found');
  });

  final doc = loadYaml(ci.readAsStringSync()) as YamlMap;
  final jobs = doc['jobs'] as YamlMap;

  String stripComments(String run) =>
      run.split('\n').where((l) => !l.trimLeft().startsWith('#')).join('\n');

  /// The job by what it DOES — runs the backend suite — so a rename cannot
  /// quietly exempt it.
  MapEntry<String, YamlMap> backendTestJob() {
    for (final e in jobs.entries) {
      final job = e.value as YamlMap;
      final steps = job['steps'] as YamlList?;
      if (steps == null) continue;
      final defaults = job['defaults'] as YamlMap?;
      final wd = (defaults?['run'] as YamlMap?)?['working-directory'];
      if (wd != 'backend') continue;
      for (final s in steps) {
        final run = (s as YamlMap)['run'];
        if (run is String && stripComments(run).trim() == 'dart test') {
          return MapEntry(e.key as String, job);
        }
      }
    }
    fail('no job runs the backend suite with `dart test` in backend/');
  }

  test('a job runs the backend suite', () {
    expect(backendTestJob().key, isNotEmpty);
  });

  test('IT HAS A POSTGRES SERVICE — or the db tests skip themselves', () {
    final services = backendTestJob().value['services'] as YamlMap?;
    expect(
      services,
      isNotNull,
      reason: 'no services block: every db-backed test would skip, green',
    );
    final images = [
      for (final v in services!.values) (v as YamlMap)['image'].toString(),
    ];
    expect(
      images.any((i) => i.startsWith('postgres')),
      isTrue,
      reason: 'services exist but none is postgres: $images',
    );
  });

  test('AND DATABASE_URL REACHES `dart test`', () {
    final steps = backendTestJob().value['steps'] as YamlList;
    final runs = [
      for (final s in steps)
        if ((s as YamlMap)['run'] is String &&
            stripComments(s['run'] as String).trim() == 'dart test')
          s,
    ];
    expect(runs, isNotEmpty);
    for (final s in runs) {
      final env = s['env'] as YamlMap?;
      final url = env?['DATABASE_URL']?.toString();
      expect(
        url,
        isNotNull,
        reason:
            'without DATABASE_URL the db suite skips and the job is still '
            'green — the run reports MORE passing tests, not fewer',
      );
      expect(url, startsWith('postgres'), reason: 'not a postgres url: $url');
    }
  });

  test('the skip is real — the suite really is gated on that variable', () {
    // Otherwise this whole file guards a mechanism that does not exist. The
    // guard lives at the top of the db test itself.
    final db = File('test/db/postgres_admin_auth_test.dart').readAsStringSync();
    expect(db, contains("Platform.environment['DATABASE_URL']"));
    expect(db, contains('skip:'));
  });
}
