import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The merge queue, and the trigger without which it hangs forever.
///
/// ## Why this file exists
///
/// `main` requires branches to be up to date, so every merge put every other
/// open pull request behind and forced a rebase plus a fresh eight-minute run.
/// On 2026-08-23 that was **37 CI runs for 13 pull requests** — about three
/// each — serialised, because each rebase had to wait for the previous merge to
/// land. Roughly two hours of waiting for eight minutes of work.
///
/// A merge queue fixes that by testing queued pull requests together against
/// the projected `main`. But a queued pull request is built on a temporary
/// `gh-readonly-queue/…` ref, **not** on the pull-request ref — so a workflow
/// that does not declare `merge_group:` never runs there. Every check `main`
/// requires would sit pending forever, and the failure is silent: nothing errors,
/// merges simply stop happening.
///
/// So this pins the half a test can see. It cannot read branch protection —
/// `launch_doc_test.dart` records why — but it can prove that every workflow
/// which *could* supply a required check is able to run inside the queue.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  YamlMap workflow(String name) =>
      loadYaml(File('$root/.github/workflows/$name').readAsStringSync())
          as YamlMap;

  /// `on:` parses as the boolean `true` in YAML 1.1, which is why this is not
  /// simply `wf['on']`. Getting that wrong makes every assertion below vacuous.
  YamlMap triggers(YamlMap wf) {
    final on = wf[true] ?? wf['on'];
    expect(
      on,
      isA<YamlMap>(),
      reason:
          'the `on:` block did not parse — every check here would pass '
          'against nothing',
    );
    return on as YamlMap;
  }

  group('ci.yml can run inside the merge queue', () {
    final ci = workflow('ci.yml');

    test('it declares merge_group', () {
      expect(
        triggers(ci).keys.map((k) => k.toString()),
        contains('merge_group'),
        reason:
            'every context main requires is produced by ci.yml. Without this '
            'trigger a queued merge waits forever for checks that cannot run, '
            'and nothing reports an error — merges just stop',
      );
    });

    test('and still runs on pull_request and push', () {
      // The queue does not replace either: a pull request must go red before it
      // is ever queued, and main is verified after the merge lands.
      final keys = triggers(ci).keys.map((k) => k.toString());
      expect(keys, containsAll(['pull_request', 'push']));
    });

    test('nothing in it reads pull-request-only context', () {
      // `github.event.pull_request` is null under merge_group. A job that reads
      // it would not fail loudly — it would compare against null and take a
      // branch nobody intended.
      //
      // **Comments stripped, and this test is why.** Its first version matched
      // the raw file and went red immediately — on the comment three lines
      // above `merge_group:` that says "Nothing here reads
      // github.event.pull_request". A guard matching the prose that explains
      // the property is the defect this repository has now found four times,
      // and this was the fourth, written on the same day as the other three.
      final code = File('$root/.github/workflows/ci.yml')
          .readAsStringSync()
          .split('\n')
          .map((l) => l.trimLeft().startsWith('#') ? '' : l)
          .join('\n');
      expect(
        code,
        isNot(contains('github.event.pull_request')),
        reason: 'this is null in a queued run',
      );
      expect(code, isNot(contains('github.head_ref')));
    });
  });

  group('no other workflow can supply a required check without the trigger', () {
    /// The ten contexts `main` requires today, by display name. Kept beside
    /// `launch_doc_test.dart`'s job-id pin: that one catches ci.yml gaining an
    /// eleventh job, this one catches a required check arriving from a
    /// DIFFERENT workflow — which would hang the queue rather than merely go
    /// unenforced.
    const requiredContexts = <String>{
      'Analyze & Test',
      'Backend — Analyze & Test',
      'Backend — boot smoke + funnel e2e',
      'Mobile — APK size',
      'Mobile — admin console builds',
      'Security — secrets & dependencies',
      'Web — Lint, Typecheck & Build',
      'Web — Lighthouse',
      'Web — e2e (Playwright)',
      'The production monitor is still firing',
    };

    test('the required contexts all come from ci.yml', () {
      final names = (workflow('ci.yml')['jobs'] as YamlMap).values
          .map((j) => (j as YamlMap)['name']?.toString())
          .whereType<String>()
          .toSet();
      expect(
        requiredContexts.difference(names),
        isEmpty,
        reason:
            'a required check is produced somewhere other than ci.yml. That '
            'workflow needs `merge_group:` too, or the queue hangs on it',
      );
    });

    test('any workflow emitting one of them declares merge_group', () {
      final dir = Directory('$root/.github/workflows');
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yml'))
          .toList();
      expect(
        files,
        isNotEmpty,
        reason: 'no workflows found — this whole group would pass vacuously',
      );

      for (final f in files) {
        final wf = loadYaml(f.readAsStringSync()) as YamlMap;
        final names =
            (wf['jobs'] as YamlMap?)?.values
                .map((j) => (j as YamlMap)['name']?.toString())
                .whereType<String>()
                .toSet() ??
            <String>{};
        if (names.intersection(requiredContexts).isEmpty) continue;

        final on = wf[true] ?? wf['on'];
        expect(
          (on as YamlMap).keys.map((k) => k.toString()),
          contains('merge_group'),
          reason:
              '${f.uri.pathSegments.last} produces a required check but cannot '
              'run in the merge queue, so every queued merge would wait on it '
              'forever',
        );
      }
    });
  });

  group('roadmap entries are one file per change', () {
    /// The other half of why merges took two hours: every entry went at the
    /// same line of `docs/ROADMAP.md` §1.8, newest-first, so every rebase
    /// conflicted. Nine times in a row on 2026-08-23, and twice the resolution
    /// committed the markers.
    final entries = Directory('$root/docs/roadmap/entries');

    test('the directory exists and explains itself', () {
      expect(entries.existsSync(), isTrue);
      expect(File('${entries.path}/README.md').existsSync(), isTrue);
    });

    test('every entry is dated in its filename', () {
      // The date prefix is what makes reverse-lexicographic order equal
      // newest-first, which is what tool/roadmap-log.sh relies on.
      final bad = entries
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n != 'README.md')
          .where(
            (n) => !RegExp(r'^\d{4}-\d{2}-\d{2}-[a-z0-9-]+\.md$').hasMatch(n),
          )
          .toList();
      expect(
        bad,
        isEmpty,
        reason:
            'entry filenames must be YYYY-MM-DD-slug.md — the date prefix is '
            'the sort key the log reader uses: $bad',
      );
    });

    test('the closed list points at them', () {
      expect(
        File('$root/docs/ROADMAP.md').readAsStringSync(),
        contains('docs/roadmap/entries/'),
        reason:
            'a reader landing in ROADMAP.md would think the log simply stopped '
            'on 2026-08-23',
      );
    });

    test('the log reader exists and is executable', () {
      final f = File('$root/tool/roadmap-log.sh');
      expect(f.existsSync(), isTrue);
      expect(
        f.statSync().mode & 0x40,
        isNonZero,
        reason: 'tool/roadmap-log.sh is not executable',
      );
    });

    test('and its date filter actually matches a date', () {
      // **Watched failing on the real script.** The first version globbed
      // `[0-9]*${FILTER}*.md`, which requires a digit BEFORE the filter — so
      // `./tool/roadmap-log.sh 2026-08`, the usage the README documents,
      // matched nothing. Documented and never run.
      final out = Process.runSync('bash', [
        '$root/tool/roadmap-log.sh',
        '2026-08',
      ], workingDirectory: root);
      expect(
        out.exitCode,
        0,
        reason: 'the documented date filter returns nothing: ${out.stderr}',
      );
      expect(
        (out.stdout as String),
        contains('2026-08'),
        reason: 'the filter matched, but not the entries it names',
      );
    });
  });
}
