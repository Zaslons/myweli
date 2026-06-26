import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../messaging/messaging_models.dart';
import '../messaging/messaging_outbox_repository.dart';

/// Postgres-backed outbound-message log (table `outbound_messages`, migration
/// `0015`). Design: docs/design/messaging-notifications.md §4.
class PostgresMessagingOutboxRepository implements MessagingOutboxRepository {
  PostgresMessagingOutboxRepository(this._pool);

  final Pool<void> _pool;

  @override
  Future<Map<String, dynamic>> append({
    required String id,
    required String recipientPhone,
    required MessageChannel channel,
    required MessageTemplate template,
    required Map<String, String> params,
    required String body,
    required DeliveryStatus status,
    String? providerMessageId,
  }) async {
    final rows = await _pool.execute(
      Sql.named(
        'INSERT INTO outbound_messages '
        '(id, recipient_phone, channel, template, params, body, status, '
        'provider_message_id) VALUES (@id, @to, @ch, @tpl, @params:jsonb, '
        '@body, @status, @pid) RETURNING *',
      ),
      parameters: {
        'id': id,
        'to': recipientPhone,
        'ch': channel.name,
        'tpl': template.name,
        'params': jsonEncode(params),
        'body': body,
        'status': status.name,
        'pid': providerMessageId,
      },
    );
    return _dto(rows.first.toColumnMap());
  }

  @override
  Future<Map<String, dynamic>?> updateStatus(
    String providerMessageId,
    DeliveryStatus status,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        'UPDATE outbound_messages SET status = @status '
        'WHERE provider_message_id = @pid RETURNING *',
      ),
      parameters: {'pid': providerMessageId, 'status': status.name},
    );
    if (rows.isEmpty) return null;
    return _dto(rows.first.toColumnMap());
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> list({
    int page = 1,
    int pageSize = 50,
  }) async {
    final count = await _pool.execute(
      Sql.named('SELECT COUNT(*)::int AS n FROM outbound_messages'),
    );
    final rows = await _pool.execute(
      Sql.named(
        'SELECT * FROM outbound_messages '
        'ORDER BY created_at DESC LIMIT @ps OFFSET @off',
      ),
      parameters: {'ps': pageSize, 'off': (page - 1) * pageSize},
    );
    return (
      items: rows.map((r) => _dto(r.toColumnMap())).toList(),
      total: count.first.toColumnMap()['n'] as int,
    );
  }

  Map<String, dynamic> _dto(Map<String, dynamic> m) {
    final raw = m['params'];
    return {
      'id': m['id'],
      'recipientPhone': m['recipient_phone'],
      'channel': m['channel'],
      'template': m['template'],
      'params': raw is String ? jsonDecode(raw) : raw,
      'body': m['body'],
      'status': m['status'],
      'providerMessageId': m['provider_message_id'],
      'createdAt': (m['created_at'] as DateTime).toIso8601String(),
    };
  }
}
