import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `infra/gcp/staging.state` — the one committed word that says whether
/// staging exists (docs/design/infra-staging.md §9).
///
/// Staging can be retired for cost and recreated before the launch rehearsals.
/// Three things read the switch: the deploy workflow, `98-verify-secret-pins.sh`
/// and `95-emitter-lag.sh`. Each of them is also on PRODUCTION's path — the
/// workflow is the only thing that builds the image a production dispatch
/// promotes, 98 is the gate in front of every production `replace` and the
/// daily check, 95 runs after every deploy — so the properties pinned here are
/// mostly about what the switch must NOT do:
///
/// * it must not stop a merge from building and pushing the image;
/// * it must not reach the resolver's production branch, so the resolver can
///   never skip a production deploy — 98 and 95 DO read it on production runs,
///   which is why its content is the first thing pinned below;
/// * `absent` must narrow the checks to production, never to nothing;
/// * any value but the two words must FAIL, because a typo that silently
///   defaulted either way is exactly the drift these checks exist to catch.
///
/// Where a property can be watched by running the real script, it is: the
/// workflow's resolver is executed from its own `run:` text, 98 runs on its
/// rehearsal fixture, and 95 runs against a throwaway repository with a stub
/// `gcloud` first on PATH and an empty gcloud config, so no real cloud call can
/// be made even if the stub were bypassed.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  String read(String path) => File('$root/$path').readAsStringSync();

  final workflowText = read('.github/workflows/deploy-backend.yml');
  final workflow = loadYaml(workflowText) as YamlMap;
  final steps = (workflow['jobs']['deploy']['steps'] as YamlList)
      .cast<YamlMap>();

  /// The one step whose name contains [part]. Failing loudly when there is not
  /// exactly one: a renamed step must not turn every assertion into a check
  /// against an empty map.
  YamlMap step(String part) {
    final found = steps
        .where((s) => (s['name'] as String? ?? '').contains(part))
        .toList();
    expect(
      found,
      hasLength(1),
      reason: 'expected exactly one step named like "$part"',
    );
    return found.single;
  }

  String run(YamlMap s) => s['run'] as String? ?? '';

  /// Where [field] of the step named like [part] sits, as [occurrences]
  /// prints it.
  String at(String part, String field) =>
      '.jobs.deploy.steps[${step(part)['name']}].$field';

  /// Every place in the PARSED workflow — keys and scalar values at any depth,
  /// comments excluded — where [pattern] occurs. Steps are named by their
  /// name, not their index, so a failure says where.
  List<String> occurrences(RegExp pattern) {
    final found = <String>[];
    void walk(Object? node, String path) {
      if (node is YamlMap) {
        node.forEach((k, v) {
          if (pattern.hasMatch('$k')) found.add('$path.$k (key)');
          walk(v, '$path.$k');
        });
      } else if (node is YamlList) {
        for (var i = 0; i < node.length; i++) {
          final item = node[i];
          final name = item is YamlMap && item['name'] is String
              ? item['name']
              : '$i';
          walk(item, '$path[$name]');
        }
      } else if (node is String && pattern.hasMatch(node)) {
        found.add(path);
      }
    }

    walk(workflow, '');
    return found;
  }

  /// GITHUB_ENV as Actions reads it: one `KEY=value` per line, the last write
  /// winning. Parsed rather than searched, because `contains('DEPLOY=skip')`
  /// also matches `DEPLOY=skipped` — which `env.DEPLOY != 'skip'` would read
  /// as "deploy".
  Map<String, String> parseEnv(String text) => {
    for (final line in const LineSplitter().convert(text))
      if (line.contains('='))
        line.substring(0, line.indexOf('=')): line.substring(
          line.indexOf('=') + 1,
        ),
  };

  /// A scratch directory that is removed when the test that made it ends.
  Directory scratch(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() => d.deleteSync(recursive: true));
    return d;
  }

  /// A child environment that cannot reach the real project: the parent's
  /// PATH (with [stubBin] in front when given) and nothing else, plus an empty
  /// gcloud configuration directory — no account, no credentials — so even a
  /// gcloud that slipped past the stub could not authenticate.
  Map<String, String> sealedEnv(Directory home, {String? stubBin}) {
    final config = Directory('${home.path}/gcloud-config')..createSync();
    return {
      'PATH': [
        ?stubBin,
        Platform.environment['PATH'] ?? '/usr/bin:/bin',
      ].join(':'),
      'HOME': home.path,
      'CLOUDSDK_CONFIG': config.path,
    };
  }

  /// An executable stub `gcloud` in a fresh scratch directory: the directory,
  /// and the bin folder to put first on PATH.
  ({Directory dir, String bin}) stubGcloud(String prefix, String body) {
    final dir = scratch(prefix);
    final stub = File('${dir.path}/stub-bin/gcloud')
      ..createSync(recursive: true)
      ..writeAsStringSync(body);
    expect(Process.runSync('chmod', ['+x', stub.path]).exitCode, 0);
    return (dir: dir, bin: '${dir.path}/stub-bin');
  }

  /// Runs the real resolver in a scratch checkout holding [state] (or no
  /// state file at all), and returns the exit code, stdout and what it wrote
  /// to GITHUB_ENV, parsed the way Actions reads it.
  ({int code, String out, Map<String, String> env}) resolve(
    String environment,
    String? state,
  ) {
    final dir = scratch('resolver_');
    if (state != null) {
      File('${dir.path}/infra/gcp/staging.state')
        ..createSync(recursive: true)
        ..writeAsStringSync(state);
    }
    final githubEnv = File('${dir.path}/github_env')..writeAsStringSync('');
    final r = Process.runSync(
      'bash',
      ['-c', run(step("Resolve this environment's target"))],
      workingDirectory: dir.path,
      includeParentEnvironment: false,
      environment: {
        ...sealedEnv(dir),
        'ENVIRONMENT': environment,
        'GITHUB_ENV': githubEnv.path,
      },
    );
    return (
      code: r.exitCode,
      out: '${r.stdout}${r.stderr}',
      env: parseEnv(githubEnv.readAsStringSync()),
    );
  }

  group('the switch itself', () {
    test('it holds exactly `present` or `absent`, and a newline', () {
      // Every reader compares the whole file to one of the two words, so a
      // trailing space, a comment or a capital is not "probably absent" — it
      // is a red deploy. Better to find that here than on the merge run.
      final text = read('infra/gcp/staging.state');
      expect(
        RegExp(r'^(present|absent)\n$').hasMatch(text),
        isTrue,
        reason:
            'infra/gcp/staging.state reads ${jsonEncode(text)}; the readers '
            'accept only "present" or "absent" (docs/design/infra-staging.md §9)',
      );
    });

    test('each of the three readers actually reads it', () {
      // The reading LINE, not the word: all three also mention the file in
      // comments, and a comment that names the switch reads nothing.
      expect(
        read('infra/gcp/98-verify-secret-pins.sh'),
        contains(r'STATE_FILE="${HERE}/staging.state"'),
      );
      expect(
        read('infra/gcp/95-emitter-lag.sh'),
        contains(r'STATE_FILE="$(dirname "${BASH_SOURCE[0]}")/staging.state"'),
      );
      expect(
        run(step("Resolve this environment's target")),
        contains('cat infra/gcp/staging.state'),
      );
    });
  });

  group('the workflow — what the switch may and may not touch', () {
    test('flipping it is a deploy trigger', () {
      // The PR that sets it back to `present` must itself deploy the
      // recreated staging; without the path, that merge runs nothing and the
      // environment sits on Google's placeholder image until some unrelated
      // backend change happens to merge.
      final on = (workflow[true] ?? workflow['on']) as YamlMap;
      expect(
        (on['push']['paths'] as YamlList).toList(),
        contains('infra/gcp/staging.state'),
      );
    });

    test('Deploy and Verify are the only steps it can skip', () {
      for (final name in [
        'Deploy the service',
        'Verify the revision actually serves',
      ]) {
        expect(
          step(name)['if'],
          "env.DEPLOY != 'skip'",
          reason:
              '"$name" must not run while staging is absent: `replace` would '
              'CREATE a service from a manifest whose secrets no longer exist',
        );
      }
      final skippable = steps
          .where((s) => (s['if'] as String? ?? '').contains("!= 'skip'"))
          .map((s) => s['name'])
          .toList();
      expect(
        skippable,
        hasLength(2),
        reason:
            'only the deploy and its verify may be skipped — found $skippable',
      );
    });

    test('the build, the pin gate and the emitter check have NO `if:`', () {
      // The trap this pins: "staging is absent, so skip the staging run" reads
      // naturally and is wrong. The build is the ONLY source of the image a
      // production dispatch promotes, 98 is production's pin gate as well, and
      // 95 is the only post-merge check of production's emitters.
      for (final name in [
        'Build and push',
        'The pinned secret versions are still enabled and current',
        'Every alert can still produce the string it watches for',
      ]) {
        expect(
          step(name).containsKey('if'),
          isFalse,
          reason:
              '"$name" became conditional — while staging is absent a merge '
              'would then leave production nothing to promote, or unchecked',
        );
      }
    });

    test(
      'only the resolver can set DEPLOY, and only on its staging branch',
      () {
        // Walked over the PARSED workflow, so comments — which name DEPLOY
        // freely — do not count, and every other place does. The trap is not
        // a second `echo` in some `run:`; it is one line in an `env:` block:
        // `DEPLOY: skip` at workflow, job or step level would skip Deploy and
        // Verify on EVERY run, production included, and finish green.
        final readers = {
          at("Resolve this environment's target", 'run'),
          at('a rollback pin must not be lifted', 'run'),
          at('Deploy the service', 'if'),
          at('Verify the revision actually serves', 'if'),
          at('Staging is absent', 'if'),
        };
        final where = occurrences(RegExp(r'\bDEPLOY\b'));
        expect(
          where.toSet(),
          readers,
          reason:
              'DEPLOY appears outside the resolver and its four readers — '
              'anything else can set it, or reads it without being pinned: '
              '$where',
        );
        expect(
          where.where((w) => w.endsWith('(key)')),
          isEmpty,
          reason: 'an `env:` block sets DEPLOY for every run that reaches it',
        );

        final writers = steps
            .where((s) => RegExp(r'\bDEPLOY=').hasMatch(run(s)))
            .map((s) => s['name'])
            .toList();
        expect(writers, ["Resolve this environment's target"]);

        final resolver = run(step("Resolve this environment's target"));
        final staging = resolver
            .split(RegExp(r'^\s+staging\)\s*$', multiLine: true))[1]
            .split(RegExp(r'^\s+production\)\s*$', multiLine: true))[0];
        final production = resolver
            .split(RegExp(r'^\s+production\)\s*$', multiLine: true))[1]
            .split(RegExp(r'^\s+\*\)\s*$', multiLine: true))[0];
        expect(staging, contains('staging.state'));
        expect(staging, contains('DEPLOY=skip'));
        expect(
          production,
          isNot(contains('staging.state')),
          reason:
              "the resolver's production branch reads the staging switch — a "
              'typo there could then SKIP a production deploy (98 and 95 read '
              'it anyway, and fail closed; this branch must not decide on it)',
        );
        expect(production, isNot(contains('DEPLOY')));
      },
    );

    test('a skipped run says so, and hands over the tag to promote', () {
      // A green run that deployed nothing reads exactly like one that did,
      // unless it says otherwise in words.
      final notice = step('Staging is absent');
      expect(notice['if'], "env.DEPLOY == 'skip'");
      expect(run(notice), contains(r'promote with image_tag=${SHA}'));
      expect(
        (notice['env'] as YamlMap)['SHA'],
        r'${{ steps.build.outputs.sha }}',
        reason: 'the tag must be the one this run built, not a guess',
      );
      final at = steps.indexOf(notice);
      expect(
        at,
        greaterThan(steps.indexOf(step('Build and push'))),
        reason: 'it reads the build step output',
      );
    });

    group('a refused production dispatch gets a value whenever staging '
        'yields no verified tag', () {
      // The hint reads staging's serving tag. With staging absent there is no
      // tag to verify — the service is gone, or mid-recreate on Google's
      // placeholder labelled `bootstrap`, which resolves to nothing — and a
      // refusal that hands over nothing is a research task. Run from the
      // step's own text behind a stub gcloud: the stub prints NEWEST-IMAGES
      // for `images list`, so its presence in the output is the list.
      const image = 'europe-west9-docker.pkg.dev/myweli/myweli/api';
      ({int code, String out}) hint({
        String? stagingImage,
        String? commit,
        String? digest,
      }) {
        final g = stubGcloud('hint_', r'''#!/bin/sh
case "$*" in
  *"describe myweli-api-staging"*"containers[0].image"*)
    [ -n "$STUB_IMAGE" ] && { echo "$STUB_IMAGE"; exit 0; }; exit 1 ;;
  *"describe myweli-api-staging"*"labels.commit"*)
    [ -n "$STUB_COMMIT" ] && { echo "$STUB_COMMIT"; exit 0; }; exit 1 ;;
  *"artifacts docker images describe"*)
    [ -n "$STUB_DIGEST" ] && { echo "$STUB_DIGEST"; exit 0; }; exit 1 ;;
  *"artifacts docker tags list"*) exit 0 ;;
  *"artifacts docker images list"*) echo NEWEST-IMAGES; exit 0 ;;
esac
exit 1
''');
        final r = Process.runSync(
          'bash',
          ['-c', run(step('Production must promote'))],
          workingDirectory: g.dir.path,
          includeParentEnvironment: false,
          environment: {
            ...sealedEnv(g.dir, stubBin: g.bin),
            'REGISTRY': 'europe-west9-docker.pkg.dev',
            'PROJECT_ID': 'myweli',
            'REGION': 'europe-west9',
            'STUB_IMAGE': ?stagingImage,
            'STUB_COMMIT': ?commit,
            'STUB_DIGEST': ?digest,
          },
        );
        return (code: r.exitCode, out: '${r.stdout}${r.stderr}');
      }

      test('staging gone: the newest images', () {
        final r = hint();
        expect(r.code, 1, reason: 'the step is a refusal: ${r.out}');
        expect(r.out, contains('could not read myweli-api-staging'));
        expect(r.out, contains('NEWEST-IMAGES'), reason: r.out);
      });

      test('staging mid-recreate on the placeholder: the newest images', () {
        final r = hint(
          stagingImage: 'gcr.io/cloudrun/hello',
          commit: 'bootstrap',
        );
        expect(r.code, 1, reason: r.out);
        expect(r.out, contains('Could not derive a tag'));
        expect(
          r.out,
          contains('NEWEST-IMAGES'),
          reason:
              'staging answered but yielded no tag, and the refusal handed '
              'over nothing:\n${r.out}',
        );
      });

      test('staging verified: its tag, and no list to choose from', () {
        final r = hint(
          stagingImage: '$image@sha256:abc',
          commit: '12d3455',
          digest: 'sha256:abc',
        );
        expect(r.code, 1, reason: r.out);
        expect(r.out, contains('image_tag=12d3455'));
        expect(
          r.out,
          isNot(contains('NEWEST-IMAGES')),
          reason: 'a rehearsed tag exists — do not offer unrehearsed ones',
        );
      });

      test('the list is the real registry command', () {
        final text = run(step('Production must promote'));
        expect(
          text,
          contains('gcloud artifacts docker images list "\${IMAGE}"'),
        );
        expect(text, contains('--sort-by=~UPDATE_TIME'));
        expect(text, contains('staging.state'));
      });
    });
  });

  group('the resolver, executed from its own run: text', () {
    test('staging + absent: skip, and say so', () {
      final r = resolve('staging', 'absent\n');
      expect(r.code, 0, reason: r.out);
      expect(r.env['DEPLOY'], 'skip');
      expect(r.env['SERVICE'], 'myweli-api-staging');
      expect(r.out, contains('staging is ABSENT'));
    });

    test('the value it writes is the value every reader compares to', () {
      // Writer and readers are separate lines in separate steps; a rename on
      // one side alone turns the skip off without a single red step. So the
      // comparand is read out of each `if:` and held to what the resolver
      // ACTUALLY wrote, not to a literal both could drift away from together.
      final value = resolve('staging', 'absent\n').env['DEPLOY'];
      expect(value, isNotNull);
      for (final name in [
        'Deploy the service',
        'Verify the revision actually serves',
      ]) {
        expect(step(name)['if'], "env.DEPLOY != '$value'", reason: name);
      }
      expect(step('Staging is absent')['if'], "env.DEPLOY == '$value'");
    });

    test('staging + present: deploy as before', () {
      final r = resolve('staging', 'present\n');
      expect(r.code, 0, reason: r.out);
      expect(r.env.containsKey('DEPLOY'), isFalse, reason: '${r.env}');
      expect(r.env['SERVICE'], 'myweli-api-staging');
    });

    for (final bad in <String?>['garbage\n', 'Absent\n', '', null]) {
      test('staging + ${bad == null ? 'no file' : jsonEncode(bad)}: FAILS', () {
        final r = resolve('staging', bad);
        expect(
          r.code,
          isNot(0),
          reason:
              'an unreadable switch was treated as an answer — a typo would '
              'silently turn staging deploys off, or on against nothing',
        );
        expect(r.env.containsKey('DEPLOY'), isFalse, reason: '${r.env}');
      });
    }

    for (final state in <String?>['garbage\n', 'absent\n', null]) {
      test('production + ${state == null ? 'no file' : jsonEncode(state)}: '
          'the resolver is unaffected', () {
        final r = resolve('production', state);
        expect(
          r.code,
          0,
          reason:
              "the staging switch reached the resolver's production branch: "
              '${r.out}. It must never be what skips or fails a production '
              'deploy there (98 and 95 do read it, and fail closed)',
        );
        expect(r.env['SERVICE'], 'myweli-api');
        expect(r.env.containsKey('DEPLOY'), isFalse, reason: '${r.env}');
      });
    }
  });

  group('the rollback-pin guard, executed from its own run: text', () {
    // It runs before the build and fails closed on a pinned service. While
    // staging is absent the service may still exist (until it is deleted, or
    // mid-recreate) — and a run that deploys nothing cannot lift a pin, so
    // failing there would only stop the build production promotes from.
    ({int code, String out, List<String> calls}) guard({String? deploy}) {
      final g = stubGcloud('guard_', r'''#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$*" in
  "run services describe"*) echo myweli-api-staging-00064-old; exit 0 ;;
esac
exit 1
''');
      final log = File('${g.dir.path}/calls.log')..writeAsStringSync('');
      final r = Process.runSync(
        'bash',
        ['-c', run(step('a rollback pin must not be lifted'))],
        workingDirectory: g.dir.path,
        includeParentEnvironment: false,
        environment: {
          ...sealedEnv(g.dir, stubBin: g.bin),
          'STUB_LOG': log.path,
          'SERVICE': 'myweli-api-staging',
          'REGION': 'europe-west9',
          'UNPIN': '',
          'DEPLOY': ?deploy,
        },
      );
      return (
        code: r.exitCode,
        out: '${r.stdout}${r.stderr}',
        calls: log.readAsLinesSync(),
      );
    }

    test('staging absent + a pinned service: passes, and asks nothing', () {
      // DEPLOY as the resolver really writes it, not as a literal here.
      final value = resolve('staging', 'absent\n').env['DEPLOY'];
      expect(value, isNotNull);
      final r = guard(deploy: value);
      expect(
        r.code,
        0,
        reason:
            'a run that deploys nothing failed on a pin it cannot lift — the '
            'build after it never ran:\n${r.out}',
      );
      expect(r.out, contains('staging absent'));
      expect(r.calls, isEmpty, reason: 'it asked Cloud Run anyway');
    });

    test('staging present + a pinned service: still FAILS closed', () {
      // The control for the case above: the same stub, without the skip,
      // must still stop the deploy — so the pass above is the skip's doing.
      final r = guard();
      expect(r.code, 1, reason: r.out);
      expect(r.out, contains('PINNED'));
      expect(r.calls, isNotEmpty);
    });
  });

  group('98-verify-secret-pins.sh, on its rehearsal fixture', () {
    // A fixture that knows ONLY production's pins, each enabled and newest.
    // `present` must then fail on the STAGING_* pins it cannot find, `absent`
    // must pass — and must still be checking production, which the last case
    // proves by removing one production pin from the fixture.
    final prodYaml = read('infra/gcp/service.yaml');
    final prodPins = {
      for (final m in RegExp(
        r"secretKeyRef: \{ name: ([A-Z0-9_]+), key: '([0-9]+)' \}",
      ).allMatches(prodYaml))
        m.group(1)!: m.group(2)!,
    };

    String fixture(Map<String, String> pins) => jsonEncode({
      for (final e in pins.entries)
        e.key: {'state': 'ENABLED', 'newest': e.value},
    });

    ({int code, String out}) pins98(String? state, Map<String, String> pins) {
      final dir = scratch('pins98_');
      for (final f in [
        '98-verify-secret-pins.sh',
        'service.yaml',
        'service-staging.yaml',
      ]) {
        File('$root/infra/gcp/$f').copySync('${dir.path}/$f');
      }
      if (state != null) {
        File('${dir.path}/staging.state').writeAsStringSync(state);
      }
      final r = Process.runSync(
        'bash',
        ['${dir.path}/98-verify-secret-pins.sh'],
        workingDirectory: dir.path,
        includeParentEnvironment: false,
        environment: {
          ...sealedEnv(dir),
          'PROJECT': 'myweli',
          'SECRET_PINS_FIXTURE_JSON': fixture(pins),
        },
      );
      return (code: r.exitCode, out: '${r.stdout}${r.stderr}');
    }

    test('the fixture is production-only and large enough to mean it', () {
      expect(prodPins.length, greaterThanOrEqualTo(12));
      expect(prodPins.keys.where((k) => k.startsWith('STAGING_')), isEmpty);
    });

    test('absent: production\'s pins alone, all green', () {
      final r = pins98('absent\n', prodPins);
      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('staging is ABSENT'));
      expect(r.out, contains('${prodPins.length} pinned mounts'));
      expect(r.out, isNot(contains('STAGING_')));
      expect(r.out, contains('Every pinned secret version is enabled'));
    });

    test('present: the staging manifest is checked, and its pins are '
        'missing', () {
      final r = pins98('present\n', prodPins);
      expect(
        r.code,
        1,
        reason:
            '`present` stopped reading service-staging.yaml — a live staging '
            'would go unchecked:\n${r.out}',
      );
      expect(r.out, contains('STAGING_'));
      expect(r.out, contains('NOT_FOUND'));
    });

    test('absent never means "check nothing"', () {
      final missingOne = Map.of(prodPins)..remove(prodPins.keys.first);
      final r = pins98('absent\n', missingOne);
      expect(
        r.code,
        1,
        reason: '`absent` let a broken PRODUCTION pin through:\n${r.out}',
      );
      expect(r.out, contains(prodPins.keys.first));
    });

    for (final bad in <String?>['garbage\n', 'present absent\n', null]) {
      test('${bad == null ? 'no state file' : jsonEncode(bad)}: FAILS', () {
        final r = pins98(bad, prodPins);
        expect(r.code, 1, reason: r.out);
        expect(r.out, contains("expected 'present' or 'absent'"));
      });
    }
  });

  group('95-emitter-lag.sh, against a throwaway repo and a stub gcloud', () {
    // 95 refuses a shallow clone (it greps old commits), and CI's checkout is
    // shallow — so it runs here in a fresh repository holding this tree's
    // infra/gcp and backend/lib as one commit. Production is pinned to that
    // commit with 95's own PIN_ override; the stub answers exactly one
    // question — "does myweli-api-staging still exist?" — and fails
    // everything else, so an unpinned service reads as not found.
    const closing95 =
        'myweli-api-staging is ABSENT (infra/gcp/staging.state) and was not '
        'checked.';
    late Directory repo;
    late String head;
    late String stubBin;

    setUpAll(() {
      repo = Directory.systemTemp.createTempSync('emitter95_');
      for (final sub in ['infra/gcp', 'backend/lib']) {
        final from = Directory('$root/$sub');
        for (final f in from.listSync(recursive: true).whereType<File>()) {
          final rel = f.path.substring(from.path.length);
          File('${repo.path}/$sub$rel').createSync(recursive: true);
          f.copySync('${repo.path}/$sub$rel');
        }
      }
      ProcessResult git(List<String> args) {
        final r = Process.runSync('git', [
          '-c',
          'user.name=fixture',
          '-c',
          'user.email=fixture@example.invalid',
          '-c',
          'commit.gpgsign=false',
          ...args,
        ], workingDirectory: repo.path);
        expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
        return r;
      }

      git(['init', '-q']);
      git(['add', '-A']);
      git(['commit', '-q', '-m', 'fixture']);
      head = (git(['rev-parse', 'HEAD']).stdout as String).trim();

      stubBin = '${repo.path}/stub-bin';
      final stub = File('$stubBin/gcloud')
        ..createSync(recursive: true)
        ..writeAsStringSync(r'''#!/bin/sh
case "$*" in
  *"describe myweli-api-staging"*"metadata.name"*)
    if [ "${STUB_STAGING_EXISTS:-}" = 1 ]; then echo myweli-api-staging; exit 0; fi ;;
esac
exit 1
''');
      expect(Process.runSync('chmod', ['+x', stub.path]).exitCode, 0);
    });

    tearDownAll(() => repo.deleteSync(recursive: true));

    ({int code, String out}) lag95(
      String state, {
      bool pinProduction = true,
      bool stagingExists = false,
    }) {
      File('${repo.path}/infra/gcp/staging.state').writeAsStringSync(state);
      final home = scratch('emitter95_home_');
      final r = Process.runSync(
        'bash',
        ['infra/gcp/95-emitter-lag.sh'],
        workingDirectory: repo.path,
        includeParentEnvironment: false,
        environment: {
          ...sealedEnv(home, stubBin: stubBin),
          'PROJECT': 'myweli',
          'REGION': 'europe-west9',
          if (pinProduction) 'PIN_myweli_api': head,
          if (stagingExists) 'STUB_STAGING_EXISTS': '1',
        },
      );
      return (code: r.exitCode, out: '${r.stdout}${r.stderr}');
    }

    test('absent: staging is reported ABSENT and production is checked', () {
      final r = lag95('absent\n');
      expect(r.code, 0, reason: r.out);
      expect(
        RegExp(r'myweli-api-staging\s+ABSENT').hasMatch(r.out),
        isTrue,
        reason: r.out,
      );
      expect(r.out, contains('myweli-api=ok'));
      expect(r.out, contains('myweli-api-staging=ABSENT'));
      expect(r.out, contains(closing95));
      expect(r.out, isNot(contains('::warning::')));
    });

    test('the deletion gate quotes that line exactly as it prints', () {
      // §9.2 step 0 tells the owner to find this line in the merge run before
      // deleting anything. 95's table pads its columns, so a paraphrase such
      // as "myweli-api-staging ABSENT" is a search that never matches.
      expect(read('docs/design/infra-staging.md'), contains(closing95));
    });

    test('absent, but the service still exists: a warning, not a failure', () {
      final r = lag95('absent\n', stagingExists: true);
      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('::warning::'));
      expect(r.out, contains('still exists'));
      // Both windows, because the advice is opposite: mid-recreate the
      // service is the recreate itself and must NOT be deleted.
      expect(r.out, contains('Mid-recreate'));
      expect(r.out, contains('§9.3'));
      expect(r.out, contains('§9.2'));
    });

    test('absent does not excuse PRODUCTION: not found stays fatal', () {
      final r = lag95('absent\n', pinProduction: false);
      expect(
        r.code,
        1,
        reason:
            '`absent` swallowed a production service that cannot be found:\n'
            '${r.out}',
      );
      expect(r.out, contains('myweli-api=UNRESOLVED'));
    });

    test('present: a staging that cannot be found still fails', () {
      final r = lag95('present\n');
      expect(r.code, 1, reason: r.out);
      expect(r.out, contains('myweli-api-staging=UNRESOLVED'));
    });

    test('anything else: FAILS before checking', () {
      final r = lag95('gone\n');
      expect(r.code, 1, reason: r.out);
      expect(r.out, contains("expected 'present' or 'absent'"));
    });
  });

  group('the recreate path — 90-staging.sh', () {
    final script = read('infra/gcp/90-staging.sh');

    test('it creates the instance WITH point-in-time recovery, at one day', () {
      // PITR was patched onto the first instance by hand (2026-08-17) and the
      // script kept creating without it, so a recreate would have quietly
      // dropped the property the restore rehearsal depends on.
      expect(script, contains('--enable-point-in-time-recovery'));
      expect(script, contains('--retained-transaction-log-days=1'));
      expect(script, isNot(contains('--no-enable-point-in-time-recovery')));
    });

    test('its closing words are the flip', () {
      final closing = script.split('cat <<EOF').last.trim().split('\n');
      expect(closing.last, 'EOF');
      expect(
        closing[closing.length - 2],
        'Now flip infra/gcp/staging.state to present.',
      );
    });

    /// Runs the real 90 against a stub gcloud that says every resource
    /// exists and lists [users] on the instance, logging every call.
    ({int code, String out, List<String> calls}) recreate90(String users) {
      final dir = scratch('recreate90_');
      final log = File('${dir.path}/calls.log')..writeAsStringSync('');
      final stub = File('${dir.path}/stub-bin/gcloud')
        ..createSync(recursive: true)
        ..writeAsStringSync(r'''#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$*" in
  "sql users list"*) [ -n "$STUB_SQL_USERS" ] && printf '%s\n' "$STUB_SQL_USERS" ;;
esac
exit 0
''');
      expect(Process.runSync('chmod', ['+x', stub.path]).exitCode, 0);
      final r = Process.runSync(
        'bash',
        ['$root/infra/gcp/90-staging.sh'],
        workingDirectory: dir.path,
        includeParentEnvironment: false,
        environment: {
          ...sealedEnv(dir, stubBin: '${dir.path}/stub-bin'),
          'STUB_LOG': log.path,
          'STUB_SQL_USERS': users,
        },
      );
      return (
        code: r.exitCode,
        out: '${r.stdout}${r.stderr}',
        calls: log.readAsLinesSync(),
      );
    }

    test('a STAGING_DATABASE_URL that outlived its instance stops the run', () {
      final r = recreate90('postgres');
      expect(
        r.code,
        1,
        reason:
            'the surviving secret was trusted — staging would boot with a '
            'password for a user the new instance does not have:\n${r.out}',
      );
      expect(r.out, contains('has no myweli_app user'));
      expect(
        r.calls.where(
          (c) => c.contains(' create') || c.contains('add-iam-policy-binding'),
        ),
        isEmpty,
        reason: 'it stopped, but only after changing something',
      );
    });

    test('and the ordinary re-run, where the user exists, is not refused', () {
      final r = recreate90('postgres\nmyweli_app');
      expect(
        r.out,
        contains('user + STAGING_DATABASE_URL already provisioned'),
      );
      expect(r.out, isNot(contains('has no myweli_app user')));
      // It then stops at the owner-supplied values, which this run does not
      // export — the next line of defence, and proof the guard let it past.
      expect(r.out, contains('==> 4/7'));
    });
  });
}
