import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../providers_repository.dart';
import 'migrations.dart' show insertProviderAvailability;

/// Postgres-backed [ProvidersRepository].
///
/// The provider core lives as a `jsonb` document (+ indexed columns for
/// filter/sort), but **services and availability are normalized** into their own
/// tables (migration `0005`). This repository **reassembles** the full provider
/// DTO — core `data` + `services` + `availability` — on every read, so the
/// contract, the slot engine, and the booking service are unchanged at their
/// boundary. List reads batch the catalogue lookups (`IN (…)`) → no N+1.
/// (Design: docs/design/provider-services-availability-backend.md.)
class PostgresProvidersRepository implements ProvidersRepository {
  PostgresProvidersRepository(this._pool);

  final Pool<void> _pool;

  /// Placeholder date for reconstructed `TimeSlot`s — only the time-of-day is
  /// significant (Abidjan is UTC+0; the slot engine uses hour/minute).
  static const _canonicalDate = '2024-01-01';

  @override
  Future<List<Map<String, dynamic>>> query({
    String? q,
    String? commune,
    String? category,
  }) async {
    final conditions = <String>[];
    final parameters = <String, Object?>{};
    if (category != null && category.isNotEmpty) {
      conditions.add('category = @category');
      parameters['category'] = category;
    }
    if (commune != null && commune.isNotEmpty) {
      conditions.add('commune = @commune');
      parameters['commune'] = commune;
    }
    if (q != null && q.isNotEmpty) {
      conditions.add(
        '(name ILIKE @q OR description ILIKE @q OR address ILIKE @q)',
      );
      parameters['q'] = '%$q%';
    }
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = await _pool.execute(
      Sql.named('SELECT data FROM providers $where ORDER BY rating DESC'),
      parameters: parameters,
    );
    final docs = rows.map(_data).toList();
    if (docs.isEmpty) return docs;

    final ids = [for (final d in docs) d['id'] as String];
    final services = await _servicesByProvider(ids);
    final availability = await _availabilityByProvider(ids);
    for (final d in docs) {
      final id = d['id'] as String;
      d['services'] = services[id] ?? const <Map<String, dynamic>>[];
      d['availability'] = availability[id] ?? _emptyAvailability(id);
    }
    return docs;
  }

