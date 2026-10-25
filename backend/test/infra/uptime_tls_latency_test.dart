// The uptime checks measure two things nobody watched (docs/design/
// hygiene-batch9.md §2.3, B9.4, decision 34): the certificate api.myweli.com
// serves, and how long it takes to answer. Without `--validate-ssl` a check
// passes against an expired or wrong certificate — the browsers and the apps
// refuse it, the probe does not — and the certificate's days-left metric is
// never written. And a service answering in nine seconds passes every check.
//
// These read the scripts, the way the other infra guards here do: the scripts
// are run by hand, against the cloud, after asking.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final checks = File('../infra/gcp/80-uptime-checks.sh').readAsStringSync();
  final file = File('../infra/gcp/81-uptime-tls-latency.sh');

  String code(String s) =>
      s.split('\n').where((l) => !l.trimLeft().startsWith('#')).join('\n');

  test('the checks as created validate the certificate', () {
    // One logical command per line: continuation backslashes joined first.
    final creates = code(checks)
        .replaceAll('\\\n', ' ')
        .split('\n')
        .where((l) => l.contains('gcloud monitoring uptime create'))
        .toList();
    expect(creates, hasLength(2));
    for (final c in creates) {
      expect(c, contains('--validate-ssl=true'), reason: c);
    }
  });

  group('81-uptime-tls-latency.sh', () {
    late String script;
    setUpAll(() {
      expect(file.existsSync(), isTrue, reason: 'the script is missing');
      script = code(file.readAsStringSync());
    });

    test('turns certificate validation on for BOTH existing checks, by the '
        'id read back — the checks already exist', () {
      expect(script, contains('gcloud monitoring uptime update'));
      expect(script, contains('--validate-ssl=true'));
      expect(script, contains('api-health'));
      expect(script, contains('api-providers-database'));
      expect(script, contains('list-configs'));
    });

    test('refuses without the owner channel, as every alert here does', () {
      expect(script, contains('displayName="Owner email"'));
      expect(script, contains('exit 1'));
    });

    test('a certificate with less than 14 days left alerts', () {
      expect(
        script,
        contains(
          'monitoring.googleapis.com/uptime_check/time_until_ssl_cert_expires',
        ),
      );
      final policy = _policy(script, 'time_until_ssl_cert_expires');
      expect(policy, contains('"comparison": "COMPARISON_LT"'));
      expect(policy, contains('"thresholdValue": 14'));
      expect(policy, contains(r'"notificationChannels": ["${CHANNEL}"]'));
    });

    test('an answer slower than 3 s for 15 minutes alerts', () {
      expect(
        script,
        contains('monitoring.googleapis.com/uptime_check/request_latency'),
      );
      final policy = _policy(script, 'request_latency');
      expect(policy, contains('"comparison": "COMPARISON_GT"'));
      expect(policy, contains('"thresholdValue": 3000'));
      expect(policy, contains('"duration": "900s"'));
      expect(
        policy,
        contains('REDUCE_MEAN'),
        reason: 'one slow probe region must not page anyone',
      );
      expect(policy, contains(r'"notificationChannels": ["${CHANNEL}"]'));
    });

    test('each policy carries its runbook', () {
      for (final metric in ['time_until_ssl_cert_expires', 'request_latency']) {
        expect(_policy(script, metric), contains('"documentation"'));
      }
    });
  });
}

/// The heredoc'd policy that names [metric].
String _policy(String script, String metric) {
  final docs = RegExp(r'<<JSON\n([\s\S]*?)\nJSON').allMatches(script);
  final hit = docs.map((m) => m.group(1)!).where((d) => d.contains(metric));
  expect(hit, hasLength(1), reason: 'one policy on $metric');
  return hit.single;
}
