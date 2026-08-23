import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `infra/gcp/98-verify-secret-pins.sh` — read-only, metadata-only, and wired.
///
/// The script answers whether the secret versions the manifests pin are still
/// enabled and still newest. It runs as an identity holding a custom role with
/// four permissions, none of them `secretmanager.versions.access`, and
/// `production-checks.yml` proves that with a refusal rather than asserting it.
///
/// This file guards the other half: that the script cannot grow the power its
/// role withholds, and that it is actually reached.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  final script = File(
    '$root/infra/gcp/98-verify-secret-pins.sh',
  ).readAsStringSync();

  YamlMap workflow(String name) =>
      loadYaml(File('$root/.github/workflows/$name').readAsStringSync())
          as YamlMap;

  group('it cannot read a value, and cannot change anything', () {
    /// **Comments are deliberately NOT stripped here**, which is the opposite
    /// of what the sibling guards do — and the reason is in
    /// `log_retention_test.dart`: a commented-out `versions access` is a line
    /// somebody uncomments at 2am. Elsewhere a comment is harmless text; in a
    /// script whose entire safety argument is "it never calls that verb", a
    /// commented-out call is a loaded gun with the safety on.
    /// gcloud's actual subcommand PATHS, not loose words. `r2_manifest_test`
    /// records why: its first draft guarded `r2 lifecycle add` while wrangler
    /// spells it `r2 bucket lifecycle add`, so the guard could not fire and a
    /// mutation appending exactly that line watched it pass. Full paths also
    /// let the script's prose name a verb while explaining that it never calls
    /// it — the hazard is a runnable line, and a runnable line carries the
    /// whole path.
    const forbidden = {
      'secrets versions access':
          'returns the secret VALUE — the one thing the custom role withholds, '
          'and the reason it is custom rather than roles/secretmanager.viewer',
      'secrets versions add': 'writes a new version',
      'secrets versions disable':
          'a checker that can disable the thing it checks',
      'secrets versions destroy': 'irreversible',
      'secrets delete': 'irreversible',
      'projects add-iam-policy-binding':
          'a checker that can widen its own identity',
    };

    forbidden.forEach((verb, why) {
      test('never calls `$verb`', () {
        expect(
          script.contains(verb),
          isFalse,
          reason:
              '98-verify-secret-pins.sh mentions `$verb`, which $why. Comments '
              'count: this is the one guard where a commented-out call is the '
              'hazard rather than noise',
        );
      });
    });

    test('the two reads it does make are the metadata ones', () {
      expect(script, contains('secrets versions describe'));
      expect(script, contains('secrets versions list'));
    });
  });

  group('it refuses to report success having checked nothing', () {
    test('a floor on the number of pins it parsed', () {
      // Every assertion in the script loops over what it parsed out of the
      // manifests. If the manifests are reshaped and the sed stops matching,
      // the loops run zero times and it exits 0 — the exact failure it exists
      // to prevent, wearing its own uniform.
      expect(
        RegExp(r'COUNT.*-lt\s+\d+').hasMatch(script),
        isTrue,
        reason:
            'the vacuity guard is gone, so a parse that matches nothing '
            'reports every pin correct',
      );
      expect(script, contains('Refusing to report success'));
    });
  });

  group('it is actually reached', () {
    test('the daily monitor runs it, and a failure opens the issue', () {
      final wf = workflow('production-checks.yml');
      final jobs = wf['jobs'] as YamlMap;
      expect(
        jobs.keys,
        contains('secretpins'),
        reason: 'a checker nothing runs is a file',
      );
      final steps = (jobs['secretpins']['steps'] as YamlList).cast<YamlMap>();
      expect(
        steps.any(
          (s) =>
              (s['run'] as String? ?? '').contains('98-verify-secret-pins.sh'),
        ),
        isTrue,
      );
      expect(
        (jobs['report']['needs'] as YamlList).toList(),
        contains('secretpins'),
        reason:
            'a monitor whose only signal is a red row in the Actions tab is a '
            'monitor nobody reads — the reason the report job exists',
      );
    });

    test('the daily monitor proves it cannot read a value', () {
      final steps =
          (workflow('production-checks.yml')['jobs']['secretpins']['steps']
                  as YamlList)
              .cast<YamlMap>();
      final control = steps.firstWhere(
        (s) => (s['name'] as String? ?? '').contains('CANNOT read a secret'),
        orElse: () => YamlMap(),
      );
      expect(
        control,
        isNotEmpty,
        reason:
            'without the negative control, "this identity cannot read a secret '
            'value" is an inference from a role definition. An argument nobody '
            'has tested is a claim, not a control',
      );
      final run = control['run'] as String;
      expect(run, contains('versions access'));
      expect(
        run,
        contains('PERMISSION_DENIED'),
        reason:
            'a failure that is not a permission error proves nothing about the '
            'boundary, and must not be read as if it did',
      );
    });

    test('the deploy runs it BEFORE replacing the service', () {
      final steps =
          (workflow('deploy-backend.yml')['jobs']['deploy']['steps']
                  as YamlList)
              .cast<YamlMap>();
      final gate = steps.indexWhere(
        (s) => (s['run'] as String? ?? '').contains('98-verify-secret-pins.sh'),
      );
      final replace = steps.indexWhere(
        (s) => (s['run'] as String? ?? '').contains('run services replace'),
      );
      expect(gate, isNonNegative, reason: 'the deploy gate is gone');
      expect(replace, isNonNegative);
      expect(
        gate,
        lessThan(replace),
        reason:
            'a check after the service is replaced is a report, not a gate — '
            'and a stale pin is already serving by then',
      );
    });

    test('no workflow sets the rehearsal fixture', () {
      // A rehearsal that runs on the schedule is a monitor measuring nothing,
      // and it would announce itself only in a log nobody reads on a green run.
      for (final name in ['production-checks.yml', 'deploy-backend.yml']) {
        // The ASSIGNMENT form, not the bare name: production-checks.yml says
        // in a comment that the fixture is deliberately not set here, and a
        // guard that forbids talking about a thing forbids explaining it.
        expect(
          RegExp(
            r'SECRET_PINS_FIXTURE_JSON\s*[:=]',
          ).hasMatch(File('$root/.github/workflows/$name').readAsStringSync()),
          isFalse,
          reason: '$name sets the fixture, so it measures a JSON literal',
        );
      }
    });
  });
}
