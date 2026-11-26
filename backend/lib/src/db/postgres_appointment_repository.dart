import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../appointments/appointment_repository.dart';

/// Postgres-backed [AppointmentRepository]. Columns mirror the `Appointment`
/// DTO; `service_ids` is jsonb; times are UTC. `create` relies on the partial
/// unique index `appointments_slot_unique` (`ON CONFLICT DO NOTHING`) for
/// atomic double-booking prevention — a concurrent insert for the same
/// (provider, start) returns no row → null. Parameterized throughout.
///
/// `currency` is the booking's own stamp, written once and returned by every
/// read; `update` refuses it, which is the immutability rule
/// (docs/design/appointment-currency-stamp.md §3.4). Every key the booking
/// service writes must come back — `appointment_repository_contract.dart`
/// holds both twins to it.
///
/// `update` writes only [kAppointmentUpdatableKeys] and refuses anything else
/// before any SQL, as the in-memory twin does
/// (docs/design/appointment-twin-update.md §5.2).
///
/// Since migration 0052 (R1, docs/design/pro-revenue-analytics.md §8.1) a
/// booking also keeps `service_lines` (what each prestation was sold as),
/// `artist_name_kept` and `channel`. NULL in all three is « made before R1 »,
/// never a value. **`service_lines` is the list itself, not `jsonEncode`d:**
/// `service_ids` is encoded first and then again by the `:jsonb` parameter,
/// which stores a JSON string — and SQL cannot read a string as an array.
/// The column refuses one (its CHECK).
class PostgresAppointmentRepository implements AppointmentRepository {
  PostgresAppointmentRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<int> wipeForProvider(String providerId) async {
    final r = await _pool.execute(
      Sql.named('DELETE FROM appointments WHERE provider_id = @p'),
      parameters: {'p': providerId},
    );
    return r.affectedRows;
  }

