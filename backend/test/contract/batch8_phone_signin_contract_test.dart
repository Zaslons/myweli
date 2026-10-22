import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// docs/design/product-questions-batch8.md §2.5 (B8.5, decision 31) — the
/// Pro phone sign-in is gone. It opened with the CLIENTS' `AUTH_METHODS`
/// switch, so bringing SMS back to clients would have opened it too; and it
/// signed into the first account carrying the number, which stopped being
/// unique in migration 0023. Rebuilt on purpose when SMS returns, with the
/// identity decided (B8.2).
///
/// dart_frog routes by FILE: with the two files gone, the router answers 404
/// whatever `AUTH_METHODS` says — which is the point of this test.
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final paths = (doc['paths'] as YamlMap).keys.cast<String>().toList();

  test('no Pro phone sign-in route — the router answers 404, phone on or '
      'off', () {
    expect(File('routes/auth/provider/otp/request.dart').existsSync(), isFalse);
    expect(File('routes/auth/provider/otp/verify.dart').existsSync(), isFalse);
    expect(Directory('routes/auth/provider/otp').existsSync(), isFalse);
  });

  test('the contract documents no Pro phone sign-in', () {
    expect(paths.where((p) => p.startsWith('/auth/provider/otp')), isEmpty);
  });

  test('the Pro auth stores keep no phone code', () {
    for (final f in [
      'lib/src/auth/provider_auth_repository.dart',
      'lib/src/db/postgres_provider_auth_repository.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src, isNot(contains('requestOtp(')), reason: f);
      expect(src, isNot(contains('verifyOtp(')), reason: f);
      expect(src, isNot(contains('provider_otp_codes')), reason: f);
    }
  });

  test('CONTROL: the clients’ phone routes stay, behind AUTH_METHODS', () {
    for (final f in [
      'routes/auth/otp/request.dart',
      'routes/auth/otp/verify.dart',
    ]) {
      expect(
        File(f).readAsStringSync(),
        contains("contains('phone')"),
        reason: f,
      );
    }
    expect(paths, containsAll(['/auth/otp/request', '/auth/otp/verify']));
  });
}
