import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../clients/clients_repository.dart';

/// Postgres-backed [ClientsRepository] (tables `salon_clients` +
/// `salon_client_notes`, migration `0024`). `tags` is jsonb (the codebase
/// idiom, like `appointments.service_ids`); times are UTC; parameterized
/// throughout. Every query is provider-scoped in SQL (threat T45 — a foreign
/// clientId can never resolve).
class PostgresClientsRepository implements ClientsRepository {
  PostgresClientsRepository(this._pool);

  final Pool<void> _pool;

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  Future<({List<Map<String, dynamic>> items, int total})> list(
    String providerId, {
    String? query,
    String? tag,
    required int page,
    required int pageSize,
  }) async {
    final q = query?.trim() ?? '';
    final qDigits = _digits(q);
    final rows = await _pool.execute(
      Sql.named('''
SELECT *, COUNT(*) OVER() AS full_count FROM salon_clients
WHERE provider_id = @pid
  AND (@tag::text IS NULL OR tags @> to_jsonb(ARRAY[@tag::text]))
  AND (
    @q::text = ''
    OR display_name ILIKE '%' || @q || '%'
    OR (length(@digits::text) >= 2 AND phone LIKE '%' || @digits || '%')
  )
ORDER BY last_visit_at DESC NULLS LAST, created_at DESC
LIMIT @limit OFFSET @offset
'''),
      parameters: {
        'pid': providerId,
        'tag': (tag == null || tag.isEmpty) ? null : tag,
        'q': q,
        'digits': qDigits,
        'limit': pageSize,
        'offset': (page - 1) * pageSize,
      },
    );
    final total = rows.isEmpty
        ? 0
        : (rows.first.toColumnMap()['full_count'] as int);
    return (
      items: [for (final r in rows) _toDto(r.toColumnMap())],
      total: total,
    );
  }

