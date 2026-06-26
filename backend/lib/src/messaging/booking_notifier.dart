import '../auth/auth_repository.dart';
import '../providers_repository.dart';
import 'messaging_models.dart';
import 'messaging_service.dart';

/// Turns a booking transition into a notification: resolves the recipient
/// (manual `clientPhone`, else the consumer's phone) + the salon name, builds the
/// template params, and hands off to [MessagingService] (best-effort). Keeps the
/// transition services pure. Design: docs/design/messaging-notifications.md.
class BookingNotifier {
  BookingNotifier(this._messaging, this._users, this._providers);

  final MessagingService _messaging;
  final AuthRepository _users;
  final ProvidersRepository _providers;

  /// Sends [template] for [appointment] (a no-op when null / unresolvable).
  Future<void> notify(
    Map<String, dynamic>? appointment,
    MessageTemplate template,
  ) async {
    if (appointment == null) return;
    try {
      final phone = await _recipient(appointment);
      if (phone == null || phone.isEmpty) return;
      final providerName = await _providerName(
        appointment['providerId'] as String?,
      );
      await _messaging.sendTemplate(
        recipientPhone: phone,
        template: template,
        params: _params(appointment, providerName),
      );
    } catch (_) {
      // best-effort — a notification failure never affects the transition.
    }
  }

  Future<String?> _recipient(Map<String, dynamic> a) async {
    final clientPhone = a['clientPhone'] as String?;
    if (clientPhone != null && clientPhone.isNotEmpty) return clientPhone;
    final userId = a['userId'] as String?;
    if (userId == null) return null;
    return (await _users.userById(userId))?.phoneNumber;
  }

  Future<String> _providerName(String? providerId) async {
    if (providerId == null) return 'votre salon';
    final p = await _providers.byId(providerId);
    return (p?['name'] as String?) ?? 'votre salon';
  }

  Map<String, String> _params(Map<String, dynamic> a, String providerName) {
    final dt = DateTime.tryParse('${a['appointmentDate'] ?? ''}')?.toUtc();
    final deposit = a['depositAmount'] as num?;
    final total = a['totalPrice'] as num?;
    return {
      'provider': providerName,
      if (dt != null) 'date': _date(dt),
      if (dt != null) 'time': _time(dt),
      if (deposit != null) 'deposit': _fcfa(deposit),
      if (total != null) 'amount': _fcfa(total),
    };
  }

  // Côte d'Ivoire is UTC, so UTC == local — no timezone conversion needed.
  String _date(DateTime d) => '${_pad(d.day)}/${_pad(d.month)}/${d.year}';
  String _time(DateTime d) => '${_pad(d.hour)}:${_pad(d.minute)}';
  String _pad(int n) => n.toString().padLeft(2, '0');
  String _fcfa(num n) => '${n.round()} XOF';
}
