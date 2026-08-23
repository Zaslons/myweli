import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The audiences the backend accepts, held to the ones the apps present.
///
/// ## Why this file exists
///
/// `GOOGLE_CLIENT_IDS` and `APPLE_CLIENT_IDS` were secrets, so the expected set
/// and the actual set were two copies with nothing between them. On 2026-08-22
/// answering "is the Pro client allowlisted?" meant reaching for
/// `gcloud secrets versions access` — and the answer that came back was then
/// **misread**, costing a day, because the reasoning about which id is even
/// presented had nowhere to live.
///
/// They are public identifiers that ship inside the app binary, so they now sit
/// in both service manifests as plain values and this runs on every push.
///
/// ## What it does NOT assert
///
/// That the allowlist is exactly the required set. It asserts
/// **required ⊆ allowlist ⊆ known**, and the two containments catch different
/// things: the first that something the apps present is missing, the second
/// that an id nobody recognises has appeared. Equality would force removing the
/// two consumer ids production carries today — a behaviour change wearing a
/// test's clothes, and one whose safety rests on the very reasoning that was
/// got wrong once already.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  YamlMap service(String name) =>
      loadYaml(File('$root/infra/gcp/$name').readAsStringSync()) as YamlMap;

  Set<String> allowlist(YamlMap svc, String name) {
    final env = (svc['spec']['template']['spec']['containers'] as YamlList)
        .expand((c) => (c['env'] as YamlList? ?? const []))
        .cast<YamlMap>();
    final entry = env.firstWhere(
      (e) => e['name'] == name,
      orElse: () => YamlMap(),
    );
    final raw = entry['value'] as String?;
    return (raw ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  final signing =
      jsonDecode(
            File('$root/infra/mobile/signing-manifest.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final audience = signing['audience'] as Map<String, dynamic>;
  final serverId = audience['server'] as String;
  final flavourIds = (audience['clients'] as List)
      .cast<Map<String, dynamic>>()
      .map((c) => c['id'] as String)
      .toSet();

  final identity =
      jsonDecode(
            File(
              '$root/infra/identity/oauth-audience-manifest.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final appleWebId =
      (identity['appleWebServicesId'] as Map<String, dynamic>)['id'] as String;

  /// Every distinct app bundle id the Xcode project builds. `RunnerTests`
  /// targets are excluded — a test bundle never signs anybody in.
  final bundleIds = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
      .allMatches(
        File(
          '$root/mobile/ios/Runner.xcodeproj/project.pbxproj',
        ).readAsStringSync(),
      )
      .map((m) => m.group(1)!.trim())
      .where((b) => !b.endsWith('.RunnerTests'))
      .toSet();

  /// **The conditional invariant, and the load-bearing part of this file.**
  ///
  /// `GoogleSignIn.instance.initialize(serverClientId: ...)` makes the token's
  /// `aud` the web client on BOTH platforms — verified from
  /// `FLTGoogleSignInPlugin.m:344` -> `GIDConfiguration.h:27` ->
  /// `GIDSignIn.m:901`. So today only the server id must be allowlisted, and a
  /// guard demanding the four per-flavour ids would refuse a release that works
  /// perfectly. That mistake was made here once.
  ///
  /// If a refactor ever drops that argument, the audience silently becomes each
  /// build's own client id — for every flavour at once. Evaluating the same
  /// condition the app does means that change turns this test red instead of
  /// breaking sign-in for everybody.
  final passesServerClientId =
      RegExp(r'serverClientId:\s*AppConfig\.googleServerClientId').hasMatch(
        File(
          '$root/mobile/lib/services/api/api_auth_service.dart',
        ).readAsStringSync(),
      );

  final requiredGoogle = passesServerClientId ? {serverId} : flavourIds;
  final knownGoogle = {serverId, ...flavourIds};
  final requiredApple = {...bundleIds, appleWebId};

  group('the derived sets are real', () {
    // Every assertion below is a set comparison. If one of the extractions
    // silently yields nothing — a renamed key, a reformatted pbxproj — the
    // comparisons pass against emptiness and this file guards nothing.
    test('the app configs actually parsed', () {
      expect(flavourIds, hasLength(4));
      expect(bundleIds, containsAll(['com.myweli.app', 'com.myweli.pro']));
      expect(serverId, contains('.apps.googleusercontent.com'));
      expect(appleWebId, isNotEmpty);
    });

    test('the app is compiled with the server id the manifest names', () {
      expect(
        File('$root/mobile/lib/core/config/app_config.dart').readAsStringSync(),
        contains(serverId),
        reason:
            'the manifest names an audience the build does not send, so every '
            'assertion below is about the wrong id',
      );
    });

    test('the serverClientId condition is being read, not assumed', () {
      expect(
        passesServerClientId,
        isTrue,
        reason:
            'api_auth_service.dart no longer passes serverClientId. That is a '
            'real change in what the backend must accept — the audience is now '
            'each flavour own client id — and the required set below has '
            'flipped accordingly. This test says so rather than letting '
            'sign-in break quietly.',
      );
    });
  });

  for (final env in ['service.yaml', 'service-staging.yaml']) {
    group(env, () {
      final svc = service(env);

      test('accepts every Google audience the apps present', () {
        expect(
          allowlist(svc, 'GOOGLE_CLIENT_IDS'),
          containsAll(requiredGoogle),
          reason:
              'a build presents an audience this service will reject, so Google '
              'succeeds and the backend refuses the token — the user picks an '
              'account and lands back on an error',
        );
      });

      test('accepts no Google id nobody recognises', () {
        expect(
          allowlist(svc, 'GOOGLE_CLIENT_IDS').difference(knownGoogle),
          isEmpty,
          reason:
              'an audience that belongs to no app of ours is a token from '
              'somewhere else being accepted as one of ours',
        );
      });

      test('accepts exactly the Apple audiences that exist', () {
        // Apple has no serverClientId indirection: the `aud` IS the running
        // app's bundle id, or the web Services ID. Every one is needed and
        // nothing else belongs.
        expect(
          allowlist(svc, 'APPLE_CLIENT_IDS'),
          requiredApple,
          reason:
              'each iOS flavour presents its own bundle id, and the web its '
              'Services ID. A missing one is a whole app that cannot sign in',
        );
      });
    });
  }

  test('staging and production accept the same audiences', () {
    for (final name in ['GOOGLE_CLIENT_IDS', 'APPLE_CLIENT_IDS']) {
      expect(
        allowlist(service('service-staging.yaml'), name),
        allowlist(service('service.yaml'), name),
        reason:
            '$name differs between environments, so a token minted for one is '
            'rejected by the other',
      );
    }
  });
}