  @override
  Future<Map<String, dynamic>?> create(Map<String, dynamic> a) async {
    final start = DateTime.parse(a['appointmentDate'] as String);
    final durationMinutes = (a['durationMinutes'] as num?)?.toInt() ?? 30;
    try {
      final result = await _pool.execute(
        Sql.named(
          'INSERT INTO appointments '
          '(id, user_id, provider_id, service_ids, artist_id, '
          'appointment_date, duration_minutes, ends_at, status, total_price, '
          'deposit_amount, balance_due, cancellation_window_hours, '
          'client_name, client_phone, notes, deposit_screenshot_url, '
          'created_at, currency, service_lines, artist_name_kept, channel) '
          'VALUES (@id, @user_id, @provider_id, @service_ids:jsonb, '
          '@artist_id:text, @appointment_date:timestamptz, @duration_minutes, '
          '@ends_at:timestamptz, @status, @total_price, @deposit_amount, '
          '@balance_due, @cancellation_window_hours, @client_name:text, '
          '@client_phone:text, @notes:text, @deposit_screenshot_url:text, '
          '@created_at:timestamptz, @currency:text, '
          '@service_lines:jsonb, @artist_name_kept:text, @channel:text) '
          'RETURNING *',
        ),
        parameters: {
          'id': a['id'],
          'user_id': a['userId'],
          'provider_id': a['providerId'],
          'service_ids': jsonEncode(a['serviceIds']),
          'artist_id': a['artistId'],
          'appointment_date': start,
          'duration_minutes': durationMinutes,
          'ends_at': start.add(Duration(minutes: durationMinutes)),
          'status': a['status'],
          'total_price': (a['totalPrice'] as num).toDouble(),
          'deposit_amount': (a['depositAmount'] as num?)?.toDouble() ?? 0,
          'balance_due': (a['balanceDue'] as num?)?.toDouble() ?? 0,
          'cancellation_window_hours': a['cancellationWindowHours'] ?? 24,
          'client_name': a['clientName'],
          'client_phone': a['clientPhone'],
          'notes': a['notes'],
          'deposit_screenshot_url': a['depositScreenshotUrl'],
          'created_at': DateTime.parse(a['createdAt'] as String),
          // No default here: the booking service is the authority. A missing
          // stamp is refused by the column itself (23502) since 0049 (B14.2).
          'currency': a['currency'],
          // The list as it is: the parameter encodes it once, into an array.
          'service_lines': a['serviceLines'],
          'artist_name_kept': a['artistNameKept'],
          'channel': a['channel'],
        },
      );
      if (result.isEmpty) return null;
      return _toDto(result.first.toColumnMap());
    } on ServerException catch (e) {
      // Per-artist guards (migration 0026): exact-start unique (23505) or
      // duration-overlap exclusion (23P01) → the slot is taken.
      if (e.code == '23P01' || e.code == '23505') return null;
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    String? status,
    String? matchPhone,
  }) async {
    final phone = (matchPhone != null && matchPhone.isNotEmpty)
        ? matchPhone
        : null;
    final result = await _pool.execute(
      Sql.named(
        'SELECT * FROM appointments WHERE '
        '(user_id = @u OR (@phone::text IS NOT NULL AND client_phone = @phone)) '
        '${status == null ? '' : 'AND status = @s '}'
        'ORDER BY appointment_date DESC',
      ),
      parameters: {
        'u': userId,
        'phone': phone,
        if (status != null) 's': status,
      },
    );
    return result.map((r) => _toDto(r.toColumnMap())).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> listForProvider(
    String providerId, {
    String? status,
  }) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT * FROM appointments WHERE provider_id = @p '
        '${status == null ? '' : 'AND status = @s '}'
        'ORDER BY appointment_date DESC',
      ),
      parameters: {'p': providerId, if (status != null) 's': status},
    );
    return result.map((r) => _toDto(r.toColumnMap())).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> confirmedInWindow(
    DateTime from,
    DateTime to,
  ) async {
    final result = await _pool.execute(
      Sql.named(
        "SELECT * FROM appointments WHERE status = 'confirmed' "
        'AND appointment_date > @from AND appointment_date <= @to '
        'ORDER BY appointment_date',
      ),
      parameters: {'from': from.toUtc(), 'to': to.toUtc()},
    );
    return result.map((r) => _toDto(r.toColumnMap())).toList();
  }

  @override
  Future<Map<String, dynamic>?> byId(String id) async {
    final result = await _pool.execute(
      Sql.named('SELECT * FROM appointments WHERE id = @id'),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    return _toDto(result.first.toColumnMap());
  }

  @override
  Future<Map<String, dynamic>?> update(
    String id,
    Map<String, dynamic> changes,
  ) async {
    // Before any SQL: a key the builder below does not know used to be
    // ignored without a word, and the in-memory twin kept it.
    checkAppointmentChanges(changes);
    final sets = <String>[];
    final params = <String, Object?>{'id': id};
    if (changes.containsKey('status')) {
      sets.add('status = @status');
      params['status'] = changes['status'];
    }
    if (changes.containsKey('appointmentDate')) {
      sets.add('appointment_date = @ad:timestamptz');
      params['ad'] = DateTime.parse(changes['appointmentDate'] as String);
    }
    if (changes.containsKey('endsAt')) {
      sets.add('ends_at = @ends_at:timestamptz');
      params['ends_at'] = DateTime.parse(changes['endsAt'] as String);
    }
    if (changes.containsKey('depositScreenshotUrl')) {
      sets.add('deposit_screenshot_url = @dsu:text');
      params['dsu'] = changes['depositScreenshotUrl'];
    }
    if (changes.containsKey('arrivedAt')) {
      sets.add('arrived_at = @arrived:timestamptz');
      params['arrived'] = changes['arrivedAt'] == null
          ? null
          : DateTime.parse(changes['arrivedAt'] as String);
    }
    if (changes.containsKey('artistId')) {
      sets.add('artist_id = @artist:text');
      params['artist'] = changes['artistId'];
    }
    if (changes.containsKey('artistNameKept')) {
      sets.add('artist_name_kept = @artist_name:text');
      params['artist_name'] = changes['artistNameKept'];
    }
    if (sets.isEmpty) return byId(id);
    try {
      final result = await _pool.execute(
        Sql.named(
          'UPDATE appointments SET ${sets.join(', ')} WHERE id = @id '
          'RETURNING *',
        ),
        parameters: params,
      );
      if (result.isEmpty) return null;
      return _toDto(result.first.toColumnMap());
    } on ServerException catch (e) {
      // Rescheduling onto an overlapping slot trips the exclusion (23P01) →
      // treat as "slot taken" (null); the lifecycle maps it to slot_unavailable.
      if (e.code == '23P01') return null;
      rethrow;
    }
  }

  Map<String, dynamic> _toDto(Map<String, dynamic> r) {
    final serviceIds = r['service_ids'];
    return {
      'id': r['id'],
      'userId': r['user_id'],
      'providerId': r['provider_id'],
      'serviceIds': serviceIds is String ? jsonDecode(serviceIds) : serviceIds,
      'artistId': r['artist_id'],
      'appointmentDate': (r['appointment_date'] as DateTime)
          .toUtc()
          .toIso8601String(),
      'durationMinutes': r['duration_minutes'],
      'status': r['status'],
      'totalPrice': (r['total_price'] as num).toDouble(),
      'depositAmount': (r['deposit_amount'] as num?)?.toDouble() ?? 0,
      'balanceDue': (r['balance_due'] as num?)?.toDouble() ?? 0,
      'cancellationWindowHours': r['cancellation_window_hours'],
      'clientName': r['client_name'],
      'clientPhone': r['client_phone'],
      'notes': r['notes'],
      'depositScreenshotUrl': r['deposit_screenshot_url'],
      'createdAt': (r['created_at'] as DateTime).toUtc().toIso8601String(),
      'arrivedAt': (r['arrived_at'] as DateTime?)?.toUtc().toIso8601String(),
      // NOT NULL since migration 0049 (B14.2): every stored booking has one.
      'currency': r['currency'],
      // R1 (migration 0052). NULL in each is « made before R1 »; the lines
      // are an array or NULL (the column's CHECK).
      'serviceLines': r['service_lines'],
      'artistNameKept': r['artist_name_kept'],
      'channel': r['channel'],
    };
  }

  // ---- Revenue analytics (R2, docs/design/pro-revenue-analytics.md §8.3) ---

  /// The narrow columns of a revenue row ([kRevenueRowKeys]).
  static const String _revenueColumns =
      'id, status, appointment_date, duration_minutes, artist_id, '
      'artist_name_kept, total_price, currency, user_id, channel, '
      'service_ids, service_lines';

  static Map<String, dynamic> _revenueRow(Map<String, dynamic> r) {
    final serviceIds = r['service_ids'];
    return {
      'id': r['id'],
      'status': r['status'],
      'appointmentDate': (r['appointment_date'] as DateTime)
          .toUtc()
          .toIso8601String(),
      'durationMinutes': r['duration_minutes'],
      'artistId': r['artist_id'],
      'artistNameKept': r['artist_name_kept'],
      'totalPrice': (r['total_price'] as num).toDouble(),
      'currency': r['currency'],
      'userId': r['user_id'],
      'channel': r['channel'],
      // The JSON string `create` stores, decoded as `_toDto` does; an
      // unreadable one reads as no prestation rather than failing the page.
      'serviceIds': switch (serviceIds) {
        final String text => _decodeOrNull(text),
        _ => serviceIds,
      },
      'serviceLines': r['service_lines'],
      if (r.containsKey('client_phone')) 'clientPhone': r['client_phone'],
    };
  }

  static Object? _decodeOrNull(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// **One JSON document for the whole range, not one row per booking.**
  /// The revenue fold reads up to ~29 000 rows (« Année » and the year
  /// before, a salon of 40 bookings a day — pro-revenue-analytics.md §11),
  /// and measured on that salon the driver's per-row, per-cell decoding was
  /// most of the time: ~110–130 ms a range for twelve columns, against
  /// ~75 ms for the same rows aggregated by `json_agg` and decoded at once
  /// (2026-11-26, Postgres 16; `test/db/revenue_analytics_budget_test.dart`
  /// holds the budget). Same rows, same keys, same order as the in-memory
  /// twin; `service_ids` decoded in SQL, both storage forms, an unreadable
  /// value read as null.
  @override
  Future<List<Map<String, dynamic>>> revenueRows(
    String providerId,
    DateTime fromUtc,
    DateTime toUtcExclusive,
  ) async {
    // On `appointments_provider_date_idx (provider_id, appointment_date)`.
    final result = await _pool.execute(
      Sql.named(
        'SELECT COALESCE(json_agg(json_build_array('
        'id, status, '
        '(extract(epoch FROM appointment_date) * 1000000)::bigint, '
        'duration_minutes, artist_id, artist_name_kept, total_price, '
        'currency, user_id, channel, $_serviceIdsDecoded, service_lines) '
        "ORDER BY appointment_date, id), '[]')::text "
        'FROM appointments '
        'WHERE provider_id = @p AND appointment_date >= @from:timestamptz '
        'AND appointment_date < @to:timestamptz',
      ),
      parameters: {
        'p': providerId,
        'from': fromUtc.toUtc(),
        'to': toUtcExclusive.toUtc(),
      },
    );
    final rows = jsonDecode(result.first.first! as String) as List<dynamic>;
    return [
      for (final r in rows.cast<List<dynamic>>())
        {
          'id': r[0],
          'status': r[1],
          'appointmentDate': DateTime.fromMicrosecondsSinceEpoch(
            (r[2] as num).toInt(),
            isUtc: true,
          ).toIso8601String(),
          'durationMinutes': r[3],
          'artistId': r[4],
          'artistNameKept': r[5],
          'totalPrice': (r[6] as num).toDouble(),
          'currency': r[7],
          'userId': r[8],
          'channel': r[9],
          'serviceIds': r[10],
          'serviceLines': r[11],
        },
    ];
  }

  /// `service_ids` as a jsonb array whatever its storage form: production
  /// writes a JSON STRING inside `jsonb` (`create` encodes, then the
  /// `:jsonb` parameter encodes again), so `service_ids` alone would match
  /// nothing — 4 of 4 rows read on 2026-11-25 (pro-revenue-analytics.md §19).
  /// The decode is `kAppointmentCurrencyBackfill`'s: nested `CASE`s, so the
  /// cast only sees text `pg_input_is_valid` accepted, and an unreadable
  /// value matches nothing instead of failing the page.
  static const String _serviceIdsDecoded =
      "CASE jsonb_typeof(service_ids) "
      "WHEN 'string' THEN CASE WHEN pg_input_is_valid(service_ids #>> '{}', "
      "'jsonb') THEN (service_ids #>> '{}')::jsonb END "
      'ELSE service_ids END';

  @override
  Future<({List<Map<String, dynamic>> items, int total})> revenueLedger(
    String providerId, {
    required DateTime fromUtc,
    required DateTime toUtcExclusive,
    required RevenueLedgerStatus status,
    required DateTime asOf,
    required int limit,
    required int offset,
    String? artistId,
    String? serviceId,
    String? channel,
  }) async {
    const end =
        "appointment_date + COALESCE(duration_minutes, 0) * interval '1 minute'";
    final where = <String>[
      'provider_id = @p',
      'appointment_date >= @from:timestamptz',
      'appointment_date < @to:timestamptz',
      switch (status) {
        RevenueLedgerStatus.completed => "status = 'completed'",
        RevenueLedgerStatus.noShow => "status = 'noShow'",
        RevenueLedgerStatus.cancelled => "status = 'cancelled'",
        RevenueLedgerStatus.upcoming =>
          "status = 'confirmed' AND $end >= @as_of:timestamptz",
        RevenueLedgerStatus.toClose =>
          "status = 'confirmed' AND $end < @as_of:timestamptz",
      },
    ];
    final params = <String, Object?>{
      'p': providerId,
      'from': fromUtc.toUtc(),
      'to': toUtcExclusive.toUtc(),
    };
    if (status == RevenueLedgerStatus.upcoming ||
        status == RevenueLedgerStatus.toClose) {
      params['as_of'] = asOf.toUtc();
    }
    if (artistId != null) {
      if (artistId == 'none') {
        where.add("(artist_id IS NULL OR artist_id = '')");
      } else {
        where.add('artist_id = @artist:text');
        params['artist'] = artistId;
      }
    }
    if (channel != null) {
      where.add(
        "COALESCE(channel, CASE WHEN user_id = 'manual' THEN 'salon' "
        "ELSE 'online' END) = @channel:text",
      );
      params['channel'] = channel;
    }
    if (serviceId != null) {
      where.add(
        'jsonb_contains($_serviceIdsDecoded, '
        'jsonb_build_array(@service:text))',
      );
      params['service'] = serviceId;
    }
    final filter = where.join(' AND ');
    final order = status == RevenueLedgerStatus.upcoming
        ? 'appointment_date ASC, id ASC'
        : 'appointment_date DESC, id ASC';
    final count = await _pool.execute(
      Sql.named('SELECT COUNT(*)::int FROM appointments WHERE $filter'),
      parameters: params,
    );
    final page = await _pool.execute(
      Sql.named(
        'SELECT $_revenueColumns, client_phone FROM appointments '
        'WHERE $filter ORDER BY $order LIMIT @limit OFFSET @offset',
      ),
      parameters: {...params, 'limit': limit, 'offset': offset},
    );
    return (
      items: [for (final r in page) _revenueRow(r.toColumnMap())],
      total: count.first.first! as int,
    );
  }

  @override
  Future<bool> hasCompleted(String providerId) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT EXISTS (SELECT 1 FROM appointments '
        "WHERE provider_id = @p AND status = 'completed')",
      ),
      parameters: {'p': providerId},
    );
    return result.first.first! as bool;
  }

  @override
  Future<Map<String, int>> countsByStatus() async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT status, COUNT(*)::int AS n FROM appointments GROUP BY status',
      ),
    );
    return {
      for (final r in rows)
        (r.toColumnMap()['status'] as String): r.toColumnMap()['n'] as int,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> completedForAnalytics(
    DateTime from,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        "SELECT provider_id, appointment_date FROM appointments "
        "WHERE status = 'completed' AND appointment_date >= @from",
      ),
      parameters: {'from': from.toUtc()},
    );
    return [
      for (final r in rows)
        {
          'providerId': r.toColumnMap()['provider_id'],
          'appointmentDate': (r.toColumnMap()['appointment_date'] as DateTime)
              .toUtc()
              .toIso8601String(),
        },
    ];
  }

  @override
  Future<List<String>> anonymizeUser(String userId) async {
    // One round-trip, and deliberately so. Postgres has no `RETURNING OLD.*`,
    // and the deposit keys must be read BEFORE the column is cleared — a CTE
    // reads the pre-statement snapshot, so "the key I returned" and "the key I
    // cleared" are the same set by construction rather than by luck.
    final rows = await _pool.execute(
      Sql.named('''
WITH victims AS (
  SELECT deposit_screenshot_url AS key FROM appointments
   WHERE user_id = @uid AND deposit_screenshot_url IS NOT NULL
), cleared AS (
  UPDATE appointments
     SET client_name = NULL, client_phone = NULL, notes = NULL,
         deposit_screenshot_url = NULL
   WHERE user_id = @uid
)
SELECT key FROM victims'''),
      parameters: {'uid': userId},
    );
    return [
      for (final r in rows)
        if (r[0] case final String k) k,
    ];
  }
}
