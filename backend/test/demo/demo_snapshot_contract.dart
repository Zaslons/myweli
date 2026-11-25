import 'dart:convert';

import 'package:myweli_backend/src/demo/demo_snapshot_repository.dart';
import 'package:test/test.dart';

/// The contract of [DemoSnapshotRepository], run against BOTH twins: in
/// memory (`demo_reset_restore_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself.
///
/// docs/design/demo-reset-restore.md §5.3 (B16.2, C-M1, decision 222). The
/// snapshot is the curated demo salon the weekly reset puts back. Postgres
/// keeps it as `jsonb`, so a read is always a new copy; the in-memory store
/// kept a shallow copy and handed out that same map, so a reviewer's
/// in-place edits to the live salon's lists rewrote the snapshot itself.
///
/// [repo] builds the store; the caller empties it before each case (one row,
/// ever).
void demoSnapshotContract({required DemoSnapshotRepository Function() repo}) {
  final t0 = DateTime.utc(2026, 8, 26, 3);

  Map<String, dynamic> doc() => {
    'name': 'Maison Nala',
    'services': [
      {'id': 's1', 'name': 'Coupe', 'price': 5000.0},
    ],
    'availability': {
      'weeklySchedule': {
        '1': [
          {'startTime': '2024-01-01T09:00:00.000Z'},
        ],
      },
    },
  };
  String json(Object? o) => jsonEncode(o);

  test('[capture copy] later changes to the document given do not reach the '
      'snapshot', () async {
    final r = repo();
    final given = doc();
    final expected = json(given);
    await r.capture(providerId: 'demo', doc: given, capturedAt: t0);

    given['name'] = 'DEFACED';
    (given['services'] as List).add({'id': 's9'});
    ((given['services'] as List).first as Map)['price'] = 1.0;
    (((given['availability'] as Map)['weeklySchedule'] as Map)['1'] as List)
        .clear();

    expect(
      json((await r.read())!.doc),
      expected,
      reason: '[capture copy] the snapshot followed the document it was given',
    );
  });

  test('[read copy] changes to one read do not reach the next', () async {
    final r = repo();
    await r.capture(providerId: 'demo', doc: doc(), capturedAt: t0);
    final expected = json((await r.read())!.doc);

    final first = (await r.read())!.doc;
    first['name'] = 'DEFACED';
    (first['services'] as List).add({'id': 's9'});
    ((first['services'] as List).first as Map)['price'] = 1.0;

    expect(
      json((await r.read())!.doc),
      expected,
      reason: '[read copy] a read handed out the stored snapshot itself',
    );
  });

  test('[clock] markReset moves the clock; a second capture replaces the '
      'first and restarts it', () async {
    final r = repo();
    await r.capture(providerId: 'demo', doc: doc(), capturedAt: t0);
    var s = (await r.read())!;
    expect(s.capturedAt, t0, reason: '[clock] capturedAt');
    expect(s.lastResetAt, t0, reason: '[clock] a capture restarts the clock');

    final t1 = t0.add(const Duration(days: 7));
    await r.markReset(t1);
    expect((await r.read())!.lastResetAt, t1, reason: '[clock] markReset');

    final t2 = t1.add(const Duration(days: 1));
    await r.capture(
      providerId: 'demo2',
      doc: {'name': 'Autre'},
      capturedAt: t2,
    );
    s = (await r.read())!;
    expect(s.providerId, 'demo2', reason: '[clock] replaced: providerId');
    expect(s.doc, {'name': 'Autre'}, reason: '[clock] replaced: doc');
    expect(s.capturedAt, t2, reason: '[clock] replaced: capturedAt');
    expect(s.lastResetAt, t2, reason: '[clock] a capture restarts the clock');
  });
}
