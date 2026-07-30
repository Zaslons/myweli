import 'package:postgres/postgres.dart';

import '../access/membership_repository.dart';

/// Postgres memberships (module `access` §3, migration 0027). Same contract
/// as the in-memory twin; parameterized queries throughout.
class PostgresMembershipRepository implements MembershipRepository {
  PostgresMembershipRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<Member?> activeMember(String accountId, String providerId) async {
    final r = await _pool.execute(
      Sql.named(
        "SELECT * FROM provider_members WHERE account_id = @a "
        "AND provider_id = @p AND status = 'active' LIMIT 1",
      ),
      parameters: {'a': accountId, 'p': providerId},
    );
    if (r.isEmpty) return null;
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<Member?> firstActiveForAccount(String accountId) async {
    final r = await _pool.execute(
      Sql.named(
        "SELECT * FROM provider_members WHERE account_id = @a "
        "AND status = 'active' ORDER BY invited_at LIMIT 1",
      ),
      parameters: {'a': accountId},
    );
    if (r.isEmpty) return null;
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<List<Member>> listForAccount(String accountId) async {
    final r = await _pool.execute(
      Sql.named(
        'SELECT * FROM provider_members WHERE account_id = @a '
        'ORDER BY invited_at',
      ),
      parameters: {'a': accountId},
    );
    return [for (final row in r) _fromRow(row.toColumnMap())];
  }

  @override
  Future<List<Member>> listForProvider(String providerId) async {
    final r = await _pool.execute(
      Sql.named(
        'SELECT * FROM provider_members WHERE provider_id = @p '
        "ORDER BY (role = 'owner') DESC, invited_at",
      ),
      parameters: {'p': providerId},
    );
    return [for (final row in r) _fromRow(row.toColumnMap())];
  }

  @override
  Future<Member> ensureOwner({
    required String providerId,
    required String accountId,
    required String email,
  }) async {
    final existing = await activeMember(accountId, providerId);
    if (existing != null && existing.role == 'owner') return existing;
    final r = await _pool.execute(
      Sql.named(
        'INSERT INTO provider_members '
        '(id, provider_id, account_id, email, role, status, invited_at, '
        'accepted_at) '
        "VALUES ('mem_' || @a || '_' || @p, @p, @a, lower(@e), 'owner', "
        "'active', now(), now()) "
        'ON CONFLICT (provider_id, email) DO UPDATE SET '
        'account_id = excluded.account_id RETURNING *',
      ),
      parameters: {'a': accountId, 'p': providerId, 'e': email},
    );
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<Member> invite({
    required String providerId,
    required String email,
    required String role,
    required DateTime expiresAt,
    String? artistId,
    String? invitedBy,
  }) async {
    final r = await _pool.execute(
      Sql.named(
        'INSERT INTO provider_members '
        '(id, provider_id, email, role, artist_id, status, invited_by, '
        'invited_at, expires_at) '
        "VALUES ('mem_' || gen_random_uuid(), @p, lower(@e), @r, @a, "
        "'invited', @b, now(), @x) RETURNING *",
      ),
      parameters: {
        'p': providerId,
        'e': email,
        'r': role,
        'a': artistId,
        'b': invitedBy,
        'x': expiresAt,
      },
    );
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<Member?> byId(String memberId) async {
    final r = await _pool.execute(
      Sql.named('SELECT * FROM provider_members WHERE id = @id'),
      parameters: {'id': memberId},
    );
    if (r.isEmpty) return null;
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<List<Member>> pendingByEmail(String email) async {
    final r = await _pool.execute(
      Sql.named(
        'SELECT * FROM provider_members WHERE email = lower(@e) '
        "AND status = 'invited' "
        'AND (expires_at IS NULL OR expires_at > now()) '
        'ORDER BY invited_at',
      ),
      parameters: {'e': email},
    );
    return [for (final row in r) _fromRow(row.toColumnMap())];
  }

  @override
  Future<Member?> updateMember(
    String memberId, {
    String? role,
    String? artistId,
  }) async {
    final sets = <String>[];
    final params = <String, dynamic>{'id': memberId};
    if (role != null) {
      sets.add('role = @r');
      params['r'] = role;
    }
    if (artistId != null) {
      sets.add('artist_id = @a');
      params['a'] = artistId;
    }
    if (sets.isEmpty) return byId(memberId);
    final r = await _pool.execute(
      Sql.named(
        'UPDATE provider_members SET ${sets.join(', ')} '
        'WHERE id = @id RETURNING *',
      ),
      parameters: params,
    );
    if (r.isEmpty) return null;
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<Member?> revoke(String memberId) async {
    final r = await _pool.execute(
      Sql.named(
        "UPDATE provider_members SET status = 'revoked', revoked_at = "
        "COALESCE(revoked_at, now()) WHERE id = @id RETURNING *",
      ),
      parameters: {'id': memberId},
    );
    if (r.isEmpty) return null;
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<Member?> resendInvite(String memberId, DateTime newExpiresAt) async {
    final r = await _pool.execute(
      Sql.named(
        'UPDATE provider_members SET expires_at = @x, '
        'resends_left = resends_left - 1 '
        "WHERE id = @id AND status = 'invited' AND resends_left > 0 "
        'RETURNING *',
      ),
      parameters: {'id': memberId, 'x': newExpiresAt},
    );
    if (r.isEmpty) return null;
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<Member?> activate(String memberId, String accountId) async {
    final r = await _pool.execute(
      Sql.named(
        "UPDATE provider_members SET status = 'active', account_id = @a, "
        'accepted_at = now() WHERE id = @id RETURNING *',
      ),
      parameters: {'id': memberId, 'a': accountId},
    );
    if (r.isEmpty) return null;
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<void> decline(String memberId) async {
    await _pool.execute(
      Sql.named('DELETE FROM provider_members WHERE id = @id'),
      parameters: {'id': memberId},
    );
  }

  @override
  Future<void> revokeAllForAccount(String accountId) async {
    await _pool.execute(
      Sql.named(
        "UPDATE provider_members SET status = 'revoked', revoked_at = now() "
        "WHERE account_id = @a AND status != 'revoked'",
      ),
      parameters: {'a': accountId},
    );
  }

  Member _fromRow(Map<String, dynamic> r) => Member(
    id: r['id'] as String,
    providerId: r['provider_id'] as String,
    accountId: r['account_id'] as String?,
    email: r['email'] as String,
    role: r['role'] as String,
    artistId: r['artist_id'] as String?,
    status: r['status'] as String,
    invitedBy: r['invited_by'] as String?,
    invitedAt: r['invited_at'] as DateTime,
    acceptedAt: r['accepted_at'] as DateTime?,
    revokedAt: r['revoked_at'] as DateTime?,
    expiresAt: r['expires_at'] as DateTime?,
    resendsLeft: (r['resends_left'] as int?) ?? 3,
  );
}
