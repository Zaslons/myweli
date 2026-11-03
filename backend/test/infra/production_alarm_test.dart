import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The alarm on the daily monitor: it closes on a green scheduled run, reopens
/// on the next failure, and tells a person. Design:
/// docs/design/production-alarm-close.md
///
/// The monitor was red from 2026-10-21 to 2026-11-02 and nobody noticed, because
/// the alarm was a comment on an issue that had been open since September. This
/// runs the two jobs' real scripts rather than reading them: a text pin would
/// pass a script whose branches were swapped.
///
/// **What this cannot see.** Only GitHub evaluates `if:`, so that line is held
/// as exact text and its behaviour is unproved until a real run. Nor can it see
/// whether the email arrives, which only the owner can say.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  final workflow =
      loadYaml(
            File(
              '$root/.github/workflows/production-checks.yml',
            ).readAsStringSync(),
          )
          as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;

  const alarmJobs = {'report', 'clear'};
  const mention = '@Zaslons';
  const alarmTitle = 'Production checks are failing';
  const runUrl = 'https://github.com/Zaslons/myweli/actions/runs/1';

  final checks = jobs.keys
      .cast<String>()
      .where((job) => !alarmJobs.contains(job))
      .toSet();

  group('when the alarm closes', () {
    for (final job in alarmJobs) {
      test('$job hears from every other job in the file', () {
        // Derived, not listed. An eighth check missing from `clear.needs` would
        // let the alarm close while that check is red.
        expect(checks, isNotEmpty);
        expect(
          (jobs[job]['needs'] as YamlList).cast<String>().toSet(),
          checks,
          reason: '$job.needs must be exactly the checks in this file',
        );
      });

      test('$job keeps the workflow\'s issues: write', () {
        // A `permissions` block on the job replaces the workflow's, whole.
        expect(workflow['permissions']['issues'], 'write');
        expect((jobs[job] as YamlMap).containsKey('permissions'), isFalse);
      });
    }

    test('only a fully green scheduled run can close it', () {
      // A manual run takes a custom `target`, and a green run against another
      // site must not close the production alarm. Exact text because nothing
      // here can evaluate it: changing it should be a deliberate edit.
      expect(
        jobs['clear']['if'],
        "github.event_name == 'schedule' && success()",
      );
    });

    test('any failure reaches the report job', () {
      expect(jobs['report']['if'], 'failure()');
    });

    test('no check can count as passed without passing', () {
      for (final name in checks) {
        final job = jobs[name] as YamlMap;
        for (final key in ['if', 'continue-on-error']) {
          expect(job.containsKey(key), isFalse, reason: '$name has $key');
          for (final step in (job['steps'] as YamlList).cast<YamlMap>()) {
            expect(
              step.containsKey(key),
              isFalse,
              reason: '$name has a step with $key: ${step['name']}',
            );
          }
        }
      }
    });
  });

  group('the scripts, against a stand-in gh', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('production_alarm_');
      // Behaves like the real gh as measured in the spec, §2: it cannot resolve
      // the repo without GH_REPO, and lists only open issues unless told
      // otherwise. Unknown commands fail, so a script can't pass by calling
      // something this does not know about.
      File('${dir.path}/gh').writeAsStringSync(r'''#!/usr/bin/env bash
{ printf '%s\037' "$@"; printf '\036'; } >> "$GH_LOG"
if [ -z "${GH_REPO:-}" ]; then
  echo 'failed to run git: fatal: not a git repository' >&2
  exit 1
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo 'gh: set the GH_TOKEN environment variable' >&2
  exit 4
fi
known() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  jq -e --argjson n "$1" 'any(.[]; .number == $n)' \
    <<<"$FAKE_ISSUES" >/dev/null
}
verb=$1 action=$2
shift 2
if [ "$verb" != issue ]; then
  echo "unknown gh command: $verb" >&2
  exit 64
fi
case "$action" in
  list)
    if [ -n "${FAKE_LIST_FAILS:-}" ]; then
      echo 'HTTP 502' >&2
      exit 1
    fi
    state=open filter=.
    while [ $# -gt 0 ]; do
      case "$1" in
        --state) state=$2; shift 2 ;;
        --jq) filter=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    jq -c --arg state "$state" \
      'map(select($state == "all" or (.state | ascii_downcase) == $state))' \
      <<<"$FAKE_ISSUES" | jq -r "$filter"
    ;;
  view)
    if ! known "$1"; then
      echo "no issue found: $1" >&2
      exit 1
    fi
    jq -r --argjson n "$1" 'map(select(.number == $n))[0].state' \
      <<<"$FAKE_ISSUES"
    ;;
  close|reopen|comment)
    if ! known "$1"; then
      echo "no issue found: $1" >&2
      exit 1
    fi
    ;;
  create) ;;
  *)
    echo "unknown gh command: issue $action" >&2
    exit 64
    ;;
esac
''');
      Process.runSync('chmod', ['+x', '${dir.path}/gh']);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    /// Runs [job]'s real script the way a runner does, passing only the env
    /// names the YAML declares: deleting GH_REPO from the workflow removes it
    /// here too. The parent environment stays out so that a GH_REPO on the
    /// tester's machine cannot rescue the script.
    ({int exitCode, String stderr, List<List<String>> calls}) run(
      String job, {
      required List<Map<String, Object>> issues,
      bool listFails = false,
    }) {
      final step = (jobs[job]['steps'] as YamlList).cast<YamlMap>().singleWhere(
        (s) => s.containsKey('run'),
      );
      final script = File('${dir.path}/script.sh')
        ..writeAsStringSync(step['run'] as String);
      final log = File('${dir.path}/gh.log')..writeAsStringSync('');

      final result = Process.runSync(
        'bash',
        ['-e', script.path],
        includeParentEnvironment: false,
        environment: {
          for (final name in (step['env'] as YamlMap).keys.cast<String>())
            name: name == 'RUN' ? runUrl : 'fixture-$name',
          'PATH': '${dir.path}:${Platform.environment['PATH']}',
          'GH_LOG': log.path,
          'FAKE_ISSUES': jsonEncode(issues),
          if (listFails) 'FAKE_LIST_FAILS': '1',
        },
      );

      final calls = log
          .readAsStringSync()
          .split('\x1e')
          .where((call) => call.isNotEmpty)
          .map((call) => (call.split('\x1f')..removeLast()))
          .toList();
      return (
        exitCode: result.exitCode,
        stderr: result.stderr as String,
        calls: calls,
      );
    }

    Map<String, Object> issue(int number, String state, [String? title]) => {
      'number': number,
      'title': title ?? alarmTitle,
      'state': state,
    };

    /// Every `gh issue <action>` call, as its arguments after the action.
    List<List<String>> calls(List<List<String>> all, String action) => all
        .where((call) => call[0] == 'issue' && call[1] == action)
        .map((call) => call.sublist(2))
        .toList();

    String flag(List<String> args, String name) => args[args.indexOf(name) + 1];

    group('clear', () {
      test('an open alarm is closed, mentioning the owner and the run', () {
        final r = run('clear', issues: [issue(549, 'OPEN')]);
        expect(r.exitCode, 0, reason: r.stderr);
        final closes = calls(r.calls, 'close');
        expect(closes, hasLength(1));
        expect(closes.single.first, '549');
        final comment = flag(closes.single, '--comment');
        expect(comment, startsWith(mention));
        expect(comment, contains(runUrl));
      });

      test('an alarm already closed is left alone, and the job passes', () {
        final r = run('clear', issues: [issue(549, 'CLOSED')]);
        expect(r.exitCode, 0, reason: r.stderr);
        expect(calls(r.calls, 'close'), isEmpty);
      });

      test('no alarm at all means nothing to do, and the job passes', () {
        final r = run('clear', issues: []);
        expect(r.exitCode, 0, reason: r.stderr);
        expect(calls(r.calls, 'view'), isEmpty);
        expect(calls(r.calls, 'close'), isEmpty);
      });

      test('a similar title is not the alarm', () {
        final similar = issue(700, 'OPEN', '$alarmTitle on staging');
        final alone = run('clear', issues: [similar]);
        expect(alone.exitCode, 0, reason: alone.stderr);
        expect(calls(alone.calls, 'close'), isEmpty);

        final both = run('clear', issues: [similar, issue(549, 'OPEN')]);
        expect(both.exitCode, 0, reason: both.stderr);
        expect(calls(both.calls, 'close').single.first, '549');
      });

      test(
        'a failed lookup fails the job, rather than saying nothing to do',
        () {
          final r = run('clear', issues: [issue(549, 'OPEN')], listFails: true);
          expect(r.exitCode, isNot(0));
          expect(calls(r.calls, 'close'), isEmpty);
        },
      );
    });

    group('report', () {
      test('no alarm yet: opens it, mentioning the owner', () {
        final r = run('report', issues: []);
        expect(r.exitCode, 0, reason: r.stderr);
        final creates = calls(r.calls, 'create');
        expect(creates, hasLength(1));
        expect(flag(creates.single, '--title'), alarmTitle);
        expect(flag(creates.single, '--body'), startsWith(mention));
        expect(calls(r.calls, 'comment'), isEmpty);
        expect(calls(r.calls, 'reopen'), isEmpty);
      });

      test('an open alarm: comments, mentioning the owner', () {
        final r = run('report', issues: [issue(549, 'OPEN')]);
        expect(r.exitCode, 0, reason: r.stderr);
        final comments = calls(r.calls, 'comment');
        expect(comments.single.first, '549');
        expect(flag(comments.single, '--body'), startsWith(mention));
        expect(calls(r.calls, 'reopen'), isEmpty);
        expect(calls(r.calls, 'create'), isEmpty);
      });

      test('a closed alarm: a new failure is a reopening, not a new issue', () {
        final r = run('report', issues: [issue(549, 'CLOSED')]);
        expect(r.exitCode, 0, reason: r.stderr);
        expect(calls(r.calls, 'reopen').single.first, '549');
        final comments = calls(r.calls, 'comment');
        expect(comments.single.first, '549');
        expect(flag(comments.single, '--body'), startsWith(mention));
        expect(calls(r.calls, 'create'), isEmpty);
      });
    });
  });
}
