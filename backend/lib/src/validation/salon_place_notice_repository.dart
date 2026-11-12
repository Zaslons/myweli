/// The cap on the place-change e-mails (B0.18 — decision 133,
/// docs/design/salon-go-live-approval.md §5.1, threat T82): a validated
/// salon's change of pin, address, commune or phone e-mails `ADMIN_EMAIL` at
/// once only when no such e-mail went for that salon in the last hour. The
/// changes after it are recorded here, and the reminders cron sends ONE
/// summary once the hour has passed — the values last reported to the admin
/// against the salon's values at that moment.
///
/// One row per salon (`salon_place_notices`, migration 0045). It holds the
/// salon's place as last reported, phone included, so account erasure
/// deletes it ([SalonPlaceNoticeRepository.forget]) — the salon row stays,
/// so no cascade would.
library;

/// One hour per salon: an e-mail, immediate or summary, opens it; nothing
/// else goes for that salon until it has passed.
const Duration kPlaceNoticeWindow = Duration(hours: 1);

/// How long past its hour a summary may wait for the reminders cron — every
/// 15 minutes, so two missed ticks — before the salon's next save sends it
/// itself ([PlaceNoticeTurn.summaryOverdue]). The cron sends the summaries;
/// it is never the only way out of the cap.
const Duration kPlaceSummaryGrace = Duration(minutes: 30);

/// The four kinds of place change, in the order the e-mails list them —
/// [PlaceNoticeState.reported] and [PlaceNoticeState.pendingFields] use
/// these keys.
const List<String> kPlaceNoticeFields = [
  'location',
  'address',
  'commune',
  'phone',
];

/// A salon's place-change e-mails: the last one, and what changed since.
class PlaceNoticeState {
  const PlaceNoticeState({
    required this.providerId,
    this.lastSentAt,
    this.reported = const {},
    this.pendingCount = 0,
    this.pendingSince,
    this.pendingFields = const [],
  });

  final String providerId;

  /// When the last e-mail (immediate or summary) went. Null: never.
  final DateTime? lastSentAt;

  /// The salon's place as that e-mail left it, by [kPlaceNoticeFields] key,
  /// each value as the e-mail shows it (null: none).
  final Map<String, String?> reported;

  /// The saves recorded since — changes not yet e-mailed.
  final int pendingCount;

  /// The first of them. Null when [pendingCount] is 0.
  final DateTime? pendingSince;

  /// The kinds they touched, in [kPlaceNoticeFields] order.
  final List<String> pendingFields;
}

/// What [SalonPlaceNoticeRepository.recordSave] decided for one save.
enum PlaceNoticeTurn {
  /// This save won the hour: the caller sends the e-mail now.
  sendNow,

  /// An e-mail went in the last hour, or a summary is owed: the save is
  /// counted, and the summary will carry it.
  recorded,

  /// Recorded, and the summary it joins is [kPlaceSummaryGrace] past its
  /// hour: the reminders cron has not sent it (paused, failing). The caller
  /// sends that summary now, this save in it — the cap never silences the
  /// admin.
  summaryOverdue,
}

/// What [SalonPlaceNoticeRepository.claimSummary] hands its single winner:
/// the summary's « before » and its counts, as they stood when claimed.
typedef PlaceSummaryClaim = ({
  Map<String, String?> reported,
  int saves,
  DateTime since,
  List<String> fields,
});

/// The rows of migration 0045.
abstract interface class SalonPlaceNoticeRepository {
  /// The salon's row, or null — no qualifying save since the migration.
  Future<PlaceNoticeState?> get(String providerId);

  /// A save changed [fields] of a validated salon's place; [after] is the
  /// place it left. **Single winner**: of the saves that race in a quiet
  /// hour, exactly one gets [PlaceNoticeTurn.sendNow].
  ///
  /// - **Quiet** — nothing pending, and no e-mail in the last
  ///   [kPlaceNoticeWindow] (or never): [PlaceNoticeTurn.sendNow]; the row
  ///   records the time and [after] as reported.
  /// - **Otherwise:** [PlaceNoticeTurn.recorded]; one more pending save, its
  ///   kinds added, the first one's time kept. A save after the hour while a
  ///   summary is still owed joins that summary (the next tick sends it): an
  ///   immediate e-mail then would report from the wrong « before ». When
  ///   that summary is [kPlaceSummaryGrace] past its hour, the same row with
  ///   [PlaceNoticeTurn.summaryOverdue].
  Future<PlaceNoticeTurn> recordSave(
    String providerId,
    DateTime now, {
    required Map<String, String?> after,
    required Iterable<String> fields,
  });

  /// The salons whose summary is due at [now]: a save pending, and the last
  /// e-mail [kPlaceNoticeWindow] or more ago. The oldest pending first, at
  /// most [limit].
  Future<List<String>> due(DateTime now, {int limit = 100});

  /// Takes the salon's due summary — **single winner**: of two ticks, one
  /// gets it, the other null. In one step: the e-mail time set to [now],
  /// [current] recorded as reported (the summary shows it), the pending
  /// cleared. Null when nothing is due (claimed already, or not yet).
  ///
  /// **Conditional on what the caller read.** [seenSaves] is the pending
  /// count the caller read ([get]) BEFORE it read the salon's place for
  /// [current]. A save recorded since then may be missing from [current]:
  /// the claim misses (null, nothing cleared) rather than mark that save
  /// reported, and the next tick reads both again.
  Future<PlaceSummaryClaim?> claimSummary(
    String providerId,
    DateTime now, {
    required Map<String, String?> current,
    required int seenSaves,
  });

