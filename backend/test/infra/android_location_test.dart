import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The client app's precise location cannot quietly come back.
///
/// ## Why this file exists
///
/// MyWeli (the client) centres a map and picks the nearest commune, which
/// approximate location does. Without `ACCESS_FINE_LOCATION`, the client app
/// needs no precise-location declaration on Play (due 2027-01-27); precise
/// location is MyWeli Pro's alone, from `src/pro/AndroidManifest.xml`
/// (A6, decision 272, docs/design/consumer-location.md §1, §8.3).
///
/// `mobile/test/infra/android_location_permission_test.dart` pins the SOURCE
/// manifests. Play reads the MERGED one in the built APK, which a plugin's
/// manifest could change, so CI's `apk-size` job reads that with
/// `tool/verify_android_location.sh`. This file:
///
/// 1. runs the script's verdicts on saved badgings, so its refusal paths run
///    on every PR and not only on the day the APK goes wrong;
/// 2. pins CI's step: after the build, on the APK, and impossible to skip.

const _script = 'verify_android_location.sh';
const _apk = 'build/app/outputs/flutter-apk/app-consumer-release.apk';

/// Copied from `aapt2 dump badging` (aapt2 2.20, build-tools 36.0.0) of two
/// release APKs of the client app (arm64), built on 2026-11-27: on `main`
/// `3a2cb1d7` before A6, and with A6's manifests after.
const _package =
    "package: name='com.myweli.app' versionCode='1' versionName='0.0.2' "
    "platformBuildVersionName='16' platformBuildVersionCode='36' "
    "compileSdkVersion='36' compileSdkVersionCodename='16'";

/// Neighbours both APKs carry: they must not count.
const _neighbours = [
  "uses-permission: name='android.permission.INTERNET'",
  "uses-permission: name='android.permission.POST_NOTIFICATIONS'",
  "  uses-feature: name='android.hardware.location'",
];

const _coarse =
    "uses-permission: name='android.permission.ACCESS_COARSE_LOCATION'";

/// Before A6: the defect itself.
const _before = [
  "uses-permission: name='android.permission.ACCESS_FINE_LOCATION'",
  _coarse,
  "  uses-implied-feature: name='android.hardware.location' "
      "reason='requested android.permission.ACCESS_COARSE_LOCATION "
      "permission, and requested android.permission.ACCESS_FINE_LOCATION "
      "permission'",
];

/// After A6: what the script accepts.
const _after = [
  _coarse,
  "  uses-implied-feature: name='android.hardware.location' "
      "reason='requested android.permission.ACCESS_COARSE_LOCATION "
      "permission'",
];

/// The other forms a plugin's manifest could bring precise location back
/// in, written in aapt2's printed shape (not copied from a real APK): the
/// script refuses any line naming the permission, whatever its prefix.
const _otherForms = [
  "uses-permission-sdk-23: name='android.permission.ACCESS_FINE_LOCATION'",
  "uses-permission: name='android.permission.ACCESS_FINE_LOCATION' "
      "maxSdkVersion='30'",
];

/// A shell script without its comments or progress lines: a flag quoted in
/// an `echo` describing the command is not the command
/// (myweli-verification-guardrails §2, learned on release_build.sh).
String _code(String shell) => shell
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      return t.startsWith('#') || t.startsWith('echo ') ? '' : l;
    })
    .join('\n');

void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  Future<ProcessResult> verdict(List<String> lines) async {
    final dir = await Directory.systemTemp.createTemp('location-badging');
    try {
      final file = File('${dir.path}/badging.txt')
        ..writeAsStringSync('${lines.join('\n')}\n');
      return await Process.run('bash', [
        '$root/tool/$_script',
        '--badging',
        file.path,
      ]);
    } finally {
      dir.deleteSync(recursive: true);
    }
  }

  group('the script judges the badging', () {
    test('accepts approximate location only (the after APK)', () async {
      final r = await verdict([_package, ..._after, ..._neighbours]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test(
      'refuses precise location (the before APK, the defect itself)',
      () async {
        final r = await verdict([_package, ..._before, ..._neighbours]);
        expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      },
    );

    for (final form in _otherForms) {
      test('refuses precise location in another form: $form', () async {
        final r = await verdict([_package, _coarse, form, ..._neighbours]);
        expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      });
    }

    test('refuses no location at all: the map and « Près de moi » are '
        'gone', () async {
      final r = await verdict([_package, ..._neighbours]);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    });

    test('refuses approximate named only in a reason, not declared', () async {
      final r = await verdict([_package, _after.last, ..._neighbours]);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    });

    test(
      'an empty or foreign read is no verdict (exit 2), not a pass',
      () async {
        for (final lines in [
          <String>[],
          [..._after],
        ]) {
          final r = await verdict(lines);
          expect(r.exitCode, 2, reason: '$lines: ${r.stdout}${r.stderr}');
        }
      },
    );
  });

  group('CI reads the built APK, after the build, and cannot skip it', () {
    final ci =
        loadYaml(File('$root/.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final job = (ci['jobs'] as YamlMap)['apk-size'] as YamlMap?;
    final List<Object?> steps = job == null
        ? const []
        : (job['steps'] as YamlList).toList();
    String run(Object? step) => _code('${(step as YamlMap)['run'] ?? ''}');

    int index(String what, bool Function(String run) matches) {
      final found = [
        for (var i = 0; i < steps.length; i++)
          if (matches(run(steps[i]))) i,
      ];
      expect(found, hasLength(1), reason: 'apk-size: exactly one step $what');
      return found.single;
    }

    test('the script runs on the CLIENT release APK, after the build', () {
      expect(job, isNotNull, reason: 'ci.yml lost its apk-size job');
      expect(job!.containsKey('if'), isFalse);
      expect(job.containsKey('continue-on-error'), isFalse);

      final build = index(
        'builds the client release APK',
        (r) =>
            r.contains('flutter build apk') &&
            r.contains('--release') &&
            r.contains('--flavor consumer'),
      );
      final check = index(
        'runs $_script on the APK',
        (r) => r.contains('../tool/$_script $_apk'),
      );
      expect(
        check,
        greaterThan(build),
        reason: 'before the build it reads nothing — or a stale file',
      );

      final step = steps[check] as YamlMap;
      expect(step.containsKey('if'), isFalse, reason: '${step['name']}');
      expect(
        step.containsKey('continue-on-error'),
        isFalse,
        reason: '${step['name']}',
      );
      expect(
        run(step),
        isNot(contains('|| true')),
        reason: '${step['name']}: a refusal must fail the job',
      );
    });
  });
}
