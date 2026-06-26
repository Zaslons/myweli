import 'messaging_models.dart';

/// One handed-off message (map DTO, like the other repos), shaped to the app's
/// `OutboundMessage`. Design: docs/design/messaging-notifications.md §4.
abstract interface class MessagingOutboxRepository {
  /// Records a message; returns the stored row (with its `id`, `createdAt`).
  Future<Map<String, dynamic>> append({
    required String id,
    required String recipientPhone,
    required MessageChannel channel,
    required MessageTemplate template,
    required Map<String, String> params,
    required String body,
    required DeliveryStatus status,
    String? providerMessageId,
  });

  /// Advances delivery status for a provider message id (the status webhook).
  /// Returns the updated row, or null if unknown.
  Future<Map<String, dynamic>?> updateStatus(
    String providerMessageId,
    DeliveryStatus status,
  );

  /// Recent messages (newest first), paginated — admin/debug.
  Future<({List<Map<String, dynamic>> items, int total})> list({
    int page,
    int pageSize,
  });
}

class InMemoryMessagingOutboxRepository implements MessagingOutboxRepository {
  final List<Map<String, dynamic>> _rows = [];

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
    final row = {
      'id': id,
      'recipientPhone': recipientPhone,
      'channel': channel.name,
      'template': template.name,
      'params': Map<String, String>.from(params),
      'body': body,
      'status': status.name,
      'providerMessageId': providerMessageId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    _rows.add(row);
    return row;
  }

  @override
  Future<Map<String, dynamic>?> updateStatus(
    String providerMessageId,
    DeliveryStatus status,
  ) async {
    for (final r in _rows) {
      if (r['providerMessageId'] == providerMessageId) {
        r['status'] = status.name;
        return r;
      }
    }
    return null;
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> list({
    int page = 1,
    int pageSize = 50,
  }) async {
    final all = _rows.reversed.toList();
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <Map<String, dynamic>>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (items: items, total: all.length);
  }
}