  /// Clears a pending summary without sending it (the salon is suspended or
  /// no longer validated). The e-mail time and the reported place stay. True
  /// when something was pending.
  Future<bool> dropPending(String providerId);

  /// Deletes the salon's row — account erasure (it holds the salon's last
  /// reported phone and address), and a salon gone from under it.
  Future<void> forget(String providerId);
}

/// [kPlaceNoticeFields] that are in [fields], in that order.
List<String> orderedPlaceFields(Iterable<String> fields) {
  final set = fields.toSet();
  return [
    for (final f in kPlaceNoticeFields)
      if (set.contains(f)) f,
  ];
}

/// [SalonPlaceNoticeRepository.recordSave]'s decision, shared by both twins
/// so they cannot drift: the row a save leaves, and what it means.
({PlaceNoticeState next, PlaceNoticeTurn turn}) placeNoticeAfterSave(
  PlaceNoticeState? row,
  String providerId,
  DateTime now, {
  required Map<String, String?> after,
  required Iterable<String> fields,
}) {
  final when = now.toUtc();
  final last = row?.lastSentAt;
  final quiet =
      (row?.pendingCount ?? 0) == 0 &&
      (last == null || !last.isAfter(when.subtract(kPlaceNoticeWindow)));
  if (quiet) {
    return (
      next: PlaceNoticeState(
        providerId: providerId,
        lastSentAt: when,
        reported: Map.unmodifiable(after),
      ),
      turn: PlaceNoticeTurn.sendNow,
    );
  }
  // The summary this save joins was due [kPlaceSummaryGrace] ago, and the
  // cron has not sent it.
  final overdue = placeSummaryDue(row!, when.subtract(kPlaceSummaryGrace));
  return (
    next: PlaceNoticeState(
      providerId: providerId,
      lastSentAt: last,
      reported: row.reported,
      pendingCount: row.pendingCount + 1,
      pendingSince: row.pendingSince ?? when,
      pendingFields: orderedPlaceFields([...row.pendingFields, ...fields]),
    ),
    turn: overdue ? PlaceNoticeTurn.summaryOverdue : PlaceNoticeTurn.recorded,
  );
}

/// Whether [row]'s summary is due at [now] — the rule [due] and
/// [claimSummary] share.
bool placeSummaryDue(PlaceNoticeState row, DateTime now) {
  final last = row.lastSentAt;
  return row.pendingCount > 0 &&
      (last == null || !last.isAfter(now.toUtc().subtract(kPlaceNoticeWindow)));
}

/// The in-memory twin. **Single winner without a database:** each write is
/// one synchronous section — the read and the write with no `await` between
/// them — so two calls interleaving on the event loop resolve as the
/// Postgres twin's row lock does.
class InMemorySalonPlaceNoticeRepository implements SalonPlaceNoticeRepository {
  final Map<String, PlaceNoticeState> _rows = {};

  @override
  Future<PlaceNoticeState?> get(String providerId) async => _rows[providerId];

  @override
  Future<PlaceNoticeTurn> recordSave(
    String providerId,
    DateTime now, {
    required Map<String, String?> after,
    required Iterable<String> fields,
  }) async {
    final r = placeNoticeAfterSave(
      _rows[providerId],
      providerId,
      now,
      after: after,
      fields: fields,
    );
    _rows[providerId] = r.next;
    return r.turn;
  }

  @override
  Future<List<String>> due(DateTime now, {int limit = 100}) async {
    final rows = _rows.values.where((r) => placeSummaryDue(r, now)).toList()
      // The Postgres twin's ORDER BY: the oldest pending first, the salon id
      // breaking ties.
      ..sort((a, b) {
        final c = a.pendingSince!.compareTo(b.pendingSince!);
        return c != 0 ? c : a.providerId.compareTo(b.providerId);
      });
    return [for (final r in rows.take(limit)) r.providerId];
  }

  @override
  Future<PlaceSummaryClaim?> claimSummary(
    String providerId,
    DateTime now, {
    required Map<String, String?> current,
    required int seenSaves,
  }) async {
    final row = _rows[providerId];
    if (row == null || !placeSummaryDue(row, now)) return null;
    if (row.pendingCount != seenSaves) return null;
    _rows[providerId] = PlaceNoticeState(
      providerId: providerId,
      lastSentAt: now.toUtc(),
      reported: Map.unmodifiable(current),
    );
    return (
      reported: row.reported,
      saves: row.pendingCount,
      since: row.pendingSince!,
      fields: row.pendingFields,
    );
  }

  @override
  Future<bool> dropPending(String providerId) async {
    final row = _rows[providerId];
    if (row == null || row.pendingCount == 0) return false;
    _rows[providerId] = PlaceNoticeState(
      providerId: providerId,
      lastSentAt: row.lastSentAt,
      reported: row.reported,
    );
    return true;
  }

  @override
  Future<void> forget(String providerId) async => _rows.remove(providerId);
}
