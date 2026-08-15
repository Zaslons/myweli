import 'access/capabilities.dart';
import 'access/membership_service.dart';
import 'appointments/appointment_repository.dart';
import 'storage/storage_service.dart';
import 'upload_verification_service.dart';

/// Outcome of a deposit operation; [data] is the response body on success.
typedef DepositResult = ({bool ok, String? error, Object? data});

/// Consumer deposit flow (design: docs/design/consumer-deposit.md). Myweli holds
/// nothing: the client pays the salon directly and attaches a **private**
/// screenshot; the salon views it (signed-GET) and confirms by accepting the
/// booking. This service records the screenshot key on the booking and issues
/// short-lived signed view URLs to the two authorized parties.
class DepositService {
  DepositService(
    this._appointments,
    this._members,
    this._storage, {
    UploadVerificationService? verifier,
  }) : _verifier = verifier ?? UploadVerificationService(storage: _storage);

  final AppointmentRepository _appointments;
  final MembershipService _members;
  final StorageService _storage;

  /// Claim-time size check. R2 ignores a signed `content-length`, so the cap
  /// declared at signing time is advisory and this is where it actually holds.
  /// docs/design/backend-upload-size-verification.md.
  final UploadVerificationService _verifier;

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
    // The key the signer issued is a PENDING one; ownership is checked against
    // the path it will take after promotion.
    if (key is! String ||
        !key.startsWith('${kPendingPrefix}deposit/$userId/')) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    // Ownership is proven above; size is not. Oversized is deleted and refused
    // — accepting it would attach a screenshot we pay to store indefinitely,
    // on the consumer-reachable payment path. Promotion moves it out of
    // `pending/` so what remains there is only ever an orphan.
    final v = await _verifier.verifyAndPromote([
      key,
    ], bucket: StorageBucket.deposit);
    if (!v.ok) return (ok: false, error: v.error, data: null);

    final updated = await _appointments.update(appointmentId, {
      // The PROMOTED key — recording the pending one would leave the object
      // under a prefix a lifecycle rule is about to expire.
      'depositScreenshotUrl': v.keys.single,
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
    // **Authorization above is about the APPOINTMENT; this is about the KEY.**
    // Every check above answers "may you see this booking's proof", and none of
    // them answers "is this the booking's own proof" — so the moment any write
    // path stores a foreign key, this endpoint presigns it for three different
    // audiences. Both writers now guarantee `deposit/{userId}/…`, and this
    // makes that a property the READ enforces rather than one it assumes,
    // which is the same posture erasure already takes (`UserErasureService`
    // skips any object outside the user's own prefix).
    //
    // A manual salon booking has a null `userId` and never carries a proof, so
    // it exits at the empty-key check above and never reaches this.
    final owner = appt['userId'];
    if (owner is! String || !key.startsWith('deposit/$owner/')) {
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