  @override
  Future<List<String>> tagsFor(String providerId) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT DISTINCT jsonb_array_elements_text(tags) AS tag '
        'FROM salon_clients WHERE provider_id = @pid ORDER BY tag',
      ),
      parameters: {'pid': providerId},
    );
    return [for (final r in rows) r.toColumnMap()['tag'] as String];
  }

  @override
  Future<Map<String, dynamic>?> byId(String providerId, String clientId) =>
      _one(
        'SELECT * FROM salon_clients WHERE provider_id = @pid AND id = @id',
        {'pid': providerId, 'id': clientId},
      );

  @override
  Future<Map<String, dynamic>?> byPhone(String providerId, String phone) =>
      _one(
        'SELECT * FROM salon_clients WHERE provider_id = @pid '
        'AND phone = @phone',
        {'pid': providerId, 'phone': phone},
      );

  @override
  Future<Map<String, dynamic>?> byUserId(String providerId, String userId) =>
      _one(
        'SELECT * FROM salon_clients WHERE provider_id = @pid '
        'AND user_id = @uid',
        {'pid': providerId, 'uid': userId},
      );

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> client) async {
    final rows = await _pool.execute(
      Sql.named(
        'INSERT INTO salon_clients '
        '(id, provider_id, user_id, display_name, phone, tags, last_visit_at, '
        'created_at, updated_at) '
        'VALUES (@id, @pid, @uid:text, @name, @phone:text, @tags:jsonb, '
        '@last_visit:timestamptz, now(), now()) '
        // Concurrent booking-driven upserts: keep the existing row.
        'ON CONFLICT DO NOTHING RETURNING *',
      ),
      parameters: {
        'id': client['id'],
        'pid': client['providerId'],
        'uid': client['userId'],
        'name': client['displayName'],
        'phone': client['phone'],
        'tags': jsonEncode(client['tags'] ?? const <String>[]),
        'last_visit': client['lastVisitAt'] == null
            ? null
            : DateTime.parse(client['lastVisitAt'] as String),
      },
    );
    if (rows.isNotEmpty) return _toDto(rows.first.toColumnMap());
    // Conflict — return the existing row for that identity.
    final existing = client['userId'] != null
        ? await byUserId(
            client['providerId'] as String,
            client['userId'] as String,
          )
        : await byPhone(
            client['providerId'] as String,
            client['phone'] as String,
          );
    return existing ?? client;
  }

  @override
  Future<Map<String, dynamic>?> updateTags(
    String providerId,
    String clientId,
    List<String> tags,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        'UPDATE salon_clients SET tags = @tags:jsonb, updated_at = now() '
        'WHERE provider_id = @pid AND id = @id RETURNING *',
      ),
      parameters: {'tags': jsonEncode(tags), 'pid': providerId, 'id': clientId},
    );
    return rows.isEmpty ? null : _toDto(rows.first.toColumnMap());
  }

  @override
  Future<void> touchLastVisit(
    String providerId,
    String clientId,
    DateTime visitAt,
  ) async {
    await _pool.execute(
      Sql.named(
        'UPDATE salon_clients SET last_visit_at = @at, updated_at = now() '
        'WHERE provider_id = @pid AND id = @id '
        'AND (last_visit_at IS NULL OR last_visit_at < @at)',
      ),
      parameters: {'at': visitAt.toUtc(), 'pid': providerId, 'id': clientId},
    );
  }

  @override
  Future<Map<String, dynamic>> addNote(Map<String, dynamic> note) async {
    await _pool.execute(
      Sql.named(
        'INSERT INTO salon_client_notes '
        '(id, client_id, author_account_id, body, created_at) '
        'VALUES (@id, @cid, @author, @body, now())',
      ),
      parameters: {
        'id': note['id'],
        'cid': note['clientId'],
        'author': note['authorAccountId'],
        'body': note['body'],
      },
    );
    return note;
  }

  @override
  Future<List<Map<String, dynamic>>> notesFor(String clientId) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT * FROM salon_client_notes WHERE client_id = @cid '
        'ORDER BY created_at DESC, id DESC',
      ),
      parameters: {'cid': clientId},
    );
    return [for (final r in rows) _noteToDto(r.toColumnMap())];
  }

  @override
  Future<Map<String, dynamic>?> noteById(String clientId, String noteId) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT * FROM salon_client_notes WHERE client_id = @cid '
        'AND id = @id',
      ),
      parameters: {'cid': clientId, 'id': noteId},
    );
    return rows.isEmpty ? null : _noteToDto(rows.first.toColumnMap());
  }

  @override
  Future<bool> deleteNote(String clientId, String noteId) async {
    final result = await _pool.execute(
      Sql.named(
        'DELETE FROM salon_client_notes WHERE client_id = @cid AND id = @id',
      ),
      parameters: {'cid': clientId, 'id': noteId},
    );
    return result.affectedRows > 0;
  }

  @override
  Future<void> anonymizeUser(String userId) async {
    await _pool.execute(
      Sql.named(
        "UPDATE salon_clients SET user_id = NULL, display_name = 'Client', "
        'phone = NULL, updated_at = now() WHERE user_id = @uid',
      ),
      parameters: {'uid': userId},
    );
  }

  Future<Map<String, dynamic>?> _one(
    String sql,
    Map<String, dynamic> params,
  ) async {
    final rows = await _pool.execute(Sql.named(sql), parameters: params);
    return rows.isEmpty ? null : _toDto(rows.first.toColumnMap());
  }

  Map<String, dynamic> _toDto(Map<String, dynamic> row) => {
    'id': row['id'],
    'providerId': row['provider_id'],
    'userId': row['user_id'],
    'displayName': row['display_name'],
    'phone': row['phone'],
    'tags': switch (row['tags']) {
      final List<dynamic> l => l.cast<String>(),
      final String s => (jsonDecode(s) as List).cast<String>(),
      _ => const <String>[],
    },
    'lastVisitAt': (row['last_visit_at'] as DateTime?)
        ?.toUtc()
        .toIso8601String(),
    'createdAt': (row['created_at'] as DateTime).toUtc().toIso8601String(),
  };

  Map<String, dynamic> _noteToDto(Map<String, dynamic> row) => {
    'id': row['id'],
    'clientId': row['client_id'],
    'authorAccountId': row['author_account_id'],
    'body': row['body'],
    'createdAt': (row['created_at'] as DateTime).toUtc().toIso8601String(),
  };
}
