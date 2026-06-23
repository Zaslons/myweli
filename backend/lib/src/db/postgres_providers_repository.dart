import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../providers_repository.dart';

/// Postgres-backed [ProvidersRepository]. Each provider is stored as a `jsonb`
/// document (the full `Provider` DTO) plus indexed columns for filtering/sort,
/// so the read slice maps 1:1 to the contract without decomposing the nested
/// model. Parameterized queries throughout (no string interpolation of input).
class PostgresProvidersRepository implements ProvidersRepository {
  PostgresProvidersRepository(this._pool);

  final Pool<void> _pool;

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
    final result = await _pool.execute(
      Sql.named('SELECT data FROM providers $where ORDER BY rating DESC'),
      parameters: parameters,
    );
    return result.map(_data).toList();
  }

  @override
  Future<Map<String, dynamic>?> byId(String id) async {
    final result = await _pool.execute(
      Sql.named('SELECT data FROM providers WHERE id = @id'),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    return _data(result.first);
  }

  /// `jsonb` is decoded by the driver to a Map; tolerate a String too.
  Map<String, dynamic> _data(ResultRow row) {
    final data = row.toColumnMap()['data'];
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data as Map);
  }
}
