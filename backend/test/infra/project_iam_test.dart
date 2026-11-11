import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `infra/gcp/43-verify-project-iam.sh` and the `iam` job of
/// `production-checks.yml`: has a broad grant come back into project myweli's
/// IAM policy? Design: docs/design/infra-iam-drift-check.md.
///
/// Two grants Google's automation added on 2026-08-05 were removed on
/// 2026-11-11. The daily job reads the live policy; this file is where every
/// red branch is reached, since reaching one against production means putting a
/// forbidden grant back. It runs the real script, on saved policies and against
/// a stand-in gcloud, and the job's negative control against a stand-in curl.
///
/// **What this cannot see.** Whether the identity can read the live policy, and
/// what Google answers when it asks: only the daily run shows that.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  const scriptPath = 'infra/gcp/43-verify-project-iam.sh';
  final script = File('$root/$scriptPath').readAsStringSync();

  final workflow =
      loadYaml(
            File(
              '$root/.github/workflows/production-checks.yml',
            ).readAsStringSync(),
          )
          as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;

  const owner = 'user:sadreddinedaher@gmail.com';
  const firebase =
      'serviceAccount:firebase-adminsdk-fbsvc@myweli.iam.gserviceaccount.com';
  const compute =
      'serviceAccount:731308991240-compute@developer.gserviceaccount.com';
  const deployer =
      'serviceAccount:myweli-deployer@myweli.iam.gserviceaccount.com';
  const checks = 'serviceAccount:myweli-checks@myweli.iam.gserviceaccount.com';

  Map<String, Object> binding(
    String role,
    List<String> members, [
    Map<String, String>? condition,
  ]) => {'role': role, 'members': members, 'condition': ?condition};

  /// The shape of the live policy on 2026-11-11, cut down: the owner, the
  /// grants that stayed, and the custom roles this check relies on.
  List<Map<String, Object>> clean() => [
    binding('roles/owner', [owner]),
    binding('roles/firebase.sdkAdminServiceAgent', [firebase]),
    binding('roles/run.admin', [deployer]),
    binding('roles/artifactregistry.writer', [deployer]),
    binding('roles/cloudsql.client', [
      'serviceAccount:myweli-run@myweli.iam.gserviceaccount.com',
    ]),
    binding('projects/myweli/roles/logBucketConfigReader', [checks]),
    binding('projects/myweli/roles/projectIamPolicyReader', [checks]),
  ];

  Map<String, Object> policy(List<Map<String, Object>> bindings) => {
    'bindings': bindings,
    'etag': 'BwZgBhnIRBI=',
    'version': 1,
  };

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('project_iam_'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A gcloud that logs every call and answers only `projects get-iam-policy`,
  /// with $FAKE_POLICY, or fails when $FAKE_GCLOUD_FAILS is set. Anything else
  /// fails, so the script cannot pass by calling something this does not know.
  void standInGcloud() {
    File('${dir.path}/gcloud').writeAsStringSync(r'''#!/usr/bin/env bash
{ printf '%s\037' "$@"; printf '\036'; } >> "$GCLOUD_LOG"
case "$1 $2" in
  'projects get-iam-policy')
    if [ -n "${FAKE_GCLOUD_FAILS:-}" ]; then
      echo 'ERROR: (gcloud.projects.get-iam-policy) [x] does not have permission' >&2
      exit 1
    fi
    echo 'WARNING: a stand-in warning on stderr' >&2
    printf '%s' "$FAKE_POLICY"
    ;;
  'auth print-access-token')
    if [ -n "${FAKE_TOKEN_FAILS:-}" ]; then
      echo 'ERROR: no credentials' >&2
      exit 1
    fi
    echo 'stand-in-token'
    ;;
  *)
    echo "unknown gcloud command: $*" >&2
    exit 64
    ;;
esac
''');
    Process.runSync('chmod', ['+x', '${dir.path}/gcloud']);
  }

  List<List<String>> logged(File log) => log
      .readAsStringSync()
      .split('\x1e')
      .where((call) => call.isNotEmpty)
      .map((call) => (call.split('\x1f')..removeLast()))
      .toList();

  /// Runs the script the way the runner does, with only PATH from outside, so
  /// that a gcloud or a variable on the tester's machine cannot rescue it.
  ({int exitCode, String out, List<List<String>> gcloud}) verify({
    Object? fixture,
    String? rawFixture,
    String? live,
    bool liveFails = false,
  }) {
    standInGcloud();
    final log = File('${dir.path}/gcloud.log')..writeAsStringSync('');
    String? path;
    if (fixture != null || rawFixture != null) {
      final f = File('${dir.path}/policy.json')
        ..writeAsStringSync(rawFixture ?? jsonEncode(fixture));
      path = f.path;
    }
    final result = Process.runSync(
      'bash',
      ['$root/$scriptPath'],
      includeParentEnvironment: false,
      environment: {
        'PATH': '${dir.path}:${Platform.environment['PATH']}',
        'GCLOUD_LOG': log.path,
        'PROJECT_IAM_POLICY_FILE': ?path,
        'FAKE_POLICY': ?live,
        if (liveFails) 'FAKE_GCLOUD_FAILS': '1',
      },
    );
    return (
      exitCode: result.exitCode,
      out: '${result.stdout}${result.stderr}',
      gcloud: logged(log),
    );
  }

  group('red on the grants it exists for', () {
    test('the two removed on 2026-11-11, put back', () {
      final r = verify(
        fixture: policy([
          ...clean(),
          binding('roles/iam.serviceAccountTokenCreator', [firebase]),
          binding('roles/editor', [compute]),
        ]),
      );
      expect(r.exitCode, 1, reason: r.out);
      expect(
        r.out,
        contains('roles/iam.serviceAccountTokenCreator is held by $firebase'),
      );
      expect(r.out, contains('roles/editor is held by $compute'));
    });

    final cases = <String, Map<String, Object>>{
      'Owner for another account': binding('roles/owner', [
        owner,
        'user:someone@example.com',
      ]),
      'Editor for another user': binding('roles/editor', [
        'user:someone@example.com',
      ]),
      'Editor for a group': binding('roles/editor', ['group:ops@example.com']),
      'Editor for a deleted account, which an undelete restores': binding(
        'roles/editor',
        ['deleted:serviceAccount:old@myweli.iam.gserviceaccount.com?uid=1'],
      ),
      'Token Creator on the project, for any member': binding(
        'roles/iam.serviceAccountTokenCreator',
        [deployer],
      ),
      'Service Account User on the project': binding(
        'roles/iam.serviceAccountUser',
        [deployer],
      ),
      'Editor under a condition': binding(
        'roles/editor',
        [compute],
        {
          'title': 'until-2030',
          'expression': 'request.time < timestamp("2030-01-01T00:00:00Z")',
        },
      ),
      'Editor read at policy version 1, renamed _withcond_': binding(
        'roles/editor_withcond_2bd3e8f9c7a1',
        [compute],
      ),
      'Token Creator read at policy version 1, renamed _withcond_': binding(
        'roles/iam.serviceAccountTokenCreator_withcond_99aa',
        [firebase],
      ),
    };

    cases.forEach((name, bad) {
      test(name, () {
        final r = verify(fixture: policy([...clean(), bad]));
        expect(r.exitCode, 1, reason: r.out);
        expect(r.out, contains('A BROAD GRANT IS IN'));
        for (final m in bad['members']! as List<String>) {
          if (m != owner) expect(r.out, contains('held by $m'));
        }
      });
    });

    test('a conditional grant says that the condition does not excuse it', () {
      final r = verify(
        fixture: policy([...clean(), cases['Editor under a condition']!]),
      );
      expect(r.out, contains('until-2030'));
      expect(r.out, contains('does not remove it'));
    });
  });

  group('green on what is allowed', () {
    test('the live shape of 2026-11-11', () {
      final r = verify(fixture: policy(clean()));
      expect(r.exitCode, 0, reason: r.out);
      expect(r.out, contains('No broad grant'));
    });

    test('the owner holding Editor as well as Owner', () {
      final r = verify(
        fixture: policy([
          ...clean(),
          binding('roles/editor', [owner]),
        ]),
      );
      expect(r.exitCode, 0, reason: r.out);
    });

    test('Token Creator with a name that only starts the same way', () {
      // An exact match after the _withcond_ strip, not a prefix: this is a
      // different (hypothetical) role and is not this check's business.
      final r = verify(
        fixture: policy([
          ...clean(),
          binding('roles/iam.serviceAccountTokenCreatorX', [deployer]),
        ]),
      );
      expect(r.exitCode, 0, reason: r.out);
    });
  });

  group('it refuses to report success having read nothing', () {
    // Each says which guard stopped it. Without the message, the shape check
    // was invisible: the owner check fails on the same inputs a step later
    // (watched: deleting the shape check left every test green).
    const notAPolicy = 'not an IAM policy with bindings';
    const notThisProject = 'none gives $owner roles/owner';
    final vacuous = <String, (String, String)>{
      'an empty object': ('{}', notAPolicy),
      'bindings that are not a list': ('{"bindings": {}}', notAPolicy),
      'a list, not a policy': ('[]', notAPolicy),
      'not JSON at all': ('<html>502 Bad Gateway</html>', notAPolicy),
      'nothing at all': ('', notAPolicy),
      'no bindings': (jsonEncode(policy([])), notThisProject),
      "a policy without the owner's roles/owner, so not this project's": (
        jsonEncode(
          policy(clean().where((b) => b['role'] != 'roles/owner').toList()),
        ),
        notThisProject,
      ),
      'the owner under a role that only looks like Owner': (
        jsonEncode(
          policy([
            ...clean().where((b) => b['role'] != 'roles/owner'),
            binding('roles/ownerX', [owner]),
          ]),
        ),
        notThisProject,
      ),
    };

    vacuous.forEach((name, c) {
      final (raw, why) = c;
      test(name, () {
        final r = verify(rawFixture: raw);
        expect(r.exitCode, 1, reason: r.out);
        expect(r.out, contains(why));
        expect(r.out, isNot(contains('No broad grant')));
      });
    });

    test('a fixture path that does not exist', () {
      standInGcloud();
      final r = Process.runSync(
        'bash',
        ['$root/$scriptPath'],
        includeParentEnvironment: false,
        environment: {
          'PATH': '${dir.path}:${Platform.environment['PATH']}',
          'GCLOUD_LOG': '${dir.path}/gcloud.log',
          'PROJECT_IAM_POLICY_FILE': '${dir.path}/missing.json',
        },
      );
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    });
  });

  group('live, against a stand-in gcloud', () {
    test('it reads the policy with one call, and nothing else', () {
      final r = verify(live: jsonEncode(policy(clean())));
      expect(r.exitCode, 0, reason: r.out);
      expect(r.gcloud, [
        ['projects', 'get-iam-policy', 'myweli', '--format=json'],
      ]);
      // The stand-in prints a warning on stderr on success; it must not have
      // ended up inside the JSON.
      expect(r.out, contains('No broad grant'));
    });

    test('a red read also makes that one call, and nothing else', () {
      final r = verify(
        live: jsonEncode(
          policy([
            ...clean(),
            binding('roles/editor', [compute]),
          ]),
        ),
      );
      expect(r.exitCode, 1, reason: r.out);
      expect(r.gcloud, hasLength(1));
    });

    test('a refused read is a failure, not a pass', () {
      final r = verify(live: '', liveFails: true);
      expect(r.exitCode, 1, reason: r.out);
      expect(r.out, contains('nothing was measured'));
      expect(r.out, contains('does not have permission'));
    });

    test('a rehearsal announces itself and calls nothing', () {
      final r = verify(fixture: policy(clean()));
      expect(r.out, contains('REHEARSAL, not a measurement'));
      expect(r.gcloud, isEmpty);
    });
  });

  group('it cannot change anything', () {
    // Comments are NOT stripped: secret_pins_test.dart gives the reason. In a
    // file whose argument is « it never writes », a commented-out write is a
    // line somebody uncomments.
    const forbidden = {
      'set-iam-policy': 'replaces the whole policy',
      'add-iam-policy-binding': 'a checker that can widen what it checks',
      'remove-iam-policy-binding':
          'a checker that removes what it finds, without the owner deciding',
      'roles create': 'creates a role',
      'roles update': 'a checker that can widen its own role',
      'keys create': 'mints a key',
    };
    forbidden.forEach((verb, why) {
      test('the script never mentions `$verb`', () {
        expect(
          script.contains(verb),
          isFalse,
          reason: '$scriptPath mentions `$verb`, which $why',
        );
      });
    });

    test('the role it runs under holds getIamPolicy and nothing else', () {
      final provisioning = File(
        '$root/infra/gcp/41-iam-checks-sa.sh',
      ).readAsStringSync();
      final yaml = RegExp(
        r"cat > /tmp/iam-policy-reader-role\.yaml <<'YAML'\n([\s\S]*?)\nYAML\n",
      ).firstMatch(provisioning);
      expect(
        yaml,
        isNotNull,
        reason: 'the projectIamPolicyReader role is gone',
      );
      final role = loadYaml(yaml!.group(1)!) as YamlMap;
      expect(
        (role['includedPermissions'] as YamlList).toList(),
        ['resourcemanager.projects.getIamPolicy'],
        reason:
            'projectIamPolicyReader has been widened. The daily job asks Google '
            'whether CI can change the policy; this asks the source first',
      );
      expect(
        provisioning,
        contains(
          '--role="projects/\${PROJECT}/roles/\${POLICY_ROLE_ID}" --condition=None',
        ),
      );
    });
  });

  group('the daily job', () {
    YamlList steps() => jobs['iam']['steps'] as YamlList;

    test('exists, runs the script as myweli-checks, and is heard', () {
      expect(
        jobs.keys,
        contains('iam'),
        reason: 'a checker nothing runs is a file',
      );
      final s = steps().cast<YamlMap>();
      final auth = s.firstWhere(
        (x) => (x['uses'] as String? ?? '').startsWith(
          'google-github-actions/auth',
        ),
      );
      expect(
        auth['with']['service_account'],
        'myweli-checks@myweli.iam.gserviceaccount.com',
        reason: 'not the deployer: it holds run.admin',
      );
      final authAt = s.indexOf(auth);
      final runAt = s.indexWhere(
        (x) => (x['run'] as String? ?? '').contains(scriptPath),
      );
      expect(runAt, greaterThan(authAt));
      expect((jobs['report']['needs'] as YamlList).toList(), contains('iam'));
      expect((jobs['clear']['needs'] as YamlList).toList(), contains('iam'));
    });

    test('no workflow sets the rehearsal file', () {
      // The ASSIGNMENT form: the workflow says in a comment that it is not set.
      for (final f in Directory('$root/.github/workflows').listSync()) {
        if (f is! File) continue;
        expect(
          RegExp(
            r'PROJECT_IAM_POLICY_FILE\s*[:=]',
          ).hasMatch(f.readAsStringSync()),
          isFalse,
          reason: '${f.path} sets the fixture, so it measures a file',
        );
      }
    });
  });

  group('the negative control, against a stand-in curl', () {
    late String control;

    setUp(() {
      final step = (jobs['iam']['steps'] as YamlList)
          .cast<YamlMap>()
          .singleWhere(
            (s) => (s['name'] as String? ?? '').contains(
              'CANNOT change the policy',
            ),
          );
      control = step['run'] as String;
      // Answers with $FAKE_BODY and $FAKE_CODE as the step's -w asks, or fails
      // as curl does when the network does.
      File('${dir.path}/curl').writeAsStringSync(r'''#!/usr/bin/env bash
{ printf '%s\037' "$@"; printf '\036'; } >> "$CURL_LOG"
if [ -n "${FAKE_CURL_FAILS:-}" ]; then
  echo 'curl: (6) Could not resolve host' >&2
  exit 6
fi
printf '%s\n%s' "$FAKE_BODY" "${FAKE_CODE:-200}"
''');
      Process.runSync('chmod', ['+x', '${dir.path}/curl']);
    });

    ({int exitCode, String out, List<List<String>> curl}) ask({
      Object? answer,
      String? raw,
      int code = 200,
      bool curlFails = false,
      bool tokenFails = false,
    }) {
      standInGcloud();
      final file = File('${dir.path}/control.sh')..writeAsStringSync(control);
      final curlLog = File('${dir.path}/curl.log')..writeAsStringSync('');
      final r = Process.runSync(
        'bash',
        ['-e', file.path],
        includeParentEnvironment: false,
        environment: {
          'PATH': '${dir.path}:${Platform.environment['PATH']}',
          'GCLOUD_LOG': '${dir.path}/gcloud.log',
          'CURL_LOG': curlLog.path,
          'FAKE_BODY': raw ?? jsonEncode(answer),
          'FAKE_CODE': '$code',
          if (curlFails) 'FAKE_CURL_FAILS': '1',
          if (tokenFails) 'FAKE_TOKEN_FAILS': '1',
        },
      );
      return (
        exitCode: r.exitCode,
        out: '${r.stdout}${r.stderr}',
        curl: logged(curlLog),
      );
    }

    const get = 'resourcemanager.projects.getIamPolicy';
    const set = 'resourcemanager.projects.setIamPolicy';
    const update = 'iam.roles.update';

    test('green: it reads and cannot write', () {
      final r = ask(
        answer: {
          'permissions': [get],
        },
      );
      expect(r.exitCode, 0, reason: r.out);
      expect(r.out, contains('cannot change it'));
    });

    test('it asks, by POST, about this project, as the identity', () {
      final r = ask(
        answer: {
          'permissions': [get],
        },
      );
      final args = r.curl.single;
      expect(
        args,
        contains(
          'https://cloudresourcemanager.googleapis.com/v1/projects/myweli:testIamPermissions',
        ),
      );
      expect(args[args.indexOf('-X') + 1], 'POST');
      expect(args, contains('Authorization: Bearer stand-in-token'));
      final asked =
          (jsonDecode(args[args.indexOf('-d') + 1]) as Map)['permissions']
              as List;
      expect(asked, containsAll([get, set, update]));
    });

    for (final widened in [set, update]) {
      test('red: the identity holds $widened', () {
        final r = ask(
          answer: {
            'permissions': [get, widened],
          },
        );
        expect(r.exitCode, isNot(0), reason: r.out);
        expect(r.out, contains('holds $widened'));
      });
    }

    final unmeasured =
        <
          String,
          ({
            Object? answer,
            String? raw,
            int code,
            bool curlFails,
            bool tokenFails,
          })
        >{
          'the read itself is gone (`{}`)': (
            answer: <String, Object>{},
            raw: null,
            code: 200,
            curlFails: false,
            tokenFails: false,
          ),
          'Google refuses the question': (
            answer: {'error': 'x'},
            raw: null,
            code: 403,
            curlFails: false,
            tokenFails: false,
          ),
          'the network fails': (
            answer: null,
            raw: '',
            code: 200,
            curlFails: true,
            tokenFails: false,
          ),
          'no token': (
            answer: {
              'permissions': [get],
            },
            raw: null,
            code: 200,
            curlFails: false,
            tokenFails: true,
          ),
          'the answer is not JSON': (
            answer: null,
            raw: '<html>oops</html>',
            code: 200,
            curlFails: false,
            tokenFails: false,
          ),
          'the answer is a list': (
            answer: [get],
            raw: null,
            code: 200,
            curlFails: false,
            tokenFails: false,
          ),
        };
    test('an answer that is not an object says so', () {
      // As above: the getIamPolicy test fails on the same inputs a step later,
      // so only the message shows the parse guard is there (watched).
      for (final raw in [
        '<html>oops</html>',
        jsonEncode([get]),
      ]) {
        final r = ask(raw: raw);
        expect(r.exitCode, isNot(0), reason: r.out);
        expect(r.out, contains('not a testIamPermissions answer'));
      }
    });

    unmeasured.forEach((name, c) {
      test('red, not green: $name', () {
        final r = ask(
          answer: c.answer,
          raw: c.raw,
          code: c.code,
          curlFails: c.curlFails,
          tokenFails: c.tokenFails,
        );
        expect(r.exitCode, isNot(0), reason: r.out);
        expect(r.out, isNot(contains('as designed')));
      });
    });
  });
}
