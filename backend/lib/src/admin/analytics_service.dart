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
}
