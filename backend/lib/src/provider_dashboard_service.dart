import 'access/capabilities.dart';
import 'access/membership_service.dart';
import 'appointments/appointment_repository.dart';
import 'providers_repository.dart';
import 'salon_time.dart';

/// Outcome of a dashboard read; [data] is the `DashboardStats` map on success.
typedef DashboardResult = ({
  bool ok,
  String? error,
  Map<String, dynamic>? data,
});

/// Server-authoritative pro dashboard stats
/// (docs/design/provider-dashboard-stats.md). Ownership-scoped: the access
/// token's account must manage `providerId` (→ `forbidden`). Bucket
/// boundaries (today / Monday-week / calendar month) are the SALON's
/// timezone (multi-pays MP1 — salon_time.dart); revenue counts
/// `confirmed` + `completed`; `todayAppointments` excludes `cancelled`.
class ProviderDashboardService {
  ProviderDashboardService(
    this._members,
    this._appointments, {
    ProvidersRepository? providers,
    DateTime Function()? clock,
  }) : _providers = providers,
       _now = clock ?? DateTime.now;

  final MembershipService _members;
  final AppointmentRepository _appointments;
  final ProvidersRepository? _providers;
  final DateTime Function() _now;

  static const _revenueStatuses = {'confirmed', 'completed'};

  Future<DashboardResult> statsFor(String accountId, String providerId) async {
    if (!await _members.can(accountId, providerId, Cap.journalViewAll)) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final appointments = await _appointments.listForProvider(providerId);
    final salon = await _providers?.byId(providerId);
    final stats = _compute(appointments, salon?['timezone'] as String?);
    // Field-level gating (module `access` §4): money figures only for
    // finances.view — absence is a valid state, not an error.
    if (!await _members.can(accountId, providerId, Cap.financesView)) {
      stats
        ..remove('todayRevenue')
        ..remove('weekRevenue')
        ..remove('monthRevenue');
    }
    return (ok: true, error: null, data: stats);
  }

  Map<String, dynamic> _compute(
    List<Map<String, dynamic>> appointments,
    String? tzName,
  ) {
    final now = _now().toUtc();
    // Salon-day buckets: today, Monday-start week, calendar month — all as
    // UTC instants of the SALON's midnights.
    final wall = salonWallClock(now, tzName);
    final today = salonDayBoundsUtc(now, tzName);
    final todayStart = today.startUtc;
    final todayEnd = today.endUtc;
    final weekStart = salonWallClockToUtc(
      wall.year,
      wall.month,
      wall.day - (wall.weekday - 1),
      0,
      tzName,
    );
    final weekEnd = salonWallClockToUtc(
      wall.year,
      wall.month,
      wall.day - (wall.weekday - 1) + 7,
      0,
      tzName,
    );
    final monthStart = salonWallClockToUtc(wall.year, wall.month, 1, 0, tzName);
    final monthEnd = salonWallClockToUtc(
      wall.year,
      wall.month + 1,
      1,
      0,
      tzName,
    );

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
