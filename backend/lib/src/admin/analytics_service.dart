import '../appointments/appointment_repository.dart';
import '../auth/auth_repository.dart';
import '../auth/provider_auth_repository.dart';
import '../providers_repository.dart';
import '../reviews_repository.dart';
import 'admin_kyc_service.dart' show AdminResult;
import 'disputes_repository.dart';

/// Read-only marketplace-health KPIs for the admin console (design:
/// docs/design/admin-console.md §13). Composes repository counts on the fly
/// (fine at V1 volume); no new tables. Event-based funnels (search→book) need a
/// product-analytics stack and are deferred (Slice 4).
class AnalyticsService {
  AnalyticsService(
    this._appointments,
    this._providers,
    this._auth,
    this._providerAuth,
    this._disputes,
    this._reviews,
  );

  final AppointmentRepository _appointments;
  final ProvidersRepository _providers;
  final AuthRepository _auth;
  final ProviderAuthRepository _providerAuth;
  final DisputesRepository _disputes;
  final ReviewsRepository _reviews;

  Future<int> _users(String status) async =>
      (await _auth.listUsers(status: status, pageSize: 1)).total;

  Future<int> _providersWith(String status) async =>
      (await _providers.listForAdmin(status: status, pageSize: 1)).total;

  Future<int> _verif(String status) async =>
      (await _providerAuth.listByVerificationStatus(status, pageSize: 1)).total;

  Future<AdminResult> overview() async {
    final bookings = await _appointments.countsByStatus();
    int b(String s) => bookings[s] ?? 0;
    final completed = b('completed');
    final noShow = b('noShow');
    final cancelled = b('cancelled');
    final totalBookings = bookings.values.fold<int>(0, (s, n) => s + n);

    double rate(int num, int den) =>
        den == 0 ? 0 : (num / den * 1000).round() / 1000;

    final disputesOpen = (await _disputes.list(
      status: 'open',
      pageSize: 1,
    )).total;
    final disputesTotal = (await _disputes.list(pageSize: 1)).total;

    return (
      ok: true,
      error: null,
      data: {
        'users': {
          'active': await _users('active'),
          'banned': await _users('banned'),
        },
        'providers': {
          'active': await _providersWith('active'),
          'suspended': await _providersWith('suspended'),
        },
        'verification': {
          'pending': await _verif('pending'),
          'verified': await _verif('verified'),
          'rejected': await _verif('rejected'),
        },
        'bookings': {
          'pending': b('pending'),
          'confirmed': b('confirmed'),
          'completed': completed,
          'cancelled': cancelled,
          'noShow': noShow,
          'total': totalBookings,
        },
        'guardrails': {
          // Of finished bookings, how many were no-shows; and the share of all
          // bookings that were cancelled.
          'noShowRate': rate(noShow, completed + noShow),
          'cancellationRate': rate(cancelled, totalBookings),
        },
        'disputes': {'open': disputesOpen, 'total': disputesTotal},
        'reportedReviews': (await _reviews.listReportedReviews(
          pageSize: 1,
        )).total,
      },
    );
  }

  /// North Star (FR-WEB-AD-006 / §17): completed bookings per ISO week ×
  /// commune over the last [weeks]. Weeks are bucketed in Dart (Monday start)
  /// so both repo backends agree.
  Future<AdminResult> northStar({int weeks = 12}) async {
    final w = weeks.clamp(1, 52);
    final from = _weekStart(
      DateTime.now().toUtc(),
    ).subtract(Duration(days: (w - 1) * 7));
    final completed = await _appointments.completedForAnalytics(from);

    // id → commune (one pull; V1 provider counts are small).
    final provs = await _providers.listForAdmin(pageSize: 100000);
    final commune = {
      for (final p in provs.items)
        p['id'] as String: (p['commune'] as String?) ?? 'unknown',
    };

    final counts = <String, Map<String, int>>{}; // week → commune → n
    for (final a in completed) {
      final week = _fmt(
        _weekStart(DateTime.parse(a['appointmentDate'] as String).toUtc()),
      );
      final c = commune[a['providerId']] ?? 'unknown';
      (counts[week] ??= {})[c] = ((counts[week]?[c]) ?? 0) + 1;
    }

    final series = [
      for (final week in counts.keys.toList()..sort())
        for (final c in counts[week]!.keys.toList()..sort())
          {'week': week, 'commune': c, 'completed': counts[week]![c]},
    ];

    return (
      ok: true,
      error: null,
      data: {
        'weeks': w,
        'fromWeek': _fmt(from),
        'totalCompleted': completed.length,
        'series': series,
      },
    );
  }

  /// Monday 00:00 UTC of the week containing [d].
  static DateTime _weekStart(DateTime d) {
    final day = DateTime.utc(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
