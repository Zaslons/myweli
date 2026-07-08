/// Salon-scoped audit trail (module `clients` C1 — threat T46/T39; the
/// `access` module's member events reuse it in A2). Append-only; entries are
/// `{id, providerId, actorAccountId, action, targetId?, meta, createdAt}`.
/// NEVER logs client PII in `meta` beyond the search query.
abstract interface class ProviderAuditLogRepository {
  Future<void> log({
    required String providerId,
    required String actorAccountId,
    required String action,
    String? targetId,
    Map<String, dynamic> meta,
  });

  /// Newest first (owner-facing viewer lands with `access` A5; tests use it).
  Future<List<Map<String, dynamic>>> entriesFor(String providerId, {int limit});
}

class InMemoryProviderAuditLogRepository implements ProviderAuditLogRepository {
  final List<Map<String, dynamic>> _entries = [];
  int _seq = 0;

  @override
  Future<void> log({
    required String providerId,
    required String actorAccountId,
    required String action,
    String? targetId,
    Map<String, dynamic> meta = const {},
  }) async {
    _entries.add({
      'id': 'audit_${++_seq}',
      'providerId': providerId,
      'actorAccountId': actorAccountId,
      'action': action,
      'targetId': targetId,
      'meta': Map<String, dynamic>.of(meta),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> entriesFor(
    String providerId, {
    int limit = 100,
  }) async {
    return [
      for (final e in _entries.reversed)
        if (e['providerId'] == providerId) Map.of(e),
    ].take(limit).toList();
  }
}
