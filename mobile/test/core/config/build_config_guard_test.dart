import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/config/app_config.dart';
import 'package:myweli/core/config/build_config_guard.dart';

/// The release-build backend guard (docs/design/infra-staging.md §1.3).
///
/// **What can and cannot be tested here, honestly.** `AppConfig`'s values come
/// from `String.fromEnvironment`, which is resolved at *compile* time — a test
/// cannot set a `--dart-define` and re-read it. And `flutter test` always runs
/// in debug, so `kReleaseMode` is false for the whole suite.
///
/// So these tests pin two things that ARE knowable in-process: that the guard
/// is inert in the mode every test and every local run uses, and that its
/// inputs are wired to the constants it claims to compare. The release
/// behaviour itself is verified by building with and without the defines — see
/// the PR, which records both outcomes.
void main() {
  group('inert outside release', () {
    test('debug builds never report a misconfiguration', () {
      // The whole suite runs in debug. If this ever fails, the guard has
      // started firing during tests and every widget test is about to break.
      expect(kReleaseMode, isFalse, reason: 'flutter test runs in debug');
      expect(AppConfig.backendMisconfiguration, isNull);
      expect(misconfiguredBuildScreen(), isNull);
    });

    test(
      'the default build is a mock build, and that stays legal in debug',
      () {
        // Restates the contract the defaults encode: no defines → mocks. The
        // guard exists to make that illegal in RELEASE only, never here.
        expect(AppConfig.useApiBackend, isFalse);
        expect(AppConfig.apiBaseUrl, AppConfig.localhostApiBaseUrl);
      },
    );
  });

  group('the guard compares against the real default', () {
    test('localhostApiBaseUrl is the declared default of apiBaseUrl', () {
      // The guard's second branch is `apiBaseUrl == localhostApiBaseUrl`. If
      // someone changes the `defaultValue` without changing the constant, that
      // branch silently stops matching and the guard quietly stops guarding —
      // which is exactly the failure mode this whole slice is about.
      expect(AppConfig.localhostApiBaseUrl, 'http://localhost:8080');
      expect(
        const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: AppConfig.localhostApiBaseUrl,
        ),
        AppConfig.apiBaseUrl,
        reason: 'apiBaseUrl must default to localhostApiBaseUrl',
      );
    });

    test('the mock-release escape hatch is off unless asked for', () {
      // `ALLOW_MOCK_RELEASE` must never be on by accident — it is the one way
      // to ship a release build on mocks deliberately.
      expect(AppConfig.allowMockRelease, isFalse);
    });
  });
}
