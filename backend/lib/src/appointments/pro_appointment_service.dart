import '../auth/provider_auth_repository.dart';
import 'appointment_repository.dart';

typedef ProLifecycleResult = ({
  bool ok,
  String? error,
  Map<String, dynamic>? appointment,
});

/// Pro-side appointment transitions (docs/BACKEND.md §3.3). The salon accepts /
/// rejects / completes / marks-no-show bookings for **its own** Provider only:
/// the access token's `sub` resolves to a provider account, and that account's
/// `providerId` must match the appointment's `providerId` (→ 403 otherwise).
/// The server is the authority on status; transitions are state-guarded.
class ProAppointmentService {
  ProAppointmentService(this._providerAuth, this._appointments);

  final ProviderAuthRepository _providerAuth;
  final AppointmentRepository _appointments;

  Future<ProLifecycleResult> accept(String appointmentId, String accountId) =>
      _transition(
        appointmentId,
        accountId,
        from: const {'pending'},
        to: 'confirmed',
      );

  Future<ProLifecycleResult> reject(String appointmentId, String accountId) =>
      _transition(
        appointmentId,
        accountId,
        from: const {'pending'},
        to: 'cancelled',
      );

  Future<ProLifecycleResult> complete(String appointmentId, String accountId) =>
      _transition(
        appointmentId,
        accountId,
        from: const {'confirmed'},
        to: 'completed',
      );

  Future<ProLifecycleResult> noShow(String appointmentId, String accountId) =>
      _transition(
        appointmentId,
        accountId,
        from: const {'pending', 'confirmed'},
        to: 'noShow',
      );

  Future<ProLifecycleResult> _transition(
    String appointmentId,
    String accountId, {
    required Set<String> from,
    required String to,
  }) async {
    final account = await _providerAuth.accountById(accountId);
    final managedProviderId = account?.providerId;
    if (managedProviderId == null) {
      // Authenticated provider, but not linked to a Provider it can manage.
      return (ok: false, error: 'forbidden', appointment: null);
    }
    final appointment = await _appointments.byId(appointmentId);
    if (appointment == null) {
      return (ok: false, error: 'not_found', appointment: null);
    }
    if (appointment['providerId'] != managedProviderId) {
      return (ok: false, error: 'forbidden', appointment: null);
    }
    if (!from.contains(appointment['status'])) {
      return (ok: false, error: 'invalid_state', appointment: null);
    }
    final updated = await _appointments.update(appointmentId, {'status': to});
    return (ok: true, error: null, appointment: updated);
  }
}
