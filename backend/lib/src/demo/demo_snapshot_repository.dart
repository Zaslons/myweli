/// Storage for the demo salon's curated state (T69).
///
/// One row, ever: the snapshot captured after the owner curates the demo
/// salon through the real app, plus the reset bookkeeping. Design:
/// docs/design/backend-demo-review-account.md §4, §6.2.
library;

import 'dart:convert';

/// The single snapshot row.
typedef DemoSnapshot = ({
  String providerId,
  Map<String, dynamic> doc,
  DateTime capturedAt,
  DateTime? lastResetAt,
});

abstract interface class DemoSnapshotRepository {
  /// Replaces the snapshot (there is only ever one).
  Future<void> capture({
    required String providerId,
    required Map<String, dynamic> doc,
    required DateTime capturedAt,
  });

  /// The snapshot, or null if none was ever captured.
  Future<DemoSnapshot?> read();

  /// Records that a reset ran, for the 7-day due-gate.
  Future<void> markReset(DateTime at);
}

/// The in-memory twin keeps its OWN copy, through JSON, on the way in and on
/// every read — as Postgres's `jsonb` does. It used to keep `Map.from(doc)`,
/// a shallow copy that shared the live salon's lists, and to hand out that
/// same map: a reviewer's in-place edits then rewrote the snapshot itself
/// (C-M1, docs/design/demo-reset-restore.md §5.3, B16.2). A document that is
/// not JSON now fails at the capture on both twins alike.
class InMemoryDemoSnapshotRepository implements DemoSnapshotRepository {
  DemoSnapshot? _row;

  static Map<String, dynamic> _copy(Map<String, dynamic> doc) =>
      jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;

  @override
  Future<void> capture({
    required String providerId,
    required Map<String, dynamic> doc,
    required DateTime capturedAt,
  }) async {
    // A capture RESTARTS the reset clock: the freshly-curated state is by
    // definition clean, so the next reset is due a full window later.
    _row = (
      providerId: providerId,
      doc: _copy(doc),
      capturedAt: capturedAt,
      lastResetAt: capturedAt,
    );
  }

  @override
  Future<DemoSnapshot?> read() async {
    final r = _row;
    if (r == null) return null;
    return (
      providerId: r.providerId,
      doc: _copy(r.doc),
      capturedAt: r.capturedAt,
      lastResetAt: r.lastResetAt,
    );
  }

  @override
  Future<void> markReset(DateTime at) async {
    final r = _row;
    if (r == null) return;
    _row = (
      providerId: r.providerId,
      doc: r.doc,
      capturedAt: r.capturedAt,
      lastResetAt: at,
    );
  }
}
