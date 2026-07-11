import 'package:postgres/postgres.dart';

import '../subscription/salon_subscription_repository.dart';

/// Postgres salon offers (migration 0028). Parameterized queries throughout.
class PostgresSalonSubscriptionRepository
    implements SalonSubscriptionRepository {
  PostgresSalonSubscriptionRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<SalonSubscriptionRow?> byProvider(String providerId) async {
    final r = await _pool.execute(
      Sql.named('SELECT * FROM provider_subscriptions WHERE provider_id = @p'),
      parameters: {'p': providerId},
    );
    if (r.isEmpty) return null;
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<SalonSubscriptionRow> create({
    required String providerId,
    required String tier,
    required DateTime trialEndsAt,
  }) async {
    final r = await _pool.execute(
      Sql.named(
        'INSERT INTO provider_subscriptions (provider_id, tier, trial_ends_at) '
        'VALUES (@p, @t, @e) '
        'ON CONFLICT (provider_id) DO UPDATE SET tier = excluded.tier, '
        'updated_at = now() RETURNING *',
      ),
      parameters: {'p': providerId, 't': tier, 'e': trialEndsAt},
    );
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<SalonSubscriptionRow?> update(
    String providerId, {
    String? tier,
    DateTime? paidUntil,
    DateTime? unpublishedAt,
    bool clearUnpublished = false,
  }) async {
    final sets = <String>['updated_at = now()'];
    final params = <String, dynamic>{'p': providerId};
    if (tier != null) {
      sets.add('tier = @t');
      params['t'] = tier;
    }
    if (paidUntil != null) {
      sets.add('paid_until = @u');
      params['u'] = paidUntil;
    }
    if (clearUnpublished) {
      sets.add('unpublished_at = NULL');
    } else if (unpublishedAt != null) {
      sets.add('unpublished_at = @n');
      params['n'] = unpublishedAt;
    }
    final r = await _pool.execute(
      Sql.named(
        'UPDATE provider_subscriptions SET ${sets.join(', ')} '
        'WHERE provider_id = @p RETURNING *',
      ),
      parameters: params,
    );
    if (r.isEmpty) return null;
    return _fromRow(r.first.toColumnMap());
  }

  @override
  Future<List<SalonSubscriptionRow>> all() async {
    final r = await _pool.execute('SELECT * FROM provider_subscriptions');
    return [for (final row in r) _fromRow(row.toColumnMap())];
  }

  @override
  Future<bool> markNoticeIfNew(String providerId, String kind) async {
    final r = await _pool.execute(
      Sql.named(
        'INSERT INTO subscription_notices (provider_id, kind) '
        'VALUES (@p, @k) ON CONFLICT DO NOTHING',
      ),
      parameters: {'p': providerId, 'k': kind},
    );
    return r.affectedRows > 0;
  }

  @override
  Future<void> clearNotices(String providerId) async {
    await _pool.execute(
      Sql.named('DELETE FROM subscription_notices WHERE provider_id = @p'),
      parameters: {'p': providerId},
    );
  }

  SalonSubscriptionRow _fromRow(Map<String, dynamic> r) => SalonSubscriptionRow(
    providerId: r['provider_id'] as String,
    tier: r['tier'] as String,
    trialEndsAt: r['trial_ends_at'] as DateTime,
    chosenAt: r['chosen_at'] as DateTime,
    paidUntil: r['paid_until'] as DateTime?,
    unpublishedAt: r['unpublished_at'] as DateTime?,
  );
}