  @override
  Future<Map<String, dynamic>?> byId(String id) async {
    final result = await _pool.execute(
      Sql.named('SELECT data FROM providers WHERE id = @id'),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    final doc = _data(result.first);
    final services = await _servicesByProvider([id]);
    final availability = await _availabilityByProvider([id]);
    doc['services'] = services[id] ?? const <Map<String, dynamic>>[];
    doc['availability'] = availability[id] ?? _emptyAvailability(id);
    return doc;
  }

  // ---- writes (PR 2) --------------------------------------------------------

  @override
  Future<Map<String, dynamic>?> addService(
    String providerId,
    Map<String, dynamic> service,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        'INSERT INTO provider_services '
        '(id, provider_id, name, description, price, price_max, '
        'duration_minutes, duration_variants, artist_ids, active) '
        'VALUES (@id, @pid, @name, @desc, @price, @price_max, @dur, '
        '@variants:jsonb, @artists:jsonb, @active) RETURNING *',
      ),
      parameters: {
        'id': service['id'],
        'pid': providerId,
        'name': service['name'],
        'desc': service['description'] ?? '',
        'price': (service['price'] as num).toDouble(),
        'price_max': (service['priceMax'] as num?)?.toDouble(),
        'dur': (service['durationMinutes'] as num).toInt(),
        'variants': jsonEncode(service['durationVariants'] ?? const {}),
        'artists': jsonEncode(service['artistIds'] ?? const []),
        'active': service['active'] as bool? ?? true,
      },
    );
    return _serviceDto(rows.first.toColumnMap());
  }

  @override
  Future<Map<String, dynamic>?> updateService(
    String providerId,
    String serviceId,
    Map<String, dynamic> changes,
  ) async {
    final sets = <String>[];
    final params = <String, Object?>{'sid': serviceId, 'pid': providerId};
    void put(String key, String column, Object? value, {String cast = ''}) {
      sets.add('$column = @$key$cast');
      params[key] = value;
    }

    if (changes.containsKey('name')) put('name', 'name', changes['name']);
    if (changes.containsKey('description')) {
      put('desc', 'description', changes['description']);
    }
    if (changes.containsKey('price')) {
      put('price', 'price', (changes['price'] as num).toDouble());
    }
    if (changes.containsKey('priceMax')) {
      put('price_max', 'price_max', (changes['priceMax'] as num?)?.toDouble());
    }
    if (changes.containsKey('durationMinutes')) {
      put(
        'dur',
        'duration_minutes',
        (changes['durationMinutes'] as num).toInt(),
      );
    }
    if (changes.containsKey('durationVariants')) {
      put(
        'variants',
        'duration_variants',
        jsonEncode(changes['durationVariants']),
        cast: ':jsonb',
      );
    }
    if (changes.containsKey('artistIds')) {
      put(
        'artists',
        'artist_ids',
        jsonEncode(changes['artistIds']),
        cast: ':jsonb',
      );
    }
    if (changes.containsKey('active')) {
      put('active', 'active', changes['active']);
    }

    final sql = sets.isEmpty
        ? 'SELECT * FROM provider_services WHERE id = @sid AND provider_id = @pid'
        : 'UPDATE provider_services SET ${sets.join(', ')} '
              'WHERE id = @sid AND provider_id = @pid RETURNING *';
    final rows = await _pool.execute(Sql.named(sql), parameters: params);
    if (rows.isEmpty) return null;
    return _serviceDto(rows.first.toColumnMap());
  }

  @override
  Future<bool> deleteService(String providerId, String serviceId) async {
    final res = await _pool.execute(
      Sql.named(
        'DELETE FROM provider_services WHERE id = @sid AND provider_id = @pid',
      ),
      parameters: {'sid': serviceId, 'pid': providerId},
    );
    return res.affectedRows > 0;
  }

  @override
  Future<Map<String, dynamic>?> replaceAvailability(
    String providerId,
    Map<String, dynamic> availability,
  ) async {
    await _pool.runTx((tx) async {
      for (final t in const [
        'provider_working_hours',
        'provider_breaks',
        'provider_blocked_dates',
        'provider_availability',
      ]) {
        await tx.execute(
          Sql.named('DELETE FROM $t WHERE provider_id = @pid'),
          parameters: {'pid': providerId},
        );
      }
      await insertProviderAvailability(tx, providerId, availability);
    });
    return (await _availabilityByProvider([providerId]))[providerId];
  }

  @override
  Future<List<String>?> updateGallery(
    String providerId,
    List<String> imageUrls,
  ) {
    // `imageUrls` lives in the core `data` document; read-modify-write the whole
    // blob (it's stored as a JSON-string scalar, so jsonb operators don't
    // apply), atomically under a row lock.
    return _pool.runTx<List<String>?>((tx) async {
      final rows = await tx.execute(
        Sql.named('SELECT data FROM providers WHERE id = @id FOR UPDATE'),
        parameters: {'id': providerId},
      );
      if (rows.isEmpty) return null;
      final data = _data(rows.first);
      data['imageUrls'] = imageUrls;
      await tx.execute(
        Sql.named('UPDATE providers SET data = @data:jsonb WHERE id = @id'),
        parameters: {'id': providerId, 'data': jsonEncode(data)},
      );
      return List<String>.from(imageUrls);
    });
  }

  @override
  Future<Map<String, dynamic>?> updateDepositPolicy(
    String providerId,
    Map<String, dynamic> fields,
  ) {
    // Deposit-policy fields live in the core `data` document; merge them in via
    // an atomic read-modify-write (same pattern as updateGallery).
    return _pool.runTx<Map<String, dynamic>?>((tx) async {
      final rows = await tx.execute(
        Sql.named('SELECT data FROM providers WHERE id = @id FOR UPDATE'),
        parameters: {'id': providerId},
      );
      if (rows.isEmpty) return null;
      final data = _data(rows.first);
      data.addAll(fields);
      await tx.execute(
        Sql.named('UPDATE providers SET data = @data:jsonb WHERE id = @id'),
        parameters: {'id': providerId, 'data': jsonEncode(data)},
      );
      return Map<String, dynamic>.from(fields);
    });
  }

  @override
  Future<bool> updateRatings(
    String providerId, {
    required double rating,
    required int reviewCount,
    Map<String, ({double rating, int count})> artists = const {},
  }) {
    // Denormalized ratings live in `data` (+ the indexed `rating` column);
    // read-modify-write the whole blob atomically (like updateGallery).
    return _pool.runTx<bool>((tx) async {
      final rows = await tx.execute(
        Sql.named('SELECT data FROM providers WHERE id = @id FOR UPDATE'),
        parameters: {'id': providerId},
      );
      if (rows.isEmpty) return false;
      final data = _data(rows.first);
      data['rating'] = rating;
      data['reviewCount'] = reviewCount;
      for (final a in (data['artists'] as List?) ?? const []) {
        final m = a as Map<String, dynamic>;
        final agg = artists[m['id']];
        if (agg != null) {
          m['rating'] = agg.rating;
          m['reviewCount'] = agg.count;
        }
      }
      await tx.execute(
        Sql.named(
          'UPDATE providers SET data = @data:jsonb, rating = @rating '
          'WHERE id = @id',
        ),
        parameters: {
          'id': providerId,
          'data': jsonEncode(data),
          'rating': rating,
        },
      );
      return true;
    });
  }

  @override
  Future<Map<String, dynamic>?> addArtist(
    String providerId,
    Map<String, dynamic> artist,
  ) => _mutateArtists(providerId, (artists) {
    artists.add(artist);
    return artist;
  });

  @override
  Future<Map<String, dynamic>?> updateArtist(
    String providerId,
    String artistId,
    Map<String, dynamic> changes,
  ) => _mutateArtists(providerId, (artists) {
    for (final a in artists) {
      if ((a as Map)['id'] == artistId) {
        a.addAll(changes);
        return Map<String, dynamic>.from(a);
      }
    }
    return null;
  });

  @override
  Future<bool> deleteArtist(String providerId, String artistId) async {
    final removed = await _mutateArtists(providerId, (artists) {
      final before = artists.length;
      artists.removeWhere((a) => (a as Map)['id'] == artistId);
      return artists.length < before ? <String, dynamic>{} : null;
    });
    return removed != null;
  }

  /// Read-modify-write `data.artists` atomically; [mutate] returns the result
  /// (or null = "not found", which aborts as a no-op).
  Future<Map<String, dynamic>?> _mutateArtists(
    String providerId,
    Map<String, dynamic>? Function(List<dynamic> artists) mutate,
  ) {
    return _pool.runTx<Map<String, dynamic>?>((tx) async {
      final rows = await tx.execute(
        Sql.named('SELECT data FROM providers WHERE id = @id FOR UPDATE'),
        parameters: {'id': providerId},
      );
      if (rows.isEmpty) return null;
      final data = _data(rows.first);
      final artists = (data['artists'] as List?) ?? <dynamic>[];
      final result = mutate(artists);
      if (result == null) return null;
      data['artists'] = artists;
      await tx.execute(
        Sql.named('UPDATE providers SET data = @data:jsonb WHERE id = @id'),
        parameters: {'id': providerId, 'data': jsonEncode(data)},
      );
      return result;
    });
  }

  // ---- assembly -------------------------------------------------------------

  Future<Map<String, List<Map<String, dynamic>>>> _servicesByProvider(
    List<String> ids,
  ) async {
    final (clause, params) = _inClause(ids);
    final rows = await _pool.execute(
      Sql.named(
        'SELECT * FROM provider_services WHERE provider_id IN $clause '
        'ORDER BY created_at',
      ),
      parameters: params,
    );
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final m = r.toColumnMap();
      (out[m['provider_id'] as String] ??= []).add(_serviceDto(m));
    }
    return out;
  }

  Map<String, dynamic> _serviceDto(Map<String, dynamic> m) => {
    'id': m['id'],
    'name': m['name'],
    'description': m['description'],
    'price': (m['price'] as num).toDouble(),
    'priceMax': (m['price_max'] as num?)?.toDouble(),
    'durationMinutes': (m['duration_minutes'] as num).toInt(),
    'durationVariants': _json(m['duration_variants']) ?? const {},
    'providerId': m['provider_id'],
    'artistIds': _json(m['artist_ids']) ?? const [],
    'active': m['active'],
  };

  Future<Map<String, Map<String, dynamic>>> _availabilityByProvider(
    List<String> ids,
  ) async {
    final (clause, params) = _inClause(ids);
    final buffers = await _pool.execute(
      Sql.named(
        'SELECT provider_id, buffer_minutes FROM provider_availability '
        'WHERE provider_id IN $clause',
      ),
      parameters: params,
    );
    final schedule = await _windows('provider_working_hours', clause, params);
    final breaks = await _windows('provider_breaks', clause, params);
    final blocked = await _blockedDates(clause, params);

    final out = <String, Map<String, dynamic>>{};
    for (final r in buffers) {
      final m = r.toColumnMap();
      final pid = m['provider_id'] as String;
      out[pid] = {
        'providerId': pid,
        'bufferMinutes': (m['buffer_minutes'] as num).toInt(),
        'weeklySchedule': schedule[pid] ?? const <String, dynamic>{},
        'breaks': breaks[pid] ?? const <String, dynamic>{},
        'blockedDates': blocked[pid] ?? const <String>[],
      };
    }
    return out;
  }

  /// `{providerId: {weekday: [TimeSlot]}}` for a working-hours / breaks table.
  Future<Map<String, Map<String, List<Map<String, dynamic>>>>> _windows(
    String table,
    String clause,
    Map<String, Object?> params,
  ) async {
    final withAvail = table == 'provider_working_hours';
    final rows = await _pool.execute(
      Sql.named(
        "SELECT provider_id, weekday, to_char(start_time, 'HH24:MI') AS s, "
        "to_char(end_time, 'HH24:MI') AS e"
        '${withAvail ? ', is_available' : ''} '
        'FROM $table WHERE provider_id IN $clause',
      ),
      parameters: params,
    );
    final out = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final r in rows) {
      final m = r.toColumnMap();
      final pid = m['provider_id'] as String;
      final wd = (m['weekday'] as num).toInt().toString();
      ((out[pid] ??= {})[wd] ??= []).add(
        _slot(
          m['s'] as String,
          m['e'] as String,
          (m['is_available'] as bool?) ?? true,
        ),
      );
    }
    return out;
  }

  Future<Map<String, List<String>>> _blockedDates(
    String clause,
    Map<String, Object?> params,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        "SELECT provider_id, to_char(blocked_date, 'YYYY-MM-DD') AS d "
        'FROM provider_blocked_dates WHERE provider_id IN $clause',
      ),
      parameters: params,
    );
    final out = <String, List<String>>{};
    for (final r in rows) {
      final m = r.toColumnMap();
      (out[m['provider_id'] as String] ??= []).add('${m['d']}T00:00:00.000Z');
    }
    return out;
  }

  Map<String, dynamic> _slot(String start, String end, bool isAvailable) => {
    'startTime': '${_canonicalDate}T$start:00.000Z',
    'endTime': '${_canonicalDate}T$end:00.000Z',
    'isAvailable': isAvailable,
  };

  Map<String, dynamic> _emptyAvailability(String id) => {
    'providerId': id,
    'bufferMinutes': 0,
    'weeklySchedule': const <String, dynamic>{},
    'breaks': const <String, dynamic>{},
    'blockedDates': const <String>[],
  };

  /// `(IN-clause, params)` with one placeholder per id (avoids array-typing).
  (String, Map<String, Object?>) _inClause(List<String> ids) {
    final names = <String>[];
    final params = <String, Object?>{};
    for (var i = 0; i < ids.length; i++) {
      names.add('@p$i');
      params['p$i'] = ids[i];
    }
    return ('(${names.join(', ')})', params);
  }

  /// `jsonb` decodes to a Map/List via the driver; tolerate a String too.
  Map<String, dynamic> _data(ResultRow row) {
    final data = row.toColumnMap()['data'];
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data as Map);
  }

  Object? _json(Object? v) => v is String ? jsonDecode(v) : v;
}
