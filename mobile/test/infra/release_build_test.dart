import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `tool/release_build.sh` — the one script that produces store artifacts.
///
/// ## Why this file exists
///
/// It passed `--flavor` and **not** `--target`. `--flavor` selects the NATIVE
/// configuration — bundle id, icon, Firebase config — and has nothing to say
/// about which Dart `main` is compiled, which defaults to `lib/main.dart`. So
/// `release_build.sh <platform> pro` produced an artifact wearing the Pro
/// identity and containing the CONSUMER app. It builds, signs, uploads and
/// installs; `mobile-store-submission.md` §5 named the script **in bold** as
/// the thing to use.
///
/// **Nothing could have caught it.** CI builds `--flavor consumer` only
/// (`ci.yml`'s APK-size job, `ios-build.yml`), so the pro flavour is compiled
/// nowhere in this repository — and for consumer the missing flag is harmless,
/// because the default target is the one it wanted. The failure is invisible
/// until someone opens the app. This test is the substitute for a build nobody
/// runs.
///
/// It greps a shell script, which is a weak instrument — but the defect was a
/// missing flag, and that is exactly what a grep can see.
void main() {
  final script = File('../tool/release_build.sh').readAsStringSync();

  /// **Comments AND `echo` lines stripped**, and the second half was learned
  /// the hard way: the first version of this file stripped only comments, and
  /// under mutation both of its important assertions passed anyway. Removing
  /// `--target "$ENTRY"` from the actual invocation — the original defect,
  /// exactly — left `echo "→ flutter build ipa … --target $ENTRY"` behind, and
  /// the grep found the flag in a sentence *about* the command rather than in
  /// the command. A progress message is no more executable than a comment.
  final code = script
      .split('\n')
      .map((l) {
        final t = l.trimLeft();
        return t.startsWith('#') || t.startsWith('echo ') ? '' : l;
      })
      .join('\n');

  group('the release script compiles the app it is naming', () {
    test('it passes --target at all', () {
      expect(
        code,
        contains('--target'),
        reason:
            'without it every build compiles lib/main.dart, so the pro artifact '
            'carries the Pro identity and the consumer app',
      );
    });

    test('and the target depends on the flavour', () {
      // A hardcoded `--target lib/main.dart` would satisfy the test above and
      // reintroduce the whole defect.
      expect(code, contains('lib/main_pro.dart'));
      expect(code, contains('lib/main.dart'));
      expect(
        RegExp(r'--target\s+"?\$').hasMatch(code),
        isTrue,
        reason: 'the target must be a variable, not a literal',
      );
    });

    test('both entry points it names actually exist', () {
      // A target pointing at a file that is not there fails the build loudly,
      // which is fine — but a RENAMED entry point would leave this script
      // silently wrong again, and renames are how the first defect arrived.
      expect(File('lib/main.dart').existsSync(), isTrue);
      expect(File('lib/main_pro.dart').existsSync(), isTrue);
    });

    test('Android produces an app bundle, not an APK', () {
      // Play requires an AAB for a new app. The two scripts deleted alongside
      // this fix built APKs, so their output could not be uploaded at all.
      expect(code, contains('flutter build appbundle'));
      expect(
        code.contains('flutter build apk'),
        isFalse,
        reason: 'an APK cannot be uploaded for a new Play listing',
      );
    });
  });

  group('the premise: the two entry points are different apps', () {
    /// If these ever converged, `--target` would stop mattering and the test
    /// above would be pinning a flag with no consequence. Stating the reason
    /// out loud is what keeps the rest of this file meaningful.
    test('they mount different routers', () {
      final consumer = File('lib/main.dart').readAsStringSync();
      final pro = File('lib/main_pro.dart').readAsStringSync();

      expect(consumer, contains('AppRouter.router'));
      expect(pro, contains('ProRouter.router'));
      expect(consumer.contains('ProRouter.router'), isFalse);
    });

    test('and nothing picks between them at runtime', () {
      // `--flavor` sets `FLUTTER_APP_FLAVOR`, but no Dart code reads it — so
      // there is no later chance for the app to notice it is the wrong one.
      final lib = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      final readers = lib
          .where((f) => f.readAsStringSync().contains('appFlavor'))
          .map((f) => f.path)
          .toList();
      expect(
        readers,
        isEmpty,
        reason:
            'if something starts branching on the flavour at runtime, the '
            'wrong-app failure stops being silent and this file needs revisiting',
      );
    });
  });
}
