import 'access/capabilities.dart';
import 'access/membership_service.dart';
import 'appointments/appointment_repository.dart';
import 'storage/storage_service.dart';

/// Outcome of a deposit operation; [data] is the response body on success.
typedef DepositResult = ({bool ok, String? error, Object? data});

/// Consumer deposit flow (design: docs/design/consumer-deposit.md). Myweli holds
/// nothing: the client pays the salon directly and attaches a **private**
/// screenshot; the salon views it (signed-GET) and confirms by accepting the
/// booking. This service records the screenshot key on the booking and issues
/// short-lived signed view URLs to the two authorized parties.
class DepositService {
  DepositService(this._appointments, this._members, this._storage);

  final AppointmentRepository _appointments;
  final MembershipService _members;
  final StorageService _storage;

  static const _viewTtl = Duration(minutes: 5);

  /// The consumer attaches/replaces the deposit screenshot on their own pending
  /// booking. [key] must be one they just uploaded (`deposit/{userId}/…`).
  Future<DepositResult> submit(
    String userId,
    String appointmentId,
    Object? key,
  ) async {
    // Resolve identity/state first (a stranger gets 403 regardless of the key),
    // then validate the key belongs to the caller.
    final appt = await _appointments.byId(appointmentId);
    if (appt == null) return (ok: false, error: 'not_found', data: null);
    if (appt['userId'] != userId) {
      return (ok: false, error: 'forbidden', data: null);
    }
    if (appt['status'] != 'pending') {
      return (ok: false, error: 'invalid_state', data: null);
    }
    if (key is! String || !key.startsWith('deposit/$userId/')) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final updated = await _appointments.update(appointmentId, {
      'depositScreenshotUrl': key,
    });
    return (ok: true, error: null, data: updated);
  }

  /// A short-lived signed view URL for the booking's screenshot — only the
  /// booking's consumer, its salon, or an **admin** (dispute evidence) may
  /// request it.
  Future<DepositResult> screenshotUrl(
    String appointmentId, {
    required String sub,
    required String role,
  }) async {
    final appt = await _appointments.byId(appointmentId);
    if (appt == null) return (ok: false, error: 'not_found', data: null);

    final bool authorized;
    if (role == 'admin') {
      authorized = true; // admins review deposit proof for disputes
    } else if (role == 'provider') {
      // Module `access` R1: the booking's salon journal is the boundary.
      authorized = await _members.can(
        sub,
        appt['providerId'] as String? ?? '',
        Cap.journalViewAll,
      );
    } else {
      authorized = appt['userId'] == sub;
    }
    if (!authorized) return (ok: false, error: 'forbidden', data: null);

    final key = appt['depositScreenshotUrl'];
    if (key is! String || key.isEmpty) {
      return (ok: false, error: 'not_found', data: null);
    }
    return (
      ok: true,
      error: null,
      data: {
        'url': _storage.presignGet(
          key: key,
          bucket: StorageBucket.deposit,
          ttl: _viewTtl,
        ),
      },
    );
  }
}
