import 'appointments/appointment_repository.dart';
import 'auth/provider_auth_repository.dart';

/// Outcome of an earnings read; [data] is the `EarningsData` map on success.
typedef EarningsResult = ({bool ok, String? error, Map<String, dynamic>? data});

/// Server-authoritative pro **earnings** — the realized-money ledger behind the
/// dashboard (docs/design/provider-earnings.md). Ownership-scoped (the token's
/// account must manage `providerId` → `forbidden`). Earnings count **only
/// `completed`** appointments (deliberately narrower than the dashboard's
/// `confirmed`+`completed` revenue), optionally bounded by an inclusive UTC
/// date range on `appointmentDate`.
class ProviderEarningsService {
  ProviderEarningsService(this._providerAuth, this._appointments);

  final ProviderAuthRepository _providerAuth;
  final AppointmentRepository _appointments;

  Future<EarningsResult> earningsFor(
    String accountId,
    String providerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final account = await _providerAuth.accountById(accountId);
    if (account?.providerId != providerId) {
      return (ok: false, error: 'forbidden', data: null);
    }

    // The repo returns completed bookings newest-first (sorted by date desc).
    final completed = await _appointments.listForProvider(
      providerId,
      status: 'completed',
    );

    var total = 0.0;
    final transactions = <Map<String, dynamic>>[];
    for (final a in completed) {
      final date = DateTime.parse(a['appointmentDate'] as String).toUtc();
      if (startDate != null && date.isBefore(startDate)) continue;
      if (endDate != null && date.isAfter(endDate)) continue;
      final amount = (a['totalPrice'] as num).toDouble();
      total += amount;
      transactions.add({
        'id': 'transaction_${a['id']}',
        'appointmentId': a['id'],
        'amount': amount,
        'date': a['appointmentDate'],
        'status': 'completed',
      });
    }

    return (
      ok: true,
      error: null,
      data: {'totalEarnings': total, 'transactions': transactions},
    );
  }
}
