import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Play's device filter cannot quietly come back.
///
/// ## Why this file exists
///
/// Both Android apps lock `MainActivity` to portrait
/// (docs/design/pro-app-batch7.md §2.9). From that lock alone, Play infers a
/// REQUIRED `android.hardware.screen.portrait` and hides the app from every
/// device that does not report the feature: 27 devices at build 785, and the
/// closed track's check of 2026-11-19 named phones, tablets, desktop and
/// Android XR. The manifest declares the feature optional
/// (docs/design/android-play-release.md §11, 2026-11-19).
///
/// `mobile/test/infra/android_orientation_test.dart` pins the SOURCE
/// manifest. Play reads the MERGED one in the built APK, so CI's `apk-size`
/// job reads that with `tool/verify_android_portrait_optional.sh`. This file:
///
/// 1. runs the script's verdicts on saved badgings, so its refusal paths run
///    on every PR and not only on the day the APK goes wrong. The badging
///    lines are copied from two real release APKs of 2026-11-19, built before
///    and after the declaration;
/// 2. pins CI's step: after the build, on the APK, and impossible to skip.

const _script = 'verify_android_portrait_optional.sh';
const _apk = 'build/app/outputs/flutter-apk/app-consumer-release.apk';

/// The lines below are copied from `aapt2 dump badging` (build-tools 36.0.0)
/// of two release APKs of the Pro app, built on 2026-11-19 on `d7e40407`:
/// before the manifest declared the feature, and after. aapt2 prints the
/// features inside a `feature-group`, indented by two spaces.
const _package =
    "package: name='com.myweli.pro' versionCode='1' versionName='0.0.2' "
    "platformBuildVersionName='16' platformBuildVersionCode='36' "
    "compileSdkVersion='36' compileSdkVersionCodename='16'";
const _group = "feature-group: label=''";

/// Before: what the lock alone made aapt2 print — the defect itself.
const _before = [
  "  uses-feature: name='android.hardware.screen.portrait'",
  "  uses-implied-feature: name='android.hardware.screen.portrait' "
      "reason='one or more activities have specified a portrait orientation'",
];

/// After: the one line the script accepts.
const _optional =
    "  uses-feature-not-required: name='android.hardware.screen.portrait'";

/// Neighbours in the same group that must not count (both APKs carry them).
const _neighbours = [
  "  uses-feature: name='android.hardware.faketouch'",
  "  uses-implied-feature: name='android.hardware.faketouch' "
      "reason='default feature for all apps'",
  "  uses-feature: name='android.hardware.location'",
];

/// A manifest (or a plugin's) that declares the feature without
/// `required="false"`: aapt2's line for it, without the implied one.
const _required = "  uses-feature: name='android.hardware.screen.portrait'";

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
    final dir = await Directory.systemTemp.createTemp('portrait-badging');
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
    test('accepts the feature declared optional (the after APK)', () async {
      final r = await verdict([_package, _group, _optional, ..._neighbours]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('refuses the requirement the lock implies (the before APK, the '
        'defect itself)', () async {
      final r = await verdict([_package, _group, ..._before, ..._neighbours]);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    });

    test('refuses the feature declared required', () async {
      final r = await verdict([_package, _group, _required, ..._neighbours]);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    });

    test('refuses optional AND required together', () async {
      final r = await verdict([_package, _group, _optional, _required]);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    });

    test('refuses no line at all: the declaration is gone', () async {
      final r = await verdict([_package, _group, ..._neighbours]);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
    });

    test(
      'an empty or foreign read is no verdict (exit 2), not a pass',
      () async {
        for (final lines in [
          <String>[],
          [_group, _optional],
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

    test('the script runs on the release APK, after the build', () {
      expect(job, isNotNull, reason: 'ci.yml lost its apk-size job');
      expect(job!.containsKey('if'), isFalse);
      expect(job.containsKey('continue-on-error'), isFalse);

      final build = index(
        'builds the release APK',
        (r) => r.contains('flutter build apk') && r.contains('--release'),
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
