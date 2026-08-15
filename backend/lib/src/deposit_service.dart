import 'access/capabilities.dart';
import 'access/membership_service.dart';
import 'appointments/appointment_repository.dart';
import 'storage/storage_service.dart';
import 'upload_verification_service.dart';

/// Outcome of a deposit operation; [data] is the response body on success.
typedef DepositResult = ({bool ok, String? error, Object? data});

/// [DepositService.submit]'s outcome, plus whether this was a **replay** — the
/// same key arriving twice because the first response was dropped.
///
/// The flag exists for the route, not for the client: the body is identical
/// either way, but a replay must not re-notify the salon about a justificatif
/// it has already been told about.
typedef DepositSubmitResult = ({
  bool ok,
  String? error,
  Object? data,
  bool replayed,
});

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
  Future<DepositSubmitResult> submit(
    String userId,
    String appointmentId,
    Object? key,
  ) async {
    // Resolve identity/state first (a stranger gets 403 regardless of the key),
    // then validate the key belongs to the caller.
    final appt = await _appointments.byId(appointmentId);
    if (appt == null) {
      return (ok: false, error: 'not_found', data: null, replayed: false);
    }
    if (appt['userId'] != userId) {
      return (ok: false, error: 'forbidden', data: null, replayed: false);
    }
    if (appt['status'] != 'pending') {
      return (ok: false, error: 'invalid_state', data: null, replayed: false);
    }
    // The key the signer issued is a PENDING one; ownership is checked against
    // the path it will take after promotion.
    if (key is! String ||
        !key.startsWith('${kPendingPrefix}deposit/$userId/')) {
      return (ok: false, error: 'invalid_input', data: null, replayed: false);
    }

    // **A dropped response was unrecoverable.** Claiming DELETES the pending
    // source, so re-sending the same key made `verify` HEAD an object we
    // deleted ourselves — `upload_not_found`, a 400, for what is only a lost
    // reply. (Not even reliably: the promotion's delete is best-effort, so if
    // it had failed the replay quietly succeeded instead. Two behaviours for
    // one situation.) The app keeps the key across a failure, so this is its
    // retry path, and the only way out was « Retirer » and re-pick.
    //
    // The comparison is against the PROMOTED form, and that is not a detail:
    // the client only ever holds the pending key, so `key == stored` is a
    // condition that can never be true — a check written that way would be
    // dead code that looks like a fix.
    //
    // Safe to treat as done: the key is server-built from 128 crypto-random
    // bits under this caller's own prefix, so a match identifies exactly one
    // prior claim of theirs. It stays BELOW the status gate on purpose — a
    // replay arriving after the salon accepted is still `invalid_state`,
    // because re-confirming a key on a settled booking is a different act.
    final already = promotedKey(key);
    if (already != null && appt['depositScreenshotUrl'] == already) {
      return (ok: true, error: null, data: appt, replayed: true);
    }

    // **Captured BEFORE the update.** `InMemoryAppointmentRepository.update`
    // mutates and returns the very map `byId` handed out, so reading the
    // column afterwards yields the NEW key under the fake and the OLD one
    // under Postgres — a delete wired that way would target the object it just
    // promoted, and only in tests.
    final prior = appt['depositScreenshotUrl'];

    // Ownership is proven above; size is not. Oversized is deleted and refused
    // — accepting it would attach a screenshot we pay to store indefinitely,
    // on the consumer-reachable payment path. Promotion moves it out of
    // `pending/` so what remains there is only ever an orphan.
    final v = await _verifier.verifyAndPromote([
      key,
    ], bucket: StorageBucket.deposit);
    if (!v.ok) {
      return (ok: false, error: v.error, data: null, replayed: false);
    }

    final promoted = v.keys.single;
    final updated = await _appointments.update(appointmentId, {
      // The PROMOTED key — recording the pending one would leave the object
      // under a prefix a lifecycle rule is about to expire.
      'depositScreenshotUrl': promoted,
    });

    // **The superseded object used to be abandoned**, and the cost was not the
    // storage. It sits at its promoted path, outside `pending/`, so no
    // lifecycle rule collects it — and `anonymizeUser` hands erasure only the
    // key each row *currently* holds, so a payment proof belonging to a real
    // person outlived `DELETE /me` with nothing left pointing at it.
    //
    // AFTER the row points at the new object, never before. The two failure
    // modes are not symmetric: delete-then-failed-update leaves a live booking
    // pointing at destroyed payment proof — which the salon and an admin can
    // both request for a dispute — while a failed delete leaves one orphan.
    //
    // Re-validated against the caller's own prefix rather than trusted,
    // because the column is bare `text` and the booking-time writer's verifier
    // is nullable: "always promoted" is a property of the two writers, not of
    // the schema. A value that does not match is skipped, not deleted and not
    // an error — the same posture erasure takes.
    if (updated != null &&
        prior is String &&
        prior.isNotEmpty &&
        prior != promoted &&
        prior.startsWith('deposit/$userId/')) {
      try {
        await _storage.deleteObject(key: prior, bucket: StorageBucket.deposit);
      } catch (_) {
        // Best-effort: one leaked object must not fail a recorded payment.
      }
    }
    return (ok: true, error: null, data: updated, replayed: false);
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
