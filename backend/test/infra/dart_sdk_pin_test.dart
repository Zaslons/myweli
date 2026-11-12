import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Design: docs/design/backend-dart-sdk-pin.md
///
/// **The Dart SDK that builds the server is the TLS verifier production runs.**
/// Every outbound HTTPS call the backend makes — Apple and Google sign-in,
/// FCM, R2, Resend, Sentry, the web rebuild hook — goes through `dart:io`,
/// whose chain verification is the BoringSSL compiled into the binary. Dart
/// < 3.13.7 trusts eight compromised eMudhra intermediates
/// (GHSA-frr6-h895-5pxp, 2026-10-23); 3.13.7 blocks them by SPKI hash.
///
/// Until this test, `backend/Dockerfile` built `FROM dart:stable`, and
/// production happened to be patched only because `stable` had moved to 3.13.7
/// before the image was built (read from the serving binary, 2026-11-10). The
/// Dockerfile's own comment advised pinning `dart:3.10` — advice that, taken
/// today, ships the vulnerable verifier. Meanwhile CI compiled and tested with
/// 3.10.7, so no test ever ran on the compiler that shipped.
///
/// Four rules, each a defect when broken and none red on a legitimate bump:
///   1. the build stage names an exact `X.Y.Z` AND a digest — never a channel;
///   2. that version is at or above the floor, which lives in ONE place
///      (`FLOOR=` in .github/scripts/verify-image-dart-sdk.sh) and may never
///      drop below this advisory's 3.13.7;
///   3. every backend CI job sets up exactly that version, and builds with the
///      same `dart_frog_cli`;
///   4. the deploy reads the SDK out of the BUILT image before it deploys —
///      because rules 1–2 read the tag, and Docker builds the digest: a 3.13.6
///      digest under a 3.13.7 tag passes them. That script is what sees it.
/// Bumping the Dockerfile and ci.yml together stays green. Bumping one alone —
/// which is what a Dependabot docker PR does — goes red until the other
/// follows, and the message says so.
void main() {
  // `dart test` runs from backend/ in CI (defaults.run.working-directory).
  final dockerfile = File('Dockerfile');
  final ci = File('../.github/workflows/ci.yml');
  final deploy = File('../.github/workflows/deploy-backend.yml');
  final checker = File('../.github/scripts/verify-image-dart-sdk.sh');

  /// The first SDK that blocks the eMudhra intermediates. The working floor is
  /// `FLOOR=` in [checker], which may rise past this but never fall below it.
  const advisoryMinimum = [3, 13, 7];
  const advisory = 'GHSA-frr6-h895-5pxp';

  test('the files are where this test thinks they are', () {
    for (final f in [dockerfile, ci, deploy, checker]) {
      expect(f.existsSync(), isTrue, reason: f.absolute.path);
    }
  });

  int compare(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  List<int> parts(String v) => v.split('.').map(int.parse).toList();

  /// `FLOOR="X.Y.Z"` in the checker, read from a line that is not a comment.
  String scriptFloor() {
    final floors = [
      for (final line in checker.readAsLinesSync())
        if (!line.trimLeft().startsWith('#'))
          RegExp(r'^FLOOR="(\d+\.\d+\.\d+)"$').firstMatch(line.trim())?[1],
    ].whereType<String>().toList();
    expect(
      floors,
      hasLength(1),
      reason: 'one FLOOR="X.Y.Z" in ${checker.path}',
    );
    return floors.single;
  }

  /// The Dockerfile's instructions, comments removed and `\` continuations
  /// joined. Docker treats only a line whose first non-blank character is `#`
  /// as a comment — so a pin written in a comment is not a pin, and this sees
  /// only what Docker executes.
  List<String> instructions() {
    final out = <String>[];
    var current = StringBuffer();
    for (final raw in dockerfile.readAsLinesSync()) {
      final line = raw.trimRight();
      if (line.trimLeft().startsWith('#')) continue;
      if (line.trim().isEmpty && current.isEmpty) continue;
      if (line.endsWith(r'\')) {
        current.write('${line.substring(0, line.length - 1)} ');
        continue;
      }
      current.write(line);
      final joined = current.toString().trim();
      if (joined.isNotEmpty) out.add(joined.replaceAll(RegExp(r'\s+'), ' '));
      current = StringBuffer();
    }
    return out;
  }

  /// `FROM <image> [AS <name>]` → the image reference of every stage that
  /// builds on the official Dart image.
  List<String> dartBaseImages() =>
      [
            for (final i in instructions())
              if (RegExp(r'^FROM\s', caseSensitive: false).hasMatch(i))
                i.split(' ')[1],
          ]
          .where(
            (ref) => RegExp(r'^(docker\.io/library/)?dart[:@]').hasMatch(ref),
          )
          .toList();

  final pinShape = RegExp(
    r'^(?:docker\.io/library/)?dart:(\d+)\.(\d+)\.(\d+)@sha256:[0-9a-f]{64}$',
  );

  /// The pinned version, as written after `dart:`.
  String pinnedVersion() {
    final m = pinShape.firstMatch(dartBaseImages().single)!;
    return '${m[1]}.${m[2]}.${m[3]}';
  }

  group('backend/Dockerfile pins the SDK', () {
    test('exactly one stage builds on the Dart image', () {
      expect(
        dartBaseImages(),
        hasLength(1),
        reason: 'expected one `FROM dart:…` build stage',
      );
    });

    test('by exact version AND digest — never a channel or a minor', () {
      final ref = dartBaseImages().single;
      expect(
        pinShape.hasMatch(ref),
        isTrue,
        reason:
            '`FROM $ref` floats. Pin `dart:X.Y.Z@sha256:<index digest>`: a '
            'channel (`stable`) or a minor (`3.13`) makes the TLS verifier '
            'production runs a function of the day the image was built '
            '($advisory). docs/design/backend-dart-sdk-pin.md §4.',
      );
    });

    test('the floor itself never drops below this advisory', () {
      expect(
        compare(parts(scriptFloor()), advisoryMinimum),
        greaterThanOrEqualTo(0),
        reason:
            'FLOOR=${scriptFloor()} in ${checker.path} is below '
            '${advisoryMinimum.join('.')}, the first SDK that blocks the '
            'compromised eMudhra intermediates ($advisory).',
      );
    });

    test('at or above the floor', () {
      expect(
        compare(parts(pinnedVersion()), parts(scriptFloor())),
        greaterThanOrEqualTo(0),
        reason:
            'Dart ${pinnedVersion()} is below the floor ${scriptFloor()} '
            '($advisory): its TLS verifier trusts the compromised eMudhra '
            'intermediates.',
      );
    });
  });

  group('the deploy reads the SDK out of the built image', () {
    final steps =
        (((loadYaml(deploy.readAsStringSync()) as YamlMap)['jobs']
                    as YamlMap)['deploy']
                as YamlMap)['steps']
            as YamlList;

    String runOf(Object? step) => (((step as YamlMap)['run'] as String?) ?? '')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n');

    int indexWhere(bool Function(YamlMap) test, String what) {
      final hits = [
        for (var i = 0; i < steps.length; i++)
          if (test(steps[i] as YamlMap)) i,
      ];
      expect(hits, hasLength(1), reason: 'exactly one step that $what');
      return hits.single;
    }

    test('between the build and the deploy, on every path', () {
      final build = indexWhere((s) => s['id'] == 'build', 'has id: build');
      final check = indexWhere(
        (s) =>
            runOf(s).contains('bash .github/scripts/verify-image-dart-sdk.sh'),
        'runs verify-image-dart-sdk.sh',
      );
      final replace = indexWhere(
        (s) => runOf(s).contains('gcloud run services replace'),
        'replaces the service',
      );
      expect(build, lessThan(check), reason: 'it reads what the build made');
      expect(
        check,
        lessThan(replace),
        reason: 'a check after the deploy reports what is already serving',
      );
      final step = steps[check] as YamlMap;
      expect(
        step.containsKey('if'),
        isFalse,
        reason:
            'no `if:` — a promotion (image_tag) builds nothing, and this is '
            'its only SDK check',
      );
      expect(
        (step['env'] as YamlMap?)?['IMAGE_REF'],
        r'${{ steps.build.outputs.image }}',
        reason: 'it must read the digest the deploy will use',
      );
    });
  });

  group('CI tests with the SDK that ships', () {
    final jobs =
        (loadYaml(ci.readAsStringSync()) as YamlMap)['jobs'] as YamlMap;

    /// The jobs that work in backend/ — found by what they do, so renaming one
    /// cannot exempt it.
    Map<String, YamlMap> backendJobs() => {
      for (final e in jobs.entries)
        if ((((e.value as YamlMap)['defaults'] as YamlMap?)?['run']
                as YamlMap?)?['working-directory'] ==
            'backend')
          e.key as String: e.value as YamlMap,
    };

    /// `sdk:` of every `dart-lang/setup-dart` step in [job].
    List<String> setupDartSdks(YamlMap job) => [
      for (final s in (job['steps'] as YamlList? ?? YamlList()))
        if (((s as YamlMap)['uses'] as String?)?.startsWith(
              'dart-lang/setup-dart@',
            ) ??
            false)
          (s['with'] as YamlMap?)?['sdk'].toString() ?? '<no sdk:>',
    ];

    test('both backend jobs exist (the comparison below is not vacuous)', () {
      expect(
        backendJobs().keys,
        containsAll(<String>['backend', 'backend-boot-smoke']),
      );
    });

    test('every backend job sets up exactly the Dockerfile SDK', () {
      final want = pinnedVersion();
      for (final e in backendJobs().entries) {
        expect(
          setupDartSdks(e.value),
          equals([want]),
          reason:
              'job `${e.key}` must set up Dart $want — the version '
              'backend/Dockerfile ships. Tests on another compiler do not test '
              'the artifact (and a Dependabot bump of the Dockerfile alone '
              'lands here: bump ci.yml in the same PR).',
        );
      }
    });

    test('and builds with the same dart_frog_cli as the image', () {
      final activate = RegExp(r'dart pub global activate dart_frog_cli (\S+)');
      final inImage = [
        for (final i in instructions())
          if (activate.hasMatch(i)) activate.firstMatch(i)![1]!,
      ];
      expect(
        inImage,
        hasLength(1),
        reason:
            'backend/Dockerfile must activate dart_frog_cli with an explicit '
            'version — without one, the image builds with whatever pub.dev '
            'serves that day',
      );
      final inCi = <String>[];
      for (final job in backendJobs().values) {
        for (final s in (job['steps'] as YamlList? ?? YamlList())) {
          final run = (s as YamlMap)['run'];
          if (run is! String) continue;
          for (final line in run.split('\n')) {
            if (line.trimLeft().startsWith('#')) continue;
            final m = activate.firstMatch(line);
            if (m != null) inCi.add(m[1]!);
          }
        }
      }
      expect(inCi, isNotEmpty, reason: 'no CI job activates dart_frog_cli');
      expect(inCi.toSet(), equals({inImage.single}));
    });
  });
}
