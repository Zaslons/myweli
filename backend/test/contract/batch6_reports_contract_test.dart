import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// docs/design/backend-integrity-batch6.md §2.6 (B6.6) — the salon's report
/// is in the contract, and the admin queue says which reports are the salon's.
void main() {
  final doc = loadYaml(File('../docs/api/openapi.yaml').readAsStringSync());
  final paths = doc['paths'] as YamlMap;

  test('POST /me/provider/reviews/{id}/report: 200, 403 for a member '
      'without profile.manage, 404', () {
    final post = paths['/me/provider/reviews/{id}/report']['post'] as YamlMap;
    final r = post['responses'] as YamlMap;
    expect(r.keys, containsAll(['200', '401', '403', '404']));
    expect('${r['403']['description']}', contains('profile.manage'));
  });

  test('the admin queue item carries reportedBySalon', () {
    final items =
        paths['/admin/reviews/reports']['get']['responses']['200']['content']['application/json']['schema']['properties']['items']['items']['properties']
            as YamlMap;
    expect((items['reportedBySalon'] as YamlMap)['type'], 'boolean');
  });
}
