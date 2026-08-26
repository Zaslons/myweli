import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Which signing keys and OAuth clients Google will actually accept.
///
/// ## Why this file exists
///
/// Google matches an Android sign-in request by **(package name, signing
/// certificate SHA-1)**. On 2026-08-22 the only fingerprint registered against
/// either package was a development keystore — so every build the owner installs
/// signs in perfectly, and the store build, signed by Google with a different
/// key and matches no OAuth client — and the user is shown **nothing**.
/// Credential Manager reports a wrong signing SHA as `canceled`, which the
/// plugin cannot tell from a dismissal (`app-google-signin-v7.md` §9);
/// `api_auth_service.dart:189` maps that to `code: 'cancelled'` with an empty
/// message, and `auth_provider.dart:141` sets `_error = null` for it. No
/// banner, no log, no crash — the button simply does nothing.
///
/// **The success case and the failure case are the same code path**, and the
/// failure case is silent, which is why no amount of testing on a device
/// would have found it. The difference is
/// entirely in who signed the artifact, and that is decided after the last test
/// has run.
///
/// This file is the half that CI can see: the committed configs must agree with
/// `infra/mobile/signing-manifest.json` on every push, so a fingerprint nobody
/// declared, or a manifest that has drifted from the files, goes red the moment
/// it is committed rather than on release day.
///
/// The other half — that Play App Signing is enrolled at all, and that the
/// backend's `GOOGLE_CLIENT_IDS` accepts what the build will present — needs
/// Secret Manager and lives in `infra/mobile/96-verify-google-identity.mjs`,
/// which `tool/release_build.sh` runs before it produces an artifact. Neither
/// alone is enough, exactly as with `log_retention_test.dart` and
/// `97-verify-log-retention.sh`: the test cannot see the cloud, and the release
/// gate does not run on a push.
///
/// **Note what this file does NOT assert:** that Play App Signing is currently
/// unenrolled. A guard that pins today's value goes red the day the problem is
/// FIXED and stays green while it rots — the mistake `registration-claim` was
/// built to undo. Everything here asserts *consistency*, so it survives the fix.
void main() {
  final manifest =
      jsonDecode(
            File('../infra/mobile/signing-manifest.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  final play = manifest['playAppSigning'] as Map<String, dynamic>;
  final devFingerprints = (manifest['developmentFingerprints'] as List)
      .cast<Map<String, dynamic>>();
  final devHashes = devFingerprints.map((f) => f['sha1'] as String).toList();
  final packages = (manifest['packages'] as Map<String, dynamic>);
  final audience = manifest['audience'] as Map<String, dynamic>;

  /// google-services.json is generated from console state and carries one
  /// `client_type: 1` entry per registered fingerprint, so this IS the set
  /// Google will match on — as far as the last download knew.
  List<Map<String, dynamic>> androidClients(String flavour, String package) {
    final cfg =
        jsonDecode(
              File(
                'android/app/src/$flavour/google-services.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final client = (cfg['client'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere(
          (c) =>
              ((c['client_info'] as Map)['android_client_info']
                  as Map)['package_name'] ==
              package,
          orElse: () => <String, dynamic>{},
        );
    if (client.isEmpty) return const [];
    return (client['oauth_client'] as List)
        .cast<Map<String, dynamic>>()
        .where((c) => c['client_type'] == 1)
        .toList();
  }

  final hex40 = RegExp(r'^[0-9a-f]{40}$');

  group('the manifest cannot lie about itself', () {
    test(
      'development fingerprints are stored the way the config stores them',
      () {
        for (final f in devFingerprints) {
          expect(
            hex40.hasMatch(f['sha1'] as String),
            isTrue,
            reason:
                'the Firebase console shows AA:BB:CC…; google-services.json stores '
                'lowercase with the colons stripped. The other form compares '
                'unequal against every entry and the failure names no cause',
          );
        }
      },
    );

    test('a development keystore can never be marked release-safe', () {
      // Otherwise the gate could be satisfied by the very key it rejects.
      for (final f in devFingerprints) {
        expect(
          f['releaseSafe'],
          isFalse,
          reason: '${f['sha1']} is a debug key',
        );
      }
    });

    test('a Play SHA-1 per package, present exactly when enrolment is claimed',
        () {
      // One PER PACKAGE — the first shape held a single field on the
      // assumption that one App Signing key covers both apps; the real
      // enrolment (2026-08-26) generated one key per app.
      final shas = packages.map(
        (name, meta) =>
            MapEntry(name, (meta as Map<String, dynamic>)['playSha1']),
      );
      if (play['enrolled'] == true) {
        shas.forEach((name, sha) {
          expect(
            hex40.hasMatch((sha as String?) ?? ''),
            isTrue,
            reason:
                '$name: enrolled without a well-formed fingerprint verifies '
                'nothing',
          );
          expect(
            devHashes.contains(sha),
            isFalse,
            reason:
                '$name: that is the debug keystore wearing the release label',
          );
        });
        expect(
          shas.values.toSet(),
          hasLength(shas.length),
          reason:
              'Play generates one App Signing key PER APP; identical values '
              'means one fingerprint pasted twice — or the UPLOAD key, which '
              'is shared because one keystore signs both uploads. Exactly '
              'that confusion happened on 2026-08-26',
        );
      } else {
        shas.forEach((name, sha) {
          expect(
            sha,
            isNull,
            reason:
                '$name: a fingerprint recorded while enrolled is false means '
                'one of the two is wrong',
          );
        });
      }
    });
  });

  group('the committed configs agree with the manifest', () {
    packages.forEach((package, meta) {
      final flavour = (meta as Map<String, dynamic>)['flavour'] as String;

      test('$package has an Android OAuth client at all', () {
        expect(
          androidClients(flavour, package),
          isNotEmpty,
          reason: 'without one, Google sign-in cannot work on any build',
        );
      });

      test('every fingerprint registered for $package is declared', () {
        final registered = androidClients(
          flavour,
          package,
        ).map((c) => (c['android_info'] as Map)['certificate_hash'] as String);
        for (final hash in registered) {
          expect(
            devHashes.contains(hash) || hash == meta['playSha1'],
            isTrue,
            reason:
                'somebody registered signing key $hash against a production '
                'OAuth client and did not write down whose it is. Declare it in '
                'the manifest, or remove it from the console',
          );
        }
      });

      test('$package carries the Play key once enrolment is recorded', () {
        // Vacuous until the day it matters, and red on exactly that day: the
        // fingerprint gets added in the console and the config is not
        // re-downloaded, which is the likeliest way this is got wrong.
        if (play['enrolled'] != true) return;
        final registered = androidClients(
          flavour,
          package,
        ).map((c) => (c['android_info'] as Map)['certificate_hash'] as String);
        expect(
          registered.contains(meta['playSha1']),
          isTrue,
          reason:
              'the Play App Signing key is recorded in the manifest but absent '
              'from android/app/src/$flavour/google-services.json — the file was '
              'never re-downloaded, or the fingerprint was never added to this '
              'package',
        );
      });
    });
  });

  group('the manifest is not a second source of truth', () {
    /// A list of ids maintained beside the files that hold the same ids is how
    /// four documents in this repo went stale at once. Every id the manifest
    /// names must be the id a build actually presents.
    final clients = (audience['clients'] as List).cast<Map<String, dynamic>>();

    for (final c in clients) {
      final platform = c['platform'] as String;
      final flavour = c['flavour'] as String;

      test('$platform/$flavour matches the config it claims to describe', () {
        String? actual;
        if (platform == 'ios') {
          final body = File(
            'ios/config/$flavour/GoogleService-Info.plist',
          ).readAsStringSync();
          final i = body.indexOf('<key>CLIENT_ID</key>');
          actual = i < 0
              ? null
              : RegExp(
                  r'<string>([^<]*)</string>',
                ).firstMatch(body.substring(i))?.group(1);
        } else {
          final package = packages.entries
              .firstWhere((e) => (e.value as Map)['flavour'] == flavour)
              .key;
          actual =
              androidClients(flavour, package).first['client_id'] as String?;
        }
        expect(
          actual,
          c['id'],
          reason:
              'the manifest describes a client no build presents, so the release '
              'gate would be checking the wrong id against the backend allowlist',
        );
      });
    }

    test('the server client id is the one the app is compiled with', () {
      // AppConfig.googleServerClientId is what Android sends as `aud`.
      final config = File('lib/core/config/app_config.dart').readAsStringSync();
      expect(
        config,
        contains(audience['server'] as String),
        reason:
            'the manifest names a server client id the app does not use, so the '
            'audience the gate verifies is not the audience the backend receives',
      );
    });
  });

  group('the release gate exists and is reachable', () {
    /// Comments AND `echo` lines stripped, for the reason
    /// `release_build_test.dart` records: a progress message naming a command
    /// is no more executable than a comment, and the first version of that file
    /// passed under mutation because of exactly this.
    final code = File('../tool/release_build.sh')
        .readAsStringSync()
        .split('\n')
        .map((l) {
          final t = l.trimLeft();
          return t.startsWith('#') || t.startsWith('echo ') ? '' : l;
        })
        .join('\n');

    test('the script runs the verifier', () {
      expect(
        code,
        contains('96-verify-google-identity.mjs'),
        reason:
            'without it a store artifact can be built for a configuration that '
            'cannot sign in — which is how both of 2026-08-22 defects would ship',
      );
    });

    test('and it runs BEFORE the build, not after', () {
      expect(
        code.indexOf('96-verify-google-identity.mjs') <
            code.indexOf('flutter build'),
        isTrue,
        reason: 'a check after the build is a report, not a gate',
      );
    });

    test('it passes the flavour and platform through', () {
      // Hardcoding either would verify one combination and ship the other three.
      expect(RegExp(r'--platform\s+"?\$').hasMatch(code), isTrue);
      expect(RegExp(r'--flavour\s+"?\$').hasMatch(code), isTrue);
    });

    test('the verifier it names is actually there', () {
      expect(
        File('../infra/mobile/96-verify-google-identity.mjs').existsSync(),
        isTrue,
      );
    });

    group('the bootstrap-enrolment escape (comments stripped first)', () {
      // Enrolment HAPPENS at the first AAB upload, so a gate that refuses
      // every unenrolled build also refuses the one build that can end the
      // unenrolled state. The escape must exist — and must be exactly as
      // narrow as the chicken-and-egg it resolves.
      final mjs = File('../infra/mobile/96-verify-google-identity.mjs')
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp('//[^\n]*'), '');

      test('it exists, keyed on the exact env var', () {
        expect(
          mjs,
          contains("process.env.BOOTSTRAP_PLAY_ENROLMENT === '1'"),
          reason:
              'without it, the first upload — the one that creates the '
              'enrolment — cannot be built at all',
        );
      });

      test(
        'it covers ONLY the not-enrolled branch, never the SHA mismatch',
        () {
          // The escape must sit inside `if (!play.enrolled)` and before the
          // `else if` that catches an enrolled app whose google-services.json
          // was never re-downloaded. That second failure is a config that
          // LOOKS finished and is not — bypassing it would ship the silent
          // sign-in failure to real testers, which is the thing this whole
          // gate exists to prevent.
          final escape = mjs.indexOf('BOOTSTRAP_PLAY_ENROLMENT');
          final enrolledBranch = mjs.indexOf('if (!play.enrolled)');
          final shaBranch = mjs.indexOf(
            'registered.includes(packageEntry.playSha1)',
          );
          expect(escape, greaterThan(enrolledBranch));
          expect(escape, lessThan(shaBranch));
          // The DOOR is the env read; the refusal MESSAGE also names the flag
          // (that is how an operator learns it exists) — so the count is on
          // `process.env.` reads, not on the string.
          expect(
            'process.env.BOOTSTRAP_PLAY_ENROLMENT'.allMatches(mjs),
            hasLength(1),
            reason:
                'one escape, one branch — a second env read would be a '
                'second door',
          );
        },
      );
    });
  });

  group('the premise: these are the packages that ship', () {
    test('the manifest names the applicationIds Gradle builds', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      for (final package in packages.keys) {
        expect(
          gradle,
          contains('applicationId = "$package"'),
          reason:
              'the manifest describes a package nothing builds, so every check '
              'above is verifying an app that does not exist',
        );
      }
    });
  });
}
