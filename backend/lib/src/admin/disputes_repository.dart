/// Admin-recorded dispute cases on a booking. Myweli holds no funds, so a
/// dispute is a **record + resolution** (advisory + consequence), never a
/// money movement. Design: docs/design/admin-console.md §12.
abstract interface class DisputesRepository {
  Future<Map<String, dynamic>> create({
    required String appointmentId,
    required String openedBy,
    required String reason,
  });

  Future<({List<Map<String, dynamic>> items, int total})> list({
    String? status,
    int page,
    int pageSize,
  });

  Future<Map<String, dynamic>?> byId(String id);

  /// Mark a dispute resolved with [resolution]; returns it, or null if absent.
  Future<Map<String, dynamic>?> resolve(
    String id, {
    required String resolution,
    required String resolvedBy,
  });
}

class InMemoryDisputesRepository implements DisputesRepository {
  final List<Map<String, dynamic>> _rows = [];
  var _seq = 0;

  @override
  Future<Map<String, dynamic>> create({
    required String appointmentId,
    required String openedBy,
    required String reason,
  }) async {
    final row = {
      'id': 'dispute_${_seq++}',
      'appointmentId': appointmentId,
      'openedBy': openedBy,
      'status': 'open',
      'reason': reason,
      'resolution': null,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'resolvedBy': null,
      'resolvedAt': null,
    };
    _rows.add(row);
    return row;
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> list({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final all = _rows
        .where((r) => status == null || r['status'] == status)
        .toList()
        .reversed
        .toList();
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <Map<String, dynamic>>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (items: items, total: all.length);
  }

  @override
  Future<Map<String, dynamic>?> byId(String id) async {
    for (final r in _rows) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> resolve(
    String id, {
    required String resolution,
    required String resolvedBy,
  }) async {
    final row = await byId(id);
    if (row == null) return null;
    row
      ..['status'] = 'resolved'
      ..['resolution'] = resolution
      ..['resolvedBy'] = resolvedBy
      ..['resolvedAt'] = DateTime.now().toUtc().toIso8601String();
    return row;
  }
}
