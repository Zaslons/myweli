import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Every place that names the Flutter version names the same one.
///
/// ## Why this file exists
///
/// The Flutter version is written down in seven places — six
/// `flutter-version:` pins across four workflows, and `FLUTTER_VERSION` in
/// `tool/update_goldens.sh` — plus the floor of `environment.flutter` in
/// `mobile/pubspec.yaml`. Moving them is a procedure (« in one commit »,
/// docs/design/mobile-flutter-3.47-upgrade.md §4), and a procedure is not a
/// check: a pin left behind, or a workflow added later with another version,
/// stays green while CI builds one thing and the goldens or the admin console
/// another. The pubspec comment already carried stale line numbers for these
/// pins, which is how they drift.
///
/// It also pins the ceiling. `environment.flutter` carries an upper bound one
/// minor above the floor, so dependabot resolves its lockfiles on the Flutter
/// CI runs instead of the newest stable (spec §2) — without it, every
/// dependabot pub PR fails `--enforce-lockfile` as #745–#749 did.
/// The flutter-action input that names the version. A named constant, not a
/// literal beside `entry.key ==`: that shape reads as a credential to
/// gitleaks' generic-api-key rule (BACKLOG B9.x's arrow false positive, again).
const _pinField = 'flutter-version';

void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  /// Every `flutter-version:` value in every workflow, with where it was found.
  /// Parsed as YAML, so a commented-out pin cannot count.
  List<({String where, String version})> workflowPins() {
    final pins = <({String where, String version})>[];
    final dir = Directory('$root/.github/workflows');
    final files =
        dir
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
            if (entry.key == _pinField) {
              pins.add((where: name, version: '${entry.value}'));
            }
            walk(entry.value);
          }
        } else if (node is YamlList) {
          node.forEach(walk);
        }
      }

      walk(loadYaml(file.readAsStringSync()));
    }
    return pins;
  }

  /// Every step that installs Flutter, with whether it says which one.
  List<({String where, bool pinned})> flutterInstalls() {
    final installs = <({String where, bool pinned})>[];
    final dir = Directory('$root/.github/workflows');
    for (final file in dir.listSync().whereType<File>()) {
      if (!(file.path.endsWith('.yml') || file.path.endsWith('.yaml'))) {
        continue;
      }
      final name = file.uri.pathSegments.last;
      void walk(Object? node) {
        if (node is YamlMap) {
          final uses = node['uses'];
          if (uses is String && uses.startsWith('subosito/flutter-action')) {
            final with_ = node['with'];
            installs.add((
              where: name,
              pinned: with_ is YamlMap && with_[_pinField] != null,
            ));
          }
          node.values.forEach(walk);
        } else if (node is YamlList) {
          node.forEach(walk);
        }
      }

      walk(loadYaml(file.readAsStringSync()));
    }
    return installs;
  }

  String goldenScriptPin() {
    final script = File('$root/tool/update_goldens.sh').readAsStringSync();
    final matches = RegExp(
      r'^FLUTTER_VERSION="([^"]+)"',
      multiLine: true,
    ).allMatches(script).toList();
    expect(
      matches,
      hasLength(1),
      reason: 'tool/update_goldens.sh must set FLUTTER_VERSION exactly once',
    );
    return matches.single.group(1)!;
  }

  ({String floor, String? ceiling}) pubspecFlutter() {
    final pubspec =
        loadYaml(File('$root/mobile/pubspec.yaml').readAsStringSync())
            as YamlMap;
    final constraint = '${(pubspec['environment'] as YamlMap)['flutter']}';
    final floor = RegExp(r'>=\s*([0-9][^\s<]*)').firstMatch(constraint);
    final ceiling = RegExp(r'<\s*([0-9][^\s]*)').firstMatch(constraint);
    expect(
      floor,
      isNotNull,
      reason: 'environment.flutter has no floor: "$constraint"',
    );
    return (floor: floor!.group(1)!, ceiling: ceiling?.group(1));
  }

  test('the workflows pin Flutter in at least the six known places', () {
    // An empty sweep — a renamed key, a moved directory — must not pass the
    // equality test below by comparing nothing.
    expect(
      workflowPins().length,
      greaterThanOrEqualTo(6),
      reason:
          'ci.yml (3), goldens.yml, ios-build.yml and deploy-admin.yml each '
          'pin Flutter; found ${workflowPins()}',
    );
  });

  test('every Flutter install in CI says which Flutter', () {
    final unpinned = flutterInstalls().where((i) => !i.pinned).toList();
    expect(
      flutterInstalls(),
      isNotEmpty,
      reason: 'no subosito/flutter-action step found — the sweep is broken',
    );
    expect(
      unpinned,
      isEmpty,
      reason:
          'a flutter-action step without flutter-version installs whatever '
          'is newest that day',
    );
  });

  test(
    'every pin, the golden script and the pubspec floor are one version',
    () {
      final pins = workflowPins();
      final golden = goldenScriptPin();
      final floor = pubspecFlutter().floor;
      final versions = {for (final p in pins) p.version, golden, floor};
      expect(
        versions,
        hasLength(1),
        reason:
            'Flutter is named differently in different places: '
            '${[for (final p in pins) '${p.where}=${p.version}']}, '
            'tool/update_goldens.sh=$golden, mobile/pubspec.yaml floor=$floor',
      );
    },
  );

  test('environment.flutter stops below the next minor', () {
    final flutter = pubspecFlutter();
    final parts = flutter.floor.split('.').map(int.parse).toList();
    final nextMinor = '${parts[0]}.${parts[1] + 1}.0';
    expect(
      flutter.ceiling,
      nextMinor,
      reason:
          'without this ceiling, dependabot resolves on the newest stable '
          'Flutter and its lockfiles fail --enforce-lockfile on the one CI '
          'pins (#745–#749)',
    );
  });
}
