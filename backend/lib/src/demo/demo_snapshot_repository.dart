/// Storage for the demo salon's curated state (T69).
///
/// One row, ever: the snapshot captured after the owner curates the demo
/// salon through the real app, plus the reset bookkeeping. Design:
/// docs/design/backend-demo-review-account.md §4, §6.2.
library;

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

class InMemoryDemoSnapshotRepository implements DemoSnapshotRepository {
  DemoSnapshot? _row;

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
      doc: Map<String, dynamic>.from(doc),
      capturedAt: capturedAt,
      lastResetAt: capturedAt,
    );
  }

  @override
  Future<DemoSnapshot?> read() async => _row;

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
