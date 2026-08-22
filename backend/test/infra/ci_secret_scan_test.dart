import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// **The secret scan cannot silently narrow again.**
///
/// CI ran `gitleaks detect --no-git` for months. That reads the checked-out
/// files and never one historical commit, so removing a credential from HEAD
/// made the job green while the value sat in the history forever — which is the
/// whole reason a leak needs rotating. **25 runs passed answering a narrower
/// question than the job's own name.**
///
/// It was fixed by adding `fetch-depth: 0` and dropping `--no-git`. Nothing
/// then stopped it drifting back: the only thing preventing recurrence was a
/// prose comment and nobody editing that block. Both halves are load-bearing
/// and both are silent when wrong — a shallow checkout with a full-history scan
/// finds one commit and still exits 0.
void main() {
  final ci = File('../.github/workflows/ci.yml');

  test('ci.yml is where this test thinks it is', () {
    // Without this the whole file degrades into vacuous passes the moment the
    // workflow moves or the working directory changes.
    expect(ci.existsSync(), isTrue, reason: '${ci.absolute.path} not found');
  });

  final doc = loadYaml(ci.readAsStringSync()) as YamlMap;
  final jobs = doc['jobs'] as YamlMap;

  /// Shell comments stripped before matching. **This test found the trap in
  /// itself:** `backend-boot-smoke` has `run:` blocks whose COMMENTS mention
  /// gitleaks ("Never a real credential — gitleaks would fail the run"), so the
  /// first version selected that job and reported a missing `fetch-depth` on a
  /// checkout that has no business having one. Two tests in this repo were
  /// already caught matching a string present only in a comment — one of them
  /// the comment explaining the very defect it was meant to catch.
  String code(String run) =>
      run.split('\n').where((l) => !l.trimLeft().startsWith('#')).join('\n');

  /// The job that runs the scan, found by what it DOES rather than by name, so
  /// renaming it cannot quietly exempt it.
  MapEntry<String, YamlMap> scanJob() {
    for (final e in jobs.entries) {
      final job = e.value as YamlMap;
      final steps = job['steps'] as YamlList?;
      if (steps == null) continue;
      for (final s in steps) {
        final run = (s as YamlMap)['run'];
        if (run is String && code(run).contains('gitleaks')) {
          return MapEntry(e.key as String, job);
        }
      }
    }
    fail('no job in ci.yml runs gitleaks at all');
  }

  test('a job actually runs gitleaks', () {
    expect(scanJob().key, isNotEmpty);
  });

  test('IT SCANS HISTORY — no --no-git', () {
    final steps = scanJob().value['steps'] as YamlList;
    final cmds = [
      for (final s in steps)
        if ((s as YamlMap)['run'] is String &&
            code(s['run'] as String).contains('gitleaks'))
          s['run'] as String,
    ];
    expect(cmds, isNotEmpty);
    for (final c in cmds) {
      // The block above the command explains the defect and names `--no-git`;
      // matching prose would make this test pass or fail on a comment.
      expect(
        code(c).contains('--no-git'),
        isFalse,
        reason:
            'gitleaks is back to scanning the working tree only — a '
            'credential removed from HEAD would pass while it stays in history',
      );
    }
  });

  test('AND THE CHECKOUT IS DEEP — fetch-depth: 0', () {
    final steps = scanJob().value['steps'] as YamlList;
    final checkouts = [
      for (final s in steps)
        if ((s as YamlMap)['uses']?.toString().startsWith('actions/checkout') ??
            false)
          s,
    ];
    expect(checkouts, isNotEmpty, reason: 'the scan job never checks out');
    for (final c in checkouts) {
      final depth = (c['with'] as YamlMap?)?['fetch-depth'];
      expect(
        depth,
        0,
        reason:
            'a shallow checkout leaves one commit to scan, and the job '
            'still exits 0 — the failure is silent in both directions',
      );
    }
  });

  /// **Four other ways to narrow it, all of which the first version missed.**
  ///
  /// `--no-git` and a shallow checkout are the two everyone thinks of. An audit
  /// found four more, each a silent narrowing that leaves the job green:
  test('IT IS `detect`, NOT `dir` — the modern spelling of --no-git', () {
    // gitleaks v8.19 renamed the working-tree scan to `gitleaks dir`. Same
    // defect, different word: a guard that only forbids `--no-git` waves it
    // through.
    final steps = scanJob().value['steps'] as YamlList;
    for (final st in steps) {
      final run = (st as YamlMap)['run'];
      if (run is! String || !code(run).contains('gitleaks')) continue;
      final c = code(run);
      expect(
        RegExp(r'gitleaks[^\n|&]*\bdir\b').hasMatch(c),
        isFalse,
        reason:
            '`gitleaks dir` scans the working tree only, exactly like '
            '--no-git',
      );
      expect(
        c.contains('detect'),
        isTrue,
        reason: 'the history-walking subcommand is `detect`',
      );
    }
  });

  test('THE SOURCE IS THE WHOLE REPO, and no --log-opts trims the walk', () {
    final steps = scanJob().value['steps'] as YamlList;
    for (final st in steps) {
      final run = (st as YamlMap)['run'];
      if (run is! String || !code(run).contains('gitleaks')) continue;
      final c = code(run);
      // A narrowed source (`--source=/repo/web`) scans history, and only one
      // subtree of it — green while the backend's history goes unread.
      final src = RegExp(r'--source=(\S+)').firstMatch(c)?.group(1);
      expect(src, '/repo', reason: 'the scan must cover the whole repository');
      // `--log-opts` is passed straight to `git log`; `--log-opts=-1` walks one
      // commit and reports "1 commits scanned. no leaks found".
      expect(
        c.contains('--log-opts'),
        isFalse,
        reason: '--log-opts can trim the walk to a single commit',
      );
    }
  });

  test('nothing conditions the job or the step out of existence', () {
    // `if: false`, or a condition on a branch/event that never matches, makes
    // the job SKIP — which GitHub reports as neither success nor failure and
    // which a required-check rule treats as absent rather than failed.
    final entry = scanJob();
    expect(
      entry.value['if'],
      isNull,
      reason: 'a conditioned scan job is one `if:` away from never running',
    );
    for (final st in entry.value['steps'] as YamlList) {
      final run = (st as YamlMap)['run'];
      if (run is String && code(run).contains('gitleaks')) {
        expect(st['if'], isNull, reason: 'the scan step is conditioned');
      }
    }
  });

  test('the scan can fail the job — no continue-on-error', () {
    final job = scanJob().value;
    expect(job['continue-on-error'], isNot(true));
    for (final s in job['steps'] as YamlList) {
      if ((s as YamlMap)['run'] is String &&
          code(s['run'] as String).contains('gitleaks')) {
        expect(s['continue-on-error'], isNot(true));
      }
    }
  });
}
