import 'dart:io';

import 'package:test/test.dart';

/// `infra/gcp/policy-bodies.sh` is the hand-kept list of alert scripts two
/// checks render their policies from: `93-sync-runbooks.sh` (the runbooks
/// synced to the live policies) and `95-emitter-lag.sh` (can the running code
/// print what each alert watches for). A script that creates a policy but is
/// missing from the list is invisible to both — and 95 still reports
/// « every alert can produce every string it watches for ».
///
/// Seen on 2026-10-22: the demo-reset alert (`84-demo-reset-alert.sh`,
/// docs/design/backend-integrity-batch6.md §2.9) was created on GCP and 95 did
/// not list it, as checked or as skipped.
void main() {
  test('every script that creates an alert policy is on the list', () {
    final list = File('../infra/gcp/policy-bodies.sh').readAsStringSync();
    final listed = RegExp(
      r'^\s*add infra/gcp/(\S+\.sh)\s*$',
      multiLine: true,
    ).allMatches(list).map((m) => m.group(1)!).toSet();

    final creators = [
      for (final f in Directory('../infra/gcp').listSync().whereType<File>())
        if (f.path.endsWith('.sh') &&
            f.readAsStringSync().contains('monitoring policies create'))
          f.uri.pathSegments.last,
    ]..sort();

    expect(creators, isNotEmpty, reason: 'the scan found no alert script');
    for (final script in creators) {
      expect(
        listed,
        contains(script),
        reason:
            '$script creates an alert policy but policy-bodies.sh does not '
            'add it — 93 and 95 cannot see it',
      );
    }
  });
}
