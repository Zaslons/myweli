import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../appointments/appointment_repository.dart';

/// Postgres-backed [AppointmentRepository]. Columns mirror the `Appointment`
/// DTO; `service_ids` is jsonb; times are UTC. `create` relies on the partial
/// unique index `appointments_slot_unique` (`ON CONFLICT DO NOTHING`) for
/// atomic double-booking prevention — a concurrent insert for the same
/// (provider, start) returns no row → null. Parameterized throughout.
class PostgresAppointmentRepository implements AppointmentRepository {
  PostgresAppointmentRepository(this._pool);

  final Pool<void> _pool;

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
          'created_at) '
          'VALUES (@id, @user_id, @provider_id, @service_ids:jsonb, '
          '@artist_id:text, @appointment_date:timestamptz, @duration_minutes, '
          '@ends_at:timestamptz, @status, @total_price, @deposit_amount, '
          '@balance_due, @cancellation_window_hours, @client_name:text, '
          '@client_phone:text, @notes:text, @deposit_screenshot_url:text, '
          '@created_at:timestamptz) '
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
    };
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
}
