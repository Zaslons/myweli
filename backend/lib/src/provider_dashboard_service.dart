import 'appointments/appointment_repository.dart';
import 'auth/provider_auth_repository.dart';

/// Outcome of a dashboard read; [data] is the `DashboardStats` map on success.
typedef DashboardResult = ({
  bool ok,
  String? error,
  Map<String, dynamic>? data,
});

/// Server-authoritative pro dashboard stats
/// (docs/design/provider-dashboard-stats.md). Ownership-scoped: the access
/// token's account must manage `providerId` (→ `forbidden`). Stats are computed
/// in UTC (Abidjan is UTC+0) from the salon's appointments — revenue counts
/// `confirmed` + `completed`; `todayAppointments` excludes `cancelled`.
class ProviderDashboardService {
  ProviderDashboardService(this._providerAuth, this._appointments);

  final ProviderAuthRepository _providerAuth;
  final AppointmentRepository _appointments;

  static const _revenueStatuses = {'confirmed', 'completed'};

  Future<DashboardResult> statsFor(String accountId, String providerId) async {
    final account = await _providerAuth.accountById(accountId);
    if (account?.providerId != providerId) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final appointments = await _appointments.listForProvider(providerId);
    return (ok: true, error: null, data: _compute(appointments));
  }

  Map<String, dynamic> _compute(List<Map<String, dynamic>> appointments) {
    final now = DateTime.now().toUtc();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final monthStart = DateTime.utc(now.year, now.month, 1);
    final monthEnd = DateTime.utc(now.year, now.month + 1, 1);

    bool inWindow(DateTime d, DateTime start, DateTime end) =>
        !d.isBefore(start) && d.isBefore(end);

    var todayAppointments = 0;
    var pendingRequests = 0;
    var todayRevenue = 0.0;
    var weekRevenue = 0.0;
    var monthRevenue = 0.0;

    for (final a in appointments) {
      final status = a['status'] as String?;
      final date = DateTime.parse(a['appointmentDate'] as String).toUtc();
      final price = (a['totalPrice'] as num?)?.toDouble() ?? 0;

      if (status == 'pending') pendingRequests++;
      if (status != 'cancelled' && inWindow(date, todayStart, todayEnd)) {
        todayAppointments++;
      }
      if (_revenueStatuses.contains(status)) {
        if (inWindow(date, todayStart, todayEnd)) todayRevenue += price;
        if (inWindow(date, weekStart, weekEnd)) weekRevenue += price;
        if (inWindow(date, monthStart, monthEnd)) monthRevenue += price;
      }
    }

    return {
      'todayAppointments': todayAppointments,
      'pendingRequests': pendingRequests,
      'todayRevenue': todayRevenue,
      'weekRevenue': weekRevenue,
      'monthRevenue': monthRevenue,
      'totalAppointments': appointments.length,
    };
  }
}
