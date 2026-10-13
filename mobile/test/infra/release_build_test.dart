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

  group('the iOS IPA survives building the OTHER flavour', () {
    // `flutter build ipa` always exports to build/ios/ipa/MyWeli.ipa, so
    // without the flavour-suffixed move, `ios pro` after `ios consumer`
    // silently replaces the consumer IPA — measured 2026-08-29, caught only
    // by a bytes-level entitlement check on what was ABOUT to be uploaded.
    test('the script parks the IPA under the flavour name', () {
      expect(
        code,
        contains(r'MyWeli-$FLAVOUR.ipa'),
        reason:
            'the move to a flavour-suffixed IPA is gone — the second iOS '
            'build will silently overwrite the first again',
      );
    });

    test('and refuses unless THIS build exported exactly one IPA', () {
      // Found by recency, not by name: since the App Store audit (#550)
      // Xcode names the export after the flavour's CFBundleName (« MyWeli
      // Pro.ipa »), and the old fixed-name check refused a good build 551.
      expect(
        code,
        contains(r'-newer "$BUILD_MARK"'),
        reason:
            'without the marker, yesterday\'s IPA counts as this build\'s '
            'and the operator uploads it',
      );
      expect(
        code,
        contains(r'${#FRESH[@]} -ne 1'),
        reason:
            'without the exactly-one check, a build that produced nothing '
            'still "succeeds", or two candidates are guessed between',
      );
      expect(
        code,
        isNot(contains(r'"$IPA_DIR/MyWeli.ipa"')),
        reason: 'the fixed export name is wrong since #550 (CFBundleName)',
      );
    });
  });

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

  group('every artifact gets its own build number', () {
    /// **Every build this script ever produced claimed to be build 1.**
    ///
    /// `pubspec.yaml`'s build number is `+1` and nothing overrode it, so the
    /// number was frozen. Both stores reject a second upload reusing a build
    /// number — but that is the least of it. `client-version-gate.md` makes the
    /// build number the identity of a release, and three things already key on
    /// it: the server-side version floor, the Sentry release string, and the
    /// staged-rollout crash-free signal. All three were reading a constant.
    test('it passes --build-number at all', () {
      expect(
        code,
        contains('--build-number'),
        reason:
            'without it every artifact is build 1, the second upload to either '
            'store is rejected, and the version-gate floor can never be raised '
            'above a shipped build',
      );
    });

    test('and the number is a variable, not a literal', () {
      // A hardcoded `--build-number 2` satisfies the test above and reintroduces
      // the whole defect one release later.
      expect(
        RegExp(r'--build-number\s+"?\$').hasMatch(code),
        isTrue,
        reason: 'the build number must be derived, not typed',
      );
    });

    test('it refuses rather than defaulting when it cannot derive one', () {
      // The script's stated philosophy: a build that cannot read what it needs
      // FAILS here rather than shipping blind. A default would be worse than
      // useless — a build number that goes backwards can never be used again,
      // because the store has already seen the higher one.
      expect(code, contains('BUILD_NUMBER'));
      expect(
        code.contains('is-shallow-repository'),
        isTrue,
        reason:
            'a shallow clone returns a SMALLER commit count, which is the one '
            'way this number can go backwards — and it does so silently',
      );
    });

    test('the premise: pubspec still carries the frozen +1', () {
      // If someone starts bumping pubspec by hand, the derived number and the
      // typed one disagree and the last one on the command line wins. This test
      // exists so that day is noticed rather than discovered from a store.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1);
      expect(
        version,
        isNotNull,
        reason: 'pubspec.yaml has no version line at all',
      );
      expect(
        version,
        contains('+'),
        reason:
            'the +N suffix IS the build number Flutter passes through to '
            'CFBundleVersion and versionCode',
      );
    });
  });

  group('the maps get their basemap key (docs/design/map-basemap-key.md)', () {
    /// **Builds up to 555 draw « API KEY REQUIRED » on every map.** Since
    /// 2026-09-25 CARTO serves no raster tile without a usable key, and the
    /// key is a `String.fromEnvironment` that defaults to empty — so a build
    /// missing the define does not fail, warn or crash. It ships, and every
    /// map is a watermark. This script is the only place that can refuse.

    test('it reads CARTO_BASEMAPS_KEY from Secret Manager', () {
      expect(
        code,
        contains('--secret=CARTO_BASEMAPS_KEY'),
        reason: 'the key must come from Secret Manager, never be typed',
      );
    });

    test('and refuses to build when it is empty', () {
      final at = code.indexOf(r'-z "$CARTO_KEY"');
      expect(at, isNonNegative, reason: 'no emptiness check on the key');
      final end = RegExp(
        r'^\s*fi\s*$',
        multiLine: true,
      ).allMatches(code).firstWhere((m) => m.start > at).start;
      final branch = code.substring(at, end);
      expect(
        branch,
        contains('exit 1'),
        reason: 'an empty key must stop the build, not be reported and ignored',
      );
    });

    test('and refuses a key with whitespace in it', () {
      // A key pasted with a stray space or line ends up in the URL as `%20` /
      // `%0A` — CARTO treats a damaged key as no key: the watermark again.
      // (`$(…)` strips trailing newlines; anything else survives into it.)
      final at = code.indexOf(r'"$CARTO_KEY" =~ [[:space:]]');
      expect(at, isNonNegative, reason: 'no whitespace check on the key');
      final end = RegExp(
        r'^\s*fi\s*$',
        multiLine: true,
      ).allMatches(code).firstWhere((m) => m.start > at).start;
      expect(
        code.substring(at, end),
        contains('exit 1'),
        reason:
            'a damaged key must stop the build, not be reported and ignored',
      );
      final build = code.indexOf('flutter build');
      expect(build, isNonNegative);
      expect(at, lessThan(build), reason: 'refuse before anything compiles');
    });

    group('and refuses a key not shaped like one — run for real', () {
      // Non-empty and blank-free still lets a placeholder through (`TODO`, a
      // truncated paste), and CARTO answers a key it does not know with the
      // watermark: every map « API KEY REQUIRED » in a build that looked
      // fine. So the script checks the SHAPE — letters, digits, `_`, `-`, at
      // least 20 — never the value, and never prints it.
      //
      // Executed, not grepped: `gcloud` and `node` are stubbed on PATH, so the
      // script runs its real checks and stops at the first thing it cannot
      // fake. A refused key exits 1 before the Google sign-in check; an
      // accepted one reaches it (the stub `node` exits 42) — still before any
      // `flutter build`.
      late Directory stubs;

      setUpAll(() {
        stubs = Directory.systemTemp.createTempSync('release-build-stubs-');
        File('${stubs.path}/gcloud').writeAsStringSync(r'''#!/bin/sh
case "$*" in
  *--secret=MOBILE_SENTRY_DSN*) echo 'https://abc123@o1.ingest.de.sentry.io/2' ;;
  *--secret=SENTRY_DSN*) echo 'https://def456@o1.ingest.de.sentry.io/3' ;;
  *--secret=CARTO_BASEMAPS_KEY*) printf '%s\n' "$STUB_CARTO_KEY" ;;
  *) exit 99 ;;
esac
''');
        File(
          '${stubs.path}/node',
        ).writeAsStringSync('#!/bin/sh\necho STUB_NODE_REACHED\nexit 42\n');
        Process.runSync('chmod', [
          '+x',
          '${stubs.path}/gcloud',
          '${stubs.path}/node',
        ]);
      });

      tearDownAll(() => stubs.deleteSync(recursive: true));

      ProcessResult build(String key) => Process.runSync(
        'bash',
        ['../tool/release_build.sh', 'ios', 'consumer'],
        environment: {
          'PATH': '${stubs.path}:${Platform.environment['PATH']}',
          'STUB_CARTO_KEY': key,
        },
      );

      final bad = {
        'a placeholder': 'TODO',
        'another placeholder': 'changeme',
        'one character short': 'a' * 19,
        'a dot': '${'a' * 24}.',
        'base64 padding': '${'A' * 22}==',
        'a slash': '${'k' * 12}/${'k' * 12}',
        'a plus': '${'k' * 12}+${'k' * 12}',
      };
      bad.forEach((what, key) {
        test('refuses $what, and does not print it', () {
          final r = build(key);
          final out = '${r.stdout}${r.stderr}';
          expect(r.exitCode, 1, reason: out);
          expect(out, contains('CARTO_BASEMAPS_KEY'));
          expect(
            out,
            isNot(contains('STUB_NODE_REACHED')),
            reason: 'refused only after the next step started',
          );
          expect(out, isNot(contains(key)), reason: 'the key was printed');
        });
      });

      test('accepts a well-shaped key and goes on — without printing it', () {
        const good = 'aB3_-zZ9-q_Wk8yLmN0pQrStU';
        final r = build(good);
        final out = '${r.stdout}${r.stderr}';
        expect(out, contains('STUB_NODE_REACHED'), reason: out);
        expect(r.exitCode, 42, reason: out);
        expect(out, isNot(contains(good)));
      });
    });

    test('it passes the key as a define, from the variable', () {
      expect(
        RegExp(
          r'--dart-define=CARTO_BASEMAPS_KEY="?\$CARTO_KEY',
        ).hasMatch(code),
        isTrue,
        reason:
            'without the define the app builds keyless and every map shows '
            'the watermark',
      );
    });

    test('the define is the very name AppConfig reads', () {
      // A rename on either side compiles, builds and ships keyless — the
      // define is passed, nothing reads it.
      final config = File('lib/core/config/app_config.dart').readAsStringSync();
      final read = RegExp(
        r"cartoBasemapsKey\s*=\s*String\.fromEnvironment\(\s*'(\w+)'",
      ).firstMatch(config)?.group(1);
      final passed = RegExp(
        r'--dart-define=(\w+)="?\$CARTO_KEY',
      ).firstMatch(code)?.group(1);
      expect(read, isNotNull, reason: 'AppConfig no longer reads a define');
      expect(passed, read);
    });

    test('the refusal comes before anything compiles', () {
      // A refusal after `flutter build` would leave a keyless artifact on
      // disk, ready to be uploaded by hand.
      final refusal = code.indexOf(r'-z "$CARTO_KEY"');
      expect(refusal, isNonNegative, reason: 'no emptiness check on the key');
      for (final build in ['flutter build ipa', 'flutter build appbundle']) {
        final at = code.indexOf(build);
        expect(at, isNonNegative, reason: '$build is gone from the script');
        expect(refusal, lessThan(at), reason: 'refuse before $build');
      }
    });

    test('the key never reaches a progress line', () {
      // Uses the RAW script: `code` has the echo lines stripped.
      final leaks = script
          .split('\n')
          .where((l) => l.trimLeft().startsWith('echo '))
          .where((l) => l.contains(r'$CARTO_KEY') || l.contains(r'${CARTO_KEY'))
          .toList();
      expect(leaks, isEmpty);
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
