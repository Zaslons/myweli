import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../validation/salon_place_notice_repository.dart';

/// Postgres place-change notices (migration 0045 — decision 133,
/// docs/design/salon-go-live-approval.md §5.1). Parameterized queries only.
///
/// **Single winner by the row lock.** A save takes the salon's row
/// `FOR UPDATE` (inserting it first when it is new), decides in Dart with the
/// in-memory twin's own function ([placeNoticeAfterSave]) and writes, in one
/// transaction: two saves racing on a quiet hour serialise on the lock, and
/// the second reads the first one's e-mail time. A summary's claim is one
/// conditional UPDATE: a second tick waits on the same lock, re-reads the
/// row, finds nothing pending and claims nothing; a save counted since the
/// tick read the row changes `pending_count`, and the claim misses.
class PostgresSalonPlaceNoticeRepository implements SalonPlaceNoticeRepository {
  PostgresSalonPlaceNoticeRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<PlaceNoticeState?> get(String providerId) async {
    final r = await _pool.execute(
      Sql.named('SELECT * FROM salon_place_notices WHERE provider_id = @p'),
      parameters: {'p': providerId},
    );
    return r.isEmpty ? null : _fromRow(r.first.toColumnMap());
  }

  @override
  Future<PlaceNoticeTurn> recordSave(
    String providerId,
    DateTime now, {
    required Map<String, String?> after,
    required Iterable<String> fields,
  }) => _pool.runTx<PlaceNoticeTurn>((tx) async {
    // A first save makes the row; a racing first save waits on the insert,
    // then finds it and inserts nothing.
    await tx.execute(
      Sql.named(
        'INSERT INTO salon_place_notices (provider_id) VALUES (@p) '
        'ON CONFLICT (provider_id) DO NOTHING',
      ),
      parameters: {'p': providerId},
    );
    final r = await tx.execute(
      Sql.named(
        'SELECT * FROM salon_place_notices WHERE provider_id = @p FOR UPDATE',
      ),
      parameters: {'p': providerId},
    );
    // A row this transaction just made has never sent anything and owes
    // nothing: quiet, exactly as « no row » is for the in-memory twin.
    final d = placeNoticeAfterSave(
      _fromRow(r.first.toColumnMap()),
      providerId,
      now,
      after: after,
      fields: fields,
    );
    final n = d.next;
    await tx.execute(
      Sql.named(
        'UPDATE salon_place_notices SET '
        'last_sent_at = @sent:timestamptz, reported = @reported:jsonb, '
        'pending_count = @count:int4, pending_since = @since:timestamptz, '
        'pending_fields = @fields:jsonb '
        'WHERE provider_id = @p',
      ),
      parameters: {
        'p': providerId,
        'sent': n.lastSentAt?.toUtc(),
        // Raw values: the driver's jsonb codec encodes them (a jsonEncode
        // here would store a JSON string).
        'reported': n.reported,
        'count': n.pendingCount,
        'since': n.pendingSince?.toUtc(),
        'fields': n.pendingFields,
      },
    );
    return d.turn;
  });

  @override
  Future<List<String>> due(DateTime now, {int limit = 100}) async {
    final r = await _pool.execute(
      Sql.named(
        'SELECT provider_id FROM salon_place_notices '
        'WHERE pending_count > 0 '
        'AND (last_sent_at IS NULL OR last_sent_at <= @cutoff) '
        'ORDER BY pending_since, provider_id LIMIT @lim',
      ),
      parameters: {
        'cutoff': now.toUtc().subtract(kPlaceNoticeWindow),
        'lim': limit,
      },
    );
    return [for (final row in r) row.toColumnMap()['provider_id'] as String];
  }

  @override
  Future<PlaceSummaryClaim?> claimSummary(
    String providerId,
    DateTime now, {
    required Map<String, String?> current,
    required int seenSaves,
  }) async {
    // The row as it was is read under the lock the UPDATE then takes over;
    // the WHERE is re-checked on a row another tick just claimed, or a save
    // just counted, and matches nothing.
    final r = await _pool.execute(
      Sql.named(
        'WITH was AS ('
        ' SELECT provider_id, reported, pending_count, pending_since, '
        ' pending_fields FROM salon_place_notices '
        ' WHERE provider_id = @p AND pending_count > 0 '
        ' AND pending_count = @seen:int4 '
        ' AND (last_sent_at IS NULL OR last_sent_at <= @cutoff) '
        ' FOR UPDATE'
        ') '
        'UPDATE salon_place_notices n SET last_sent_at = @now, '
        'reported = @current:jsonb, pending_count = 0, pending_since = NULL, '
        "pending_fields = '[]'::jsonb "
        'FROM was WHERE n.provider_id = was.provider_id '
        'RETURNING was.reported AS was_reported, '
        'was.pending_count AS was_count, was.pending_since AS was_since, '
        'was.pending_fields AS was_fields',
      ),
      parameters: {
        'p': providerId,
        'now': now.toUtc(),
        'cutoff': now.toUtc().subtract(kPlaceNoticeWindow),
        'current': current,
        'seen': seenSaves,
      },
    );
    if (r.isEmpty) return null;
    final m = r.first.toColumnMap();
    return (
      reported: _place(m['was_reported']),
      saves: m['was_count'] as int,
      since: (m['was_since'] as DateTime).toUtc(),
      fields: _fields(m['was_fields']),
    );
  }

  @override
  Future<bool> dropPending(String providerId) async {
    final r = await _pool.execute(
      Sql.named(
        'UPDATE salon_place_notices SET pending_count = 0, '
        "pending_since = NULL, pending_fields = '[]'::jsonb "
        'WHERE provider_id = @p AND pending_count > 0 RETURNING provider_id',
      ),
      parameters: {'p': providerId},
    );
    return r.isNotEmpty;
  }

  @override
  Future<void> forget(String providerId) => _pool.execute(
    Sql.named('DELETE FROM salon_place_notices WHERE provider_id = @p'),
    parameters: {'p': providerId},
  );

  static PlaceNoticeState _fromRow(Map<String, dynamic> m) => PlaceNoticeState(
    providerId: m['provider_id'] as String,
    lastSentAt: (m['last_sent_at'] as DateTime?)?.toUtc(),
    reported: _place(m['reported']),
    pendingCount: m['pending_count'] as int,
    pendingSince: (m['pending_since'] as DateTime?)?.toUtc(),
    pendingFields: _fields(m['pending_fields']),
  );

  /// A jsonb value as the driver hands it back — decoded, or (defensively)
  /// still text.
  static Object? _json(Object? v) => v is String ? jsonDecode(v) : v;

  static Map<String, String?> _place(Object? v) {
    final m = _json(v);
    if (m is! Map) return const {};
    return {for (final e in m.entries) '${e.key}': e.value?.toString()};
  }

  static List<String> _fields(Object? v) {
    final l = _json(v);
    return l is List ? orderedPlaceFields(l.map((e) => '$e')) : const [];
  }
}
