import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/screens/provider/android/pro_android_extensions.dart';

import '../support/app_roots.dart';
import '../support/dart_source.dart';
import '../support/pro_closure.dart';

/// The import fence between the two Pro apps
/// (docs/design/pro-android-signup.md §5.1, §8.1 P1, P5).
///
/// ## Why this file exists
///
/// Apple refused 0.0.1 for signing salons up in the app (3.1.1, build 587),
/// and Google Play does not: so MyWeli Pro signs salons up again on Android
/// only. A runtime check (`if Android`) would make the iOS sign-up
/// unreachable, not absent — its screens and sentences would still be in the
/// binary Apple reads. So everything Android-only lives in
/// `lib/screens/provider/android/`, reached from `lib/main_pro_android.dart`
/// alone, and the iOS entry `lib/main_pro.dart` never reaches it.
///
/// The compiler only drops what the program cannot reach. **This file is the
/// fence's only guard**: an import of the fenced folder from any shared file
/// would put Android's sign-up into the iOS binary with every other test
/// green. app-store-forms §11.3's read of the signed IPA is the binary half.
void main() {
  const fenced = 'lib/screens/provider/android/';

  group('the iOS app reaches nothing behind the fence (P1)', () {
    test('lib/main_pro.dart\'s closure holds no fenced file', () {
      final ios = proClosure();
      expect(
        ios.keys,
        contains('lib/screens/provider/auth/pro_login_screen.dart'),
        reason: 'the closure no longer reaches the sign-in: it reads nothing',
      );
      expect(ios.keys.where((f) => f.startsWith(fenced)), isEmpty);
    });

    test('only the Android entry and the fenced files import the fence', () {
      final importers = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final path = f.path.replaceAll(r'\', '/');
        final code = stripDartComments(f.readAsStringSync());
        final reachesFence =
            RegExp(
              r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
              multiLine: true,
            ).allMatches(code).any((m) {
              final target = resolveDartUri(path, m.group(1)!);
              return target != null && target.startsWith(fenced);
            });
        if (reachesFence) importers.add(path);
      }
      expect(
        importers,
        contains('lib/main_pro_android.dart'),
        reason: 'the Android entry must reach the fence, or this reads nothing',
      );
      expect(
        importers.where(
          (p) => p != 'lib/main_pro_android.dart' && !p.startsWith(fenced),
        ),
        isEmpty,
        reason:
            'a shared file that imports the fence carries Android\'s sign-up '
            'into the iOS binary (pro-android-signup.md §5.1)',
      );
    });

    test('the Android entry reaches the fence AND the iOS app\'s wiring', () {
      final android = proClosure('lib/main_pro_android.dart');
      expect(
        android.keys,
        contains('lib/screens/provider/android/pro_android_extensions.dart'),
      );
      expect(android.keys, contains('lib/main_pro.dart'));
    });

    test('and it hands over to runProApp rather than building its own app — '
        'so every pin on main_pro.dart\'s wiring holds for both (P14)', () {
      final code = stripDartComments(
        File('lib/main_pro_android.dart').readAsStringSync(),
      );
      expect(
        code,
        matches(RegExp(r"import\s+'main_pro\.dart'\s+show\s+runProApp\s*;")),
      );
      expect(
        code,
        matches(
          RegExp(
            r'runProApp\(\s*extensions:\s*proAndroidExtensionsFor\(\s*'
            r'defaultTargetPlatform\s*\)',
          ),
        ),
      );
      expect(
        appRootSource(File('lib/main_pro_android.dart')).path,
        'lib/main_pro.dart',
      );
    });
  });

  group('iOS gets no extensions, even from the Android file (P5)', () {
    // A hand-made iOS build from the wrong entry would then show nothing
    // (§5.1, « Defence in depth »); its strings would remain, and the IPA
    // read catches those.
    for (final platform in TargetPlatform.values.where(
      (p) => p != TargetPlatform.android,
    )) {
      test('$platform → null', () {
        expect(proAndroidExtensionsFor(platform), isNull);
      });
    }
  });

  test('Android gets the sign-up: its route and the sign-in\'s block (P5)', () {
    final android = proAndroidExtensionsFor(TargetPlatform.android);
    expect(android, isNotNull);
    expect(android!.routes.whereType<GoRoute>().map((r) => r.path), [
      '/pro/register',
    ]);
    expect(android.login, isNotNull);
  });
}
