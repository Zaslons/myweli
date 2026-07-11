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
  );
}
