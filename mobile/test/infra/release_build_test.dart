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
      // Run in a throwaway repository at its own `origin/main` (B9.2: the
      // script builds nothing else), with the tools stubbed.
      late _ReleaseRepo repo;
      setUpAll(() => repo = _ReleaseRepo());
      tearDownAll(() => repo.dispose());

      ProcessResult build(String key) => repo.run(
        'ios',
        'consumer',
        env: {'STUB_CARTO_KEY': key, 'STUB_NODE_EXIT': '42'},
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

  // docs/design/hygiene-batch9.md §2.2 (B9.2) — run for real, in a
  // throwaway repository with `gcloud`, `node`, `flutter` and `xcrun` stubbed.
  group('a store build is a reviewed commit, archived, validated (B9.2)', () {
    late _ReleaseRepo repo;
    setUp(() => repo = _ReleaseRepo());
    tearDown(() => repo.dispose());

    String out(ProcessResult r) => '${r.stdout}${r.stderr}';

    test('a commit that is not origin/main is refused before anything is '
        'read', () {
      repo.commit('a change nobody reviewed');
      final r = repo.run('ios', 'consumer');
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('origin/main'));
      expect(repo.gcloudCalls, isEmpty, reason: 'no secret read for it');
      expect(out(r), isNot(contains('STUB_FLUTTER_REACHED')));
    });

    test('a tree that is not clean is refused — an untracked file too', () {
      File('${repo.work.path}/mobile/notes.txt').writeAsStringSync('x');
      final r = repo.run('ios', 'consumer');
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('not clean'));
      expect(repo.gcloudCalls, isEmpty);
    });

    test('a modified tracked file is refused', () {
      File(
        '${repo.work.path}/mobile/pubspec.yaml',
      ).writeAsStringSync('name: myweli\nversion: 0.0.2+1\n');
      final r = repo.run('android', 'pro');
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('not clean'));
    });

    test('an iOS build without the App Store Connect key is refused first', () {
      final r = repo.run('ios', 'consumer', env: {'ASC_KEY_ID': ''});
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('ASC_KEY_ID'));
      expect(repo.gcloudCalls, isEmpty);
    });

    test('the archive is parked under its flavour AND build, the IPA is '
        'validated, then — only then — the upload command is printed', () {
      final r = repo.run('ios', 'pro');
      final o = out(r);
      expect(r.exitCode, 0, reason: o);
      const n = 1; // one commit: build 1 in this repository
      final archive = Directory(
        '${repo.work.path}/mobile/build/ios/archive/Runner-pro-$n.xcarchive',
      );
      expect(archive.existsSync(), isTrue, reason: o);
      expect(
        Directory(
          '${repo.work.path}/mobile/build/ios/archive/Runner.xcarchive',
        ).existsSync(),
        isFalse,
        reason: 'the next build would overwrite it',
      );
      expect(repo.xcrunCalls.join('\n'), contains('--validate-app'));
      expect(
        repo.xcrunCalls.join('\n'),
        contains('build/ios/ipa/MyWeli-pro.ipa'),
      );
      expect(o, contains('--upload-package'));
      expect(o, contains('MyWeli-pro.ipa'));
    });

    test('a refused validation stops everything: no upload command', () {
      final r = repo.run('ios', 'pro', env: {'STUB_VALIDATE_EXIT': '1'});
      final o = out(r);
      expect(r.exitCode, 1, reason: o);
      expect(o, isNot(contains('--upload-package')));
      expect(o, isNot(contains('debug-files upload')));
    });

    test('a build that wrote no archive is refused', () {
      final r = repo.run('ios', 'pro', env: {'STUB_NO_ARCHIVE': '1'});
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('Runner.xcarchive'));
    });

    test('the Sentry command carries the archive\'s dSYMs and the Dart '
        'symbols, and names the suspect commits of THIS release', () {
      final r = repo.run('ios', 'pro');
      final o = out(r);
      expect(r.exitCode, 0, reason: o);
      final upload = o
          .split('\n')
          .skipWhile((l) => !l.contains('debug-files upload'))
          .take(3)
          .join(' ');
      expect(upload, contains('mobile/build/symbols/pro'));
      expect(
        upload,
        contains('mobile/build/ios/archive/Runner-pro-1.xcarchive/dSYMs'),
      );
      expect(o, contains('set-commits'));
      expect(o, contains('com.myweli.pro@0.0.1+1'), reason: 'the app release');
      expect(o, contains('Zaslons/myweli@${repo.head}'));
    });

    test('Android: no validation step, the same release and commits', () {
      final r = repo.run('android', 'consumer');
      final o = out(r);
      expect(r.exitCode, 0, reason: o);
      expect(repo.xcrunCalls, isEmpty);
      expect(o, contains('com.myweli.app@0.0.1+1'));
      expect(o, contains('Zaslons/myweli@${repo.head}'));
      expect(o, isNot(contains('dSYMs')));
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

/// A throwaway repository holding `tool/release_build.sh` (the real file), at
/// its own `origin/main` and clean — the only state the script builds from —
/// with `gcloud`, `node`, `flutter` and `xcrun` stubbed on PATH. The stubs log
/// what reached them; `flutter build ipa` leaves an IPA and an archive behind.
class _ReleaseRepo {
  _ReleaseRepo() {
    root = Directory.systemTemp.createTempSync('release-repo-');
    work = Directory('${root.path}/work')..createSync();
    stubs = Directory('${root.path}/stubs')..createSync();
    Directory('${work.path}/tool').createSync();
    File(
      '${work.path}/tool/release_build.sh',
    ).writeAsStringSync(File('../tool/release_build.sh').readAsStringSync());
    Directory('${work.path}/mobile').createSync();
    File(
      '${work.path}/mobile/pubspec.yaml',
    ).writeAsStringSync('name: myweli\nversion: 0.0.1+1\n');
    Directory('${work.path}/infra/mobile').createSync(recursive: true);
    File(
      '${work.path}/infra/mobile/96-verify-google-identity.mjs',
    ).writeAsStringSync('// stub\n');
    File('${work.path}/.gitignore').writeAsStringSync('mobile/build/\n');
    _git(['init', '-q', '-b', 'main']);
    commit('base');
    Process.runSync('git', ['init', '-q', '--bare', '${root.path}/origin.git']);
    _git(['remote', 'add', 'origin', '${root.path}/origin.git']);
    _git(['push', '-q', 'origin', 'main']);
    _git(['fetch', '-q', 'origin']);
    _stub('gcloud', r'''
echo "$*" >> "$STUB_LOG/gcloud"
case "$*" in
  *--secret=MOBILE_SENTRY_DSN*) echo 'https://abc123@o1.ingest.de.sentry.io/2' ;;
  *--secret=SENTRY_DSN*) echo 'https://def456@o1.ingest.de.sentry.io/3' ;;
  *--secret=CARTO_BASEMAPS_KEY*) printf '%s\n' "${STUB_CARTO_KEY:-aB3_-zZ9-q_Wk8yLmN0pQrStU}" ;;
  *) exit 99 ;;
esac
''');
    _stub('node', r'''
echo STUB_NODE_REACHED
exit "${STUB_NODE_EXIT:-0}"
''');
    _stub('flutter', r'''
echo STUB_FLUTTER_REACHED
case "$*" in
  *"build ipa"*)
    sleep 1
    mkdir -p build/ios/ipa build/ios/archive
    if [ -z "$STUB_NO_ARCHIVE" ]; then
      mkdir -p build/ios/archive/Runner.xcarchive/dSYMs
    fi
    printf 'ipa' > build/ios/ipa/MyWeli.ipa
    ;;
esac
''');
    _stub('xcrun', r'''
echo "$*" >> "$STUB_LOG/xcrun"
exit "${STUB_VALIDATE_EXIT:-0}"
''');
    Directory('${root.path}/log').createSync();
  }

  late final Directory root;
  late final Directory work;
  late final Directory stubs;

  String get head =>
      (Process.runSync('git', [
                'rev-parse',
                'HEAD',
              ], workingDirectory: work.path).stdout
              as String)
          .trim();

  List<String> _log(String tool) {
    final f = File('${root.path}/log/$tool');
    return f.existsSync() ? f.readAsLinesSync() : const [];
  }

  List<String> get gcloudCalls => _log('gcloud');
  List<String> get xcrunCalls => _log('xcrun');

  void commit(String message) {
    File(
      '${work.path}/mobile/HISTORY',
    ).writeAsStringSync('$message\n', mode: FileMode.append);
    _git(['add', '-A']);
    _git([
      '-c',
      'user.name=t',
      '-c',
      'user.email=t@t',
      'commit',
      '-q',
      '-m',
      message,
    ]);
  }

  ProcessResult run(
    String platform,
    String flavour, {
    Map<String, String> env = const {},
  }) => Process.runSync(
    'bash',
    ['${work.path}/tool/release_build.sh', platform, flavour],
    environment: {
      'PATH': '${stubs.path}:${Platform.environment['PATH']}',
      'STUB_LOG': '${root.path}/log',
      'ASC_KEY_ID': 'KEY123',
      'ASC_ISSUER_ID': 'issuer-uuid',
      ...env,
    },
  );

  void _git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: work.path);
    if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
  }

  void _stub(String name, String body) {
    final f = File('${stubs.path}/$name')
      ..writeAsStringSync('#!/bin/sh\n$body');
    Process.runSync('chmod', ['+x', f.path]);
  }

  void dispose() => root.deleteSync(recursive: true);
}
