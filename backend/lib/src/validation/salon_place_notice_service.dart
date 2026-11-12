import '../admin/admin_notifier.dart';
import '../email/salon_validation_emails.dart' show PlaceChange;
import '../providers_repository.dart';
import 'salon_place_notice_repository.dart';
import 'salon_validation_repository.dart';

/// A value of a salon's place as the admin reads it: trimmed text, null when
/// empty.
String? placeText(Object? v) {
  final t = v is String ? v.trim() : v?.toString();
  return (t == null || t.isEmpty) ? null : t;
}

/// The pin as the admin reads it — as doubles, so a stored `5` and a sent
/// `5.0` are the same pin. Null without both coordinates.
String? placePin(Object? lat, Object? lng) =>
    (lat is num && lng is num) ? '${lat.toDouble()}, ${lng.toDouble()}' : null;

/// The commune and the city, as the admin reads them.
String? placeArea(Map<String, dynamic> m) {
  final parts = [?placeText(m['commune']), ?placeText(m['city'])];
  return parts.isEmpty ? null : parts.join(', ');
}

/// A salon's place as the e-mails show it, by [kPlaceNoticeFields] key — what
/// a summary compares with what was last reported.
Map<String, String?> placeSnapshot(Map<String, dynamic> doc) => {
  'location': placePin(doc['latitude'], doc['longitude']),
  'address': placeText(doc['address']),
  'commune': placeArea(doc),
  'phone': placeText(doc['phoneNumber']),
};

/// The admin's place-change e-mails, capped (B0.18 — decision 133,
/// docs/design/salon-go-live-approval.md §5.1, threat T82).
///
/// Before the cap, every save that changed a validated salon's pin,
/// address, commune or phone sent one e-mail: an owner or a manager saving
/// a value back and forth filled the admin's inbox and spent the
/// platform-wide hourly `warm` budget every other warm e-mail shares. Now:
///
/// - **the first change of a quiet hour** is e-mailed at once, as before
///   (the old and the new values of that save);
/// - **the changes in the hour after it** are recorded, not e-mailed;
/// - **once the hour has passed**, [tick] — run by the reminders cron every
///   15 minutes — sends ONE summary: the values last reported against the
///   salon's values now, which kinds changed, how many saves and since when.
///   It opens a new hour, so a salon that keeps saving yields at most one
///   e-mail an hour;
/// - **a suspended salon** records nothing and is sent nothing: the admin
///   already acted. A summary owed by a salon suspended (or no longer
///   validated, or gone) by the time it is due is dropped.
///
/// Both sides are single-winner in the repository: two saves racing on a
/// quiet hour send one e-mail, two ticks send one summary.
class SalonPlaceNoticeService {
  SalonPlaceNoticeService(
    this._notices,
    this._providers,
    this._validations,
    this._admin, {
    DateTime Function()? clock,
    void Function(String)? log,
  }) : _clock = clock ?? DateTime.now,
       _log = log ?? print;

  final SalonPlaceNoticeRepository _notices;
  final ProvidersRepository _providers;
  final SalonValidationRepository _validations;
  final AdminNotifier _admin;
  final DateTime Function() _clock;
  final void Function(String) _log;

  /// Whether a salon's place changes are reported at all: validated, and
  /// not suspended. The save path and [tick] read the same rule.
  static bool reportable(SalonValidation? v, Map<String, dynamic>? salon) =>
      v?.state == ValidationStates.approved &&
      salon != null &&
      salon['status'] != 'suspended';

  /// A save changed [changes] of a reportable salon's place; [after] is the
  /// salon as the save left it. The save has already stood: nothing here
  /// can fail it.
  ///
  /// When the cap cannot be read (its table unreachable), the e-mail goes as
  /// before the cap: the admin is told rather than not, and the shared
  /// budget still bounds it.
  Future<void> placeChanged({
    required String providerId,
    required String salonName,
    required List<PlaceChange> changes,
    required Map<String, dynamic> after,
  }) async {
    if (changes.isEmpty) return;
    PlaceNoticeTurn turn;
    try {
      turn = await _notices.recordSave(
        providerId,
        _clock().toUtc(),
        after: placeSnapshot(after),
        fields: changes.map((c) => c.field),
      );
    } catch (e) {
      _log(
        'place_notice provider=$providerId outcome=cap_unavailable '
        'error=${e.runtimeType}',
      );
      turn = PlaceNoticeTurn.sendNow;
    }
    if (turn == PlaceNoticeTurn.recorded) {
      _log('place_notice provider=$providerId outcome=recorded');
      return;
    }
    // Best effort inside the notifier: it never throws.
    await _admin.salonPlaceChanged(
      providerId: providerId,
      salonName: salonName,
      changes: changes,
    );
  }

  /// The summaries due at [now], each sent once; the number sent. One
  /// salon's failure is logged (its id and the error's type, nothing the
  /// salon typed) and the walk goes on.
  Future<int> tick(DateTime now) async {
    final when = now.toUtc();
    var sent = 0;
    for (final id in await _notices.due(when)) {
      try {
        if (await _summarise(id, when)) sent++;
      } catch (e) {
        _log('place_notice provider=$id outcome=failed error=${e.runtimeType}');
      }
    }
    return sent;
  }

  /// One salon's due summary, sent once; whether it went.
  ///
  /// **The row first, then the salon.** The claim is conditional on the
  /// pending count read here: a save recorded after this read may be missing
  /// from the place read next, so it makes the claim miss — never a summary
  /// that marks a value as reported without showing it — and the next tick
  /// reads both again.
  Future<bool> _summarise(String id, DateTime when) async {
    final seen = (await _notices.get(id))?.pendingCount ?? 0;
    final salon = await _providers.byId(id);
    if (salon == null) {
      await _notices.forget(id);
      _log('place_notice provider=$id outcome=dropped reason=gone');
      return false;
    }
    final v = await _validations.get(id);
    if (!reportable(v, salon)) {
      await _notices.dropPending(id);
      final reason = salon['status'] == 'suspended'
          ? 'suspended'
          : 'not_validated';
      _log('place_notice provider=$id outcome=dropped reason=$reason');
      return false;
    }
    final current = placeSnapshot(salon);
    final claim = await _notices.claimSummary(
      id,
      when,
      current: current,
      seenSaves: seen,
    );
    // Another tick took it first, or a save landed since the row was read:
    // the next tick sends it.
    if (claim == null) return false;
    await _admin.salonPlaceSummary(
      providerId: id,
      salonName: placeText(salon['name']) ?? id,
      reported: claim.reported,
      current: current,
      fields: claim.fields,
      saves: claim.saves,
      since: claim.since,
    );
    return true;
  }
}
