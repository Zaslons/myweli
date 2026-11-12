import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The Android TLS gate (GHSA-frr6-h895-5pxp) cannot quietly fall away.
///
/// ## Why this file exists
///
/// On Android, `dart:io` verifies TLS with the BoringSSL compiled into
/// `libflutter.so`. Below Flutter 3.47.8 (Dart 3.13.7) it trusts eight
/// eMudhra intermediate CAs whose private keys can be derived, so every API
/// call the app makes — tokens, sign-in codes, KYC uploads — accepts a forged
/// certificate. docs/design/android-tls-artifact-gate.md.
///
/// `flutter_pin_test.dart` (#758) proves the Flutter pins AGREE. Agreement is
/// not safety: every pin moved back to 3.44.9 together keeps it green. This
/// file adds what it cannot see:
///
/// 1. every pin, and the pubspec floor, clears the advisory floor;
/// 2. `tool/verify_android_tls.py` — which reads the BUILT APK — keeps its
///    floor and its eight hashes;
/// 3. CI's `apk-size` job still runs that verifier, after the build, and
///    cannot skip it.
///
/// The release script's own use of the verifier is exercised for real in
/// mobile/test/infra/release_build_test.dart.

/// The first Flutter stable with the fix (the advisory's own number).
const _advisoryFloor = [3, 47, 8];

/// The first Dart release with the fix; Flutter 3.47.8 bundles it.
const _dartFloor = [3, 13, 7];

/// The flutter-action input that names the version, held in a constant as
/// flutter_pin_test.dart holds it: gitleaks misreads a map lookup compared
/// with that literal as a credential.
const _pinField = 'flutter-version';

const _verifier = 'verify_android_tls.py';

List<int> _parse(String version) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version.trim());
  if (m == null) throw FormatException('not X.Y.Z: "$version"');
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// Numeric, not lexicographic: 3.47.10 > 3.47.8.
bool _atLeast(List<int> v, List<int> floor) {
  for (var i = 0; i < 3; i++) {
    if (v[i] != floor[i]) return v[i] > floor[i];
  }
  return true;
}

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

YamlMap _yaml(String path) =>
    loadYaml(File(path).readAsStringSync()) as YamlMap;

void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  group('every Flutter version clears the advisory floor (3.47.8)', () {
    test('the pubspec floor', () {
      final pubspec = _yaml('$root/mobile/pubspec.yaml');
      final constraint = '${(pubspec['environment'] as YamlMap)['flutter']}';
      final floor = RegExp(r'>=\s*(\d+\.\d+\.\d+)').firstMatch(constraint);
      expect(floor, isNotNull, reason: 'no floor in "$constraint"');
      expect(
        _atLeast(_parse(floor!.group(1)!), _advisoryFloor),
        isTrue,
        reason:
            'mobile/pubspec.yaml lets Flutter ${floor.group(1)} build the app: '
            'below 3.47.8, Android trusts the compromised eMudhra CAs '
            '(GHSA-frr6-h895-5pxp)',
      );
    });

    test('every flutter-version in every workflow', () {
      final pins = <String>[];
      final files =
          Directory('$root/.github/workflows')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        void walk(Object? node) {
          if (node is YamlMap) {
            for (final entry in node.entries) {
              if (entry.key == _pinField) pins.add('$name=${entry.value}');
              walk(entry.value);
            }
          } else if (node is YamlList) {
            node.forEach(walk);
          }
        }

        walk(loadYaml(file.readAsStringSync()));
      }
      expect(
        pins.where((p) => p.startsWith('ci.yml=')),
        isNotEmpty,
        reason:
            'found no Flutter pin in ci.yml: this check would pass on '
            'nothing',
      );
      final below = pins
          .where((p) => !_atLeast(_parse(p.split('=').last), _advisoryFloor))
          .toList();
      expect(below, isEmpty, reason: 'below 3.47.8: $below');
    });

    test('the golden script', () {
      final script = File('$root/tool/update_goldens.sh').readAsStringSync();
      final pin = RegExp(
        r'^FLUTTER_VERSION="([^"]+)"',
        multiLine: true,
      ).allMatches(script).toList();
      expect(pin, hasLength(1));
      expect(_atLeast(_parse(pin.single.group(1)!), _advisoryFloor), isTrue);
    });
  });

  group('tool/$_verifier keeps its floor and its eight hashes', () {
    final source = File('$root/tool/$_verifier')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n');

    test('MIN_DART is at least 3.13.7', () {
      final m = RegExp(
        r'^MIN_DART = \((\d+), (\d+), (\d+)\)$',
        multiLine: true,
      ).allMatches(source).toList();
      expect(m, hasLength(1), reason: 'MIN_DART must be set exactly once');
      final v = [for (var i = 1; i <= 3; i++) int.parse(m.single.group(i)!)];
      expect(
        _atLeast(v, _dartFloor),
        isTrue,
        reason: 'MIN_DART $v would accept an engine without the fix',
      );
    });

    test('BLOCKLIST holds eight distinct SHA-256 values', () {
      final block = RegExp(
        r'^BLOCKLIST = \((.*?)^\)',
        multiLine: true,
        dotAll: true,
      ).firstMatch(source);
      expect(block, isNotNull, reason: 'no BLOCKLIST tuple');
      final quoted = RegExp(r"'([^']*)'");
      final hashes = [
        for (final m in quoted.allMatches(block!.group(1)!)) m.group(1)!,
      ];
      expect(hashes, hasLength(8), reason: 'BoringSSL blocks eight keys');
      expect(hashes.toSet(), hasLength(8), reason: 'a hash is repeated');
      for (final h in hashes) {
        expect(h, matches(RegExp(r'^[0-9a-f]{64}$')), reason: h);
      }
    });
  });

  group('CI reads the built APK, after the build, and cannot skip it', () {
    final ci = _yaml('$root/.github/workflows/ci.yml');
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

    test('the job exists and is not conditional', () {
      expect(job, isNotNull, reason: 'ci.yml lost its apk-size job');
      expect(job!.containsKey('if'), isFalse);
      expect(job.containsKey('continue-on-error'), isFalse);
    });

    test('the self-test, then the APK, both after the build', () {
      final build = index(
        'builds the release APK',
        (r) => r.contains('flutter build apk'),
      );
      final selfTest = index(
        'runs the verifier self-test',
        (r) => r.contains('$_verifier --self-test'),
      );
      final apk = index(
        'runs the verifier on the APK',
        (r) =>
            r.contains(_verifier) &&
            r.contains(
              'build/app/outputs/flutter-apk/app-consumer-release.apk',
            ),
      );
      expect(selfTest, greaterThan(build));
      expect(
        apk,
        greaterThan(build),
        reason:
            'before the build it reads '
            'nothing — or a stale file',
      );
      for (final i in [selfTest, apk]) {
        final step = steps[i] as YamlMap;
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
      }
    });
  });
}
