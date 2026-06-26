/// One privileged admin action to record. Append-only.
typedef AuditEntry = ({
  String actorAdminId,
  String action,
  String targetType,
  String? targetId,
  String? reason,
  Map<String, dynamic> metadata,
});

/// Append-only log of every privileged admin action (who, what, target, reason).
/// The audit trail is the backbone of the admin trust boundary
/// (docs/BACKEND.md §7 T17). There is intentionally no update/delete.
abstract interface class AuditLogRepository {
  Future<void> append(AuditEntry entry);

  /// Newest-first, paginated, optionally filtered by actor / action.
  Future<({List<Map<String, dynamic>> items, int total})> list({
    int page,
    int pageSize,
    String? actor,
    String? action,
  });
}

class InMemoryAuditLogRepository implements AuditLogRepository {
  final List<Map<String, dynamic>> _rows = [];
  var _seq = 0;

  @override
  Future<void> append(AuditEntry entry) async {
    _rows.add({
      'id': 'audit_${_seq++}',
      'actorAdminId': entry.actorAdminId,
      'action': entry.action,
      'targetType': entry.targetType,
      'targetId': entry.targetId,
      'reason': entry.reason,
      'metadata': entry.metadata,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> list({
    int page = 1,
    int pageSize = 20,
    String? actor,
    String? action,
  }) async {
    final filtered = _rows
        .where((r) => actor == null || r['actorAdminId'] == actor)
        .where((r) => action == null || r['action'] == action)
        .toList()
        .reversed
        .toList();
    final start = (page - 1) * pageSize;
    final items = start >= filtered.length
        ? <Map<String, dynamic>>[]
        : filtered.sublist(start, (start + pageSize).clamp(0, filtered.length));
    return (items: items, total: filtered.length);
  }
}
