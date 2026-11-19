import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `mobile/scripts/run_pro.sh` — how a developer runs the Pro app on a device.
///
/// The Pro app has two entries since B0.17 (docs/design/pro-android-signup.md
/// §5.6): `lib/main_pro_android.dart` on Android, where the salon sign-up
/// lives, and `lib/main_pro.dart` on iOS, sign-in only. The script used to run
/// `lib/main_pro.dart` everywhere and without `--flavor pro`, so an Android run
/// showed no sign-up at all, which reads as a bug that is not there.
///
/// Executed, not grepped: `flutter` is stubbed on PATH. Its `devices
/// --machine` answer is a fixed list, and every other call is logged, so each
/// case reads the exact `flutter run` line the script would start.
void main() {
  late Directory stubs;
  late File log;

  setUp(() {
    stubs = Directory.systemTemp.createTempSync('run-pro-');
    log = File('${stubs.path}/flutter.log');
    final flutter = File('${stubs.path}/flutter')
      ..writeAsStringSync('''#!/bin/bash
if [[ "\$1" == devices && "\$2" == --machine ]]; then
  cat <<'JSON'
[
  {"name": "sdk gphone64 arm64", "id": "emulator-5554", "targetPlatform": "android-arm64"},
  {"name": "Galaxy A73", "id": "RZCW102W0NT", "targetPlatform": "android-arm64"},
  {"name": "iPhone 17", "id": "IPHONE-17", "targetPlatform": "ios"}
]
JSON
  exit 0
fi
echo "\$*" >> "${log.path}"
''');
    Process.runSync('chmod', ['+x', flutter.path]);
  });

  tearDown(() => stubs.deleteSync(recursive: true));

  ProcessResult run(List<String> args) => Process.runSync(
    'bash',
    ['scripts/run_pro.sh', ...args],
    environment: {'PATH': '${stubs.path}:${Platform.environment['PATH']}'},
  );

  String ran() => log.existsSync() ? log.readAsStringSync().trim() : '';

  test('an Android device runs the Android entry, with the Pro flavour', () {
    final r = run(['emulator-5554']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(
      ran(),
      'run --flavor pro -t lib/main_pro_android.dart -d emulator-5554',
    );
  });

  test('a device named instead of its id is found too', () {
    final r = run(['Galaxy A73']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(ran(), contains('-t lib/main_pro_android.dart'));
  });

  test('an iPhone runs the sign-in-only entry', () {
    final r = run(['IPHONE-17']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(ran(), 'run --flavor pro -t lib/main_pro.dart -d IPHONE-17');
  });

  test('an entry given as the second argument wins', () {
    final r = run(['emulator-5554', 'lib/main_pro.dart']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(ran(), 'run --flavor pro -t lib/main_pro.dart -d emulator-5554');
  });

  test('the remaining arguments reach flutter run', () {
    final r = run([
      'emulator-5554',
      '--dart-define=USE_API_BACKEND=true',
      '--dart-define=API_BASE_URL=https://api.myweli.com',
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(
      ran(),
      'run --flavor pro -t lib/main_pro_android.dart -d emulator-5554 '
      '--dart-define=USE_API_BACKEND=true '
      '--dart-define=API_BASE_URL=https://api.myweli.com',
    );
  });

  test('an unknown device stops before running anything', () {
    final r = run(['no-such-phone']);
    expect(r.exitCode, 2);
    expect(r.stderr, contains('no device « no-such-phone »'));
    expect(ran(), isEmpty);
  });

  test('no device at all is refused with the usage line', () {
    final r = run([]);
    expect(r.exitCode, isNot(0));
    expect(r.stderr, contains('usage: run_pro.sh'));
    expect(ran(), isEmpty);
  });
}
