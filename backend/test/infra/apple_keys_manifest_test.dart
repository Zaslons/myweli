import 'dart:io';

import 'package:myweli_backend/src/auth/apple_tokens.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../auth/apple_key.dart';

/// docs/design/apple-signin-keys.md §4, §9 step 5 — the production manifest's
/// Sign in with Apple keys, put through the SAME boot rules the server applies
/// (`AppleSignInKeys.fromEnv`). A manifest the server would refuse to boot on
/// fails here, in CI, instead of at revision creation; one that boots but
/// leaves a client without a key fails here too.
///
/// What this cannot see: whether the mounted `.p8` IS the key its Key ID
/// names. That was checked by fingerprint against the downloads on
/// 2026-10-27; the first real sign-in per client is the test (§9 step 7).
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  YamlList envOf(String file) {
    final svc =
        loadYaml(File('$root/infra/gcp/$file').readAsStringSync()) as YamlMap;
    return svc['spec']['template']['spec']['containers'][0]['env'] as YamlList;
  }

  final prod = envOf('service.yaml');
  final testPem = applePkcs8Pem(appleTestKeyPair().privateKey);

  YamlMap? entry(YamlList env, String name) {
    for (final e in env) {
      if (e['name'] == name) return e as YamlMap;
    }
    return null;
  }

  /// The manifest as the server's `_envOrNull` would see it: plain values as
  /// written; a mounted secret stands in as a readable test key (its value
  /// lives in Secret Manager, not here).
  String? lookup(String name) {
    final e = entry(prod, name);
    if (e == null) return null;
    if (e['valueFrom']?['secretKeyRef'] != null) return testPem;
    final v = (e['value'] as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  final clientIds = lookup('APPLE_CLIENT_IDS')!.split(',');

  const plain = [
    'APPLE_TEAM_ID',
    'APPLE_APP_KEY_ID',
    'APPLE_APP_KEY_CLIENTS',
    'APPLE_PRO_KEY_ID',
    'APPLE_PRO_KEY_CLIENTS',
  ];
  const secrets = ['APPLE_APP_PRIVATE_KEY', 'APPLE_PRO_PRIVATE_KEY'];

  test('anti-vacuity: production declares all seven, and APPLE_CLIENT_IDS', () {
    expect(clientIds, hasLength(3));
    for (final n in [...plain, ...secrets]) {
      expect(entry(prod, n), isNotNull, reason: '$n missing from service.yaml');
    }
  });

  test('the identifiers are plain values, the two keys are mounted secrets '
      'of the same name, pinned to a version number', () {
    for (final n in plain) {
      expect(entry(prod, n)!['valueFrom'], isNull, reason: n);
      expect(entry(prod, n)!['value'], isA<String>(), reason: n);
    }
    for (final n in secrets) {
      final ref = entry(prod, n)!['valueFrom']?['secretKeyRef'];
      expect(ref, isNotNull, reason: '$n must come from Secret Manager');
      expect(ref['name'], n);
      expect(ref['key'], matches(RegExp(r'^[1-9][0-9]*$')), reason: n);
    }
  });

  test('the server would boot on it — every rule of §4 holds', () {
    expect(
      () => AppleSignInKeys.fromEnv(lookup, clientIds: clientIds),
      returnsNormally,
    );
  });

  test('every Apple client has a key: the Pro app the Pro key, the MyWeli app '
      'and the web Services ID the MyWeli key (it sits under MyWeli)', () {
    final keys = AppleSignInKeys.fromEnv(lookup, clientIds: clientIds);
    expect(keys.uncovered(clientIds), isEmpty);
    expect(appleKeysNotice(keys, clientIds), isNull);
    final appKey = lookup('APPLE_APP_KEY_ID');
    final proKey = lookup('APPLE_PRO_KEY_ID');
    expect(appKey, isNot(proKey));
    expect(keys.forClient('com.myweli.pro')!.keyId, proKey);
    expect(keys.forClient('com.myweli.app')!.keyId, appKey);
    expect(keys.forClient('com.myweli.signin')!.keyId, appKey);
  });

  test('the old single-key names are gone from production', () {
    expect(entry(prod, 'APPLE_KEY_ID'), isNull);
    expect(entry(prod, 'APPLE_PRIVATE_KEY'), isNull);
  });

  test('staging mounts no Apple key (it does not exist; its manifest must '
      'not bring production\'s keys back with it)', () {
    final staging = envOf('service-staging.yaml');
    for (final n in [
      ...plain,
      ...secrets,
      'APPLE_KEY_ID',
      'APPLE_PRIVATE_KEY',
    ]) {
      expect(entry(staging, n), isNull, reason: n);
    }
  });
}
