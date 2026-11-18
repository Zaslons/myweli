import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/pro_app_extensions.dart';
import 'package:myweli/main_pro.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/dart_source.dart';

/// How `runProApp` hands the extensions to the app
/// (docs/design/pro-android-signup.md §5.2 — B0.17 PR A).
///
/// The router must be built with them before anything reads it, and the
/// sign-in must find its block above it. Neither shows on screen until PR B
/// puts something behind the fence, so this file holds the wiring itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
  });

  final extras = ProLoginExtras(
    block:
        (
          context, {
          required bool noAccount,
          String? email,
          String? code,
          required VoidCallback onReturned,
        }) => const SizedBox.shrink(),
  );

  Future<ProLoginExtras?> provided(
    WidgetTester tester, {
    ProLoginExtras? loginExtras,
  }) async {
    ProLoginExtras? read;
    await tester.pumpWidget(
      MultiProvider(
        providers: proAppProviders(ProAuthProvider(), loginExtras: loginExtras),
        child: Builder(
          builder: (context) {
            read = Provider.of<ProLoginExtras?>(context, listen: false);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // The provider's constructor loads a session through the mock's delays:
    // let them land, or the test ends with timers pending.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    return read;
  }

  testWidgets('the app\'s stores carry the sign-in\'s block when there is '
      'one', (tester) async {
    expect(await provided(tester, loginExtras: extras), same(extras));
  });

  testWidgets('and none without — the iOS app: the sign-in reads null', (
    tester,
  ) async {
    expect(await provided(tester), isNull);
  });

  group('runProApp\'s order (source, comments stripped)', () {
    final code = stripDartComments(
      File('lib/main_pro.dart').readAsStringSync(),
    );
    int at(String pattern) => code.indexOf(RegExp(pattern));

    test('the router is installed before anything can read it', () {
      final install = at(r'ProRouter\.install\(\s*extensions\s*\)');
      expect(install, isNonNegative, reason: 'runProApp installs no router');
      for (final reader in [
        r'ProAuthProvider\(\)',
        r'_startPush\(\s*proAuth\s*\)',
        r'runApp\(\s*MyweliProApp\(',
      ]) {
        expect(at(reader), greaterThan(install), reason: reader);
      }
    });

    test('the extensions\' block reaches the app\'s stores', () {
      expect(
        code,
        matches(
          RegExp(
            r'MyweliProApp\(\s*auth:\s*proAuth,\s*'
            r'loginExtras:\s*extensions\?\.login,?\s*\)',
          ),
        ),
      );
      expect(
        code,
        matches(
          RegExp(
            r'proAppProviders\(\s*auth,\s*loginExtras:\s*loginExtras\s*\)',
          ),
        ),
      );
    });
  });
}
