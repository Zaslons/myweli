import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// docs/design/backend-integrity-batch6.md §3 — what PR A changed in the
/// contract is in the contract: the 403 on a non-client booking (B6.1), the
/// 409 on a revoked member's role (B6.8c), and the cron's demo reset that
/// says why (B6.9).
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final paths = doc['paths'] as YamlMap;

  test('POST /appointments documents the 403 for a non-client token', () {
    final r = paths['/appointments']['post']['responses'] as YamlMap;
    expect(r.containsKey('403'), isTrue);
    expect('${r['403']['description']}', contains('forbidden'));
  });

  test(
    'PATCH /me/provider/members/{memberId} documents 409 member_revoked',
    () {
      final r =
          paths['/me/provider/members/{memberId}']['patch']['responses']
              as YamlMap;
      expect('${r['409']['description']}', contains('member_revoked'));
    },
  );

  test('the maintenance cron’s demoReset says why — never a bare boolean', () {
    final props =
        paths['/internal/cron/maintenance']['post']['responses']['200']['content']['application/json']['schema']['properties']
            as YamlMap;
    final demo = props['demoReset'] as YamlMap;
    expect(demo['type'], 'string');
    expect(
      (demo['enum'] as YamlList).toList(),
      containsAll(['ran', 'not_due', 'no_snapshot', 'refused:not_demo_owned']),
    );
  });
}
