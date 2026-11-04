import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `ios/tool/setup_flavours.rb` — the script that gives the iOS project its
/// two flavours (docs/design/mobile-ios-flavours.md).
///
/// Its header promised « IDEMPOTENT: re-running is a no-op », and it was not
/// (docs/design/hygiene-batch9.md §2.2, B9.3): every run deleted and recreated
/// the « Copy Firebase config » phase under a NEW UUID, and rewrote both
/// schemes from scratch — dropping the « Run Prepare Flutter Framework Script »
/// pre-action and `customLLDBInitFile` that Flutter's own migration had added.
/// So nobody could re-run it without reading, and hand-reverting, the diff.
///
/// Run for real on a COPY of `ios/`, with the `xcodeproj` gem it needs. The
/// gem is a Mac thing (CocoaPods carries it): on a machine without it these
/// tests skip — except where `REQUIRE_XCODEPROJ=1`, set by the macOS iOS
/// workflow so a missing gem fails there instead of skipping unseen.
void main() {
  final hasGem =
      Process.runSync('ruby', ['-e', "require 'xcodeproj'"]).exitCode == 0;
  final required = Platform.environment['REQUIRE_XCODEPROJ'] == '1';
  final skip = hasGem || required
      ? false
      : 'the xcodeproj gem is not installed (macOS + CocoaPods only)';

  late Directory root;
  late String ios;

  ProcessResult sh(String cmd) =>
      Process.runSync('bash', ['-c', cmd], workingDirectory: ios);

  String status() => (sh('git status --porcelain').stdout as String).trim();

  ProcessResult setup() => Process.runSync(
    'ruby',
    ['tool/setup_flavours.rb'],
    workingDirectory: ios,
    // A non-UTF-8 locale on purpose: the script must read back the em-dash
    // it writes (its header's 2026-08-22 note).
    environment: {'LANG': 'C', 'LC_ALL': 'C'},
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('setup-flavours-');
    ios = '${root.path}/ios';
    final copy = Process.runSync('rsync', [
      '-a',
      '--exclude',
      'Pods',
      '--exclude',
      'build',
      '--exclude',
      '.symlinks',
      'ios/',
      '$ios/',
    ]);
    expect(copy.exitCode, 0, reason: '${copy.stderr}');
    expect(
      sh(
        'git init -q && git add -A && '
        'git -c user.name=t -c user.email=t@t commit -qm base',
      ).exitCode,
      0,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  const scheme = 'Runner.xcodeproj/xcshareddata/xcschemes';

  test('on the committed project, a run changes nothing', () {
    final r = setup();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(
      status(),
      isEmpty,
      reason:
          'a re-run rewrote the project — the phase got a new UUID, or a '
          'scheme lost what Flutter added to it:\n'
          '${sh('git diff --stat').stdout}',
    );
  }, skip: skip);

  test('a missing scheme is created; the run after it changes nothing', () {
    File('$ios/$scheme/pro.xcscheme').deleteSync();
    expect(setup().exitCode, 0);
    final pro = File('$ios/$scheme/pro.xcscheme').readAsStringSync();
    expect(pro, contains('buildConfiguration = "Release-pro"'));
    expect(pro, contains('buildConfiguration = "Debug-pro"'));
    sh('git add -A && git -c user.name=t -c user.email=t@t commit -qm again');
    expect(setup().exitCode, 0);
    expect(status(), isEmpty, reason: '${sh('git diff').stdout}');
  }, skip: skip);

  test('a wrong configuration is put right IN PLACE: what Flutter added to '
      'the scheme stays', () {
    final f = File('$ios/$scheme/consumer.xcscheme');
    f.writeAsStringSync(
      f.readAsStringSync().replaceFirst(
        'buildConfiguration = "Release-consumer"',
        'buildConfiguration = "Release"',
      ),
    );
    expect(setup().exitCode, 0);
    final after = f.readAsStringSync();
    expect(after, contains('buildConfiguration = "Release-consumer"'));
    expect(after, contains('Run Prepare Flutter Framework Script'));
    expect(after, contains('customLLDBInitFile'));
    expect(status(), isEmpty, reason: 'back to the committed scheme exactly');
  }, skip: skip);

  test('the premise: the committed schemes carry what Flutter added', () {
    // If these go, the in-place test above proves nothing.
    for (final flavour in ['consumer', 'pro']) {
      final s = File('ios/$scheme/$flavour.xcscheme').readAsStringSync();
      expect(s, contains('Run Prepare Flutter Framework Script'));
      expect(s, contains('customLLDBInitFile'));
    }
  });

  test('the header no longer promises what the script did not do', () {
    final script = File('ios/tool/setup_flavours.rb').readAsStringSync();
    expect(script, contains('IDEMPOTENT'));
    expect(
      script,
      contains('in place'),
      reason: 'say how it is idempotent, now that it is',
    );
  });
}
