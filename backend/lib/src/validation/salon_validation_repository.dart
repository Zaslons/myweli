/// A salon goes public only once MyWeli validates it (B0.18, decision 120):
/// the validation record that sits BESIDE `providers.status`, which stays
/// `draft` until the admin's decision takes the salon live.
///
/// Design: docs/design/salon-go-live-approval.md §2 (the model), §3.1–§3.4
/// (the transitions), §3.7 (the backfill). Migration 0044.
///
/// **Never in `providers.data`.** The public payload serializes that whole
/// blob, so the validation lives in its own two tables and travels only on
/// authenticated reads — the reason billing state got its own table too.
library;

import '../access/membership_repository.dart';
import '../providers_repository.dart';

/// The three states of a salon's validation (`salon_validations.state`).
abstract final class ValidationStates {
  /// Waiting for the admin.
  static const pending = 'pending';

  /// Validated. Final for validation: it survives a billing unpublish and a
  /// suspension, so those paths never ask for a new one (§2.2).
  static const approved = 'approved';

  /// Refused, with a code (§4.3) and maybe a note.
  static const refused = 'refused';

  static const all = {pending, approved, refused};
}

/// The kinds of `salon_validation_events` — the history the admin reads.
abstract final class ValidationEventKinds {
  static const submitted = 'submitted';
  static const approved = 'approved';
  static const refused = 'refused';
}

/// §4.3's closed list of refusal codes.
const List<String> kRefusalCodes = [
  'incomplete_info',
  'photos',
  'unconfirmed',
  'outside_ci',
  'test_salon',
  'other',
];

/// The refusals a salon cannot answer by asking again (§4.3): only the admin
/// can still validate it, from « Refusés ».
const Set<String> kFinalRefusalCodes = {'outside_ci', 'test_salon'};

/// The current validation of one salon (`salon_validations`, one row per
/// salon).
class SalonValidation {
  const SalonValidation({
    required this.providerId,
    required this.state,
    this.submittedAt,
    this.decidedAt,
    this.decidedBy,
    this.refusalCode,
    this.refusalNote,
    this.wentLiveAt,
  });

  final String providerId;

  /// One of [ValidationStates.all].
  final String state;

  /// The last request; null on a row the migration backfilled.
  final DateTime? submittedAt;

  final DateTime? decidedAt;

  /// The admin's id. Never shown to a salon.
  final String? decidedBy;

  /// Set while [state] is `refused` (§4.3's codes); cleared by a new request
  /// or a validation — the history keeps it.
  final String? refusalCode;

  /// ≤ 500 code points (the service checks); cleared on account erasure.
  final String? refusalNote;

  /// Set once, by the single winner that took the salon public (§3.2 step 4).
  final DateTime? wentLiveAt;

  /// The admin's validation took the salon live at least once. An `approved`
  /// row without it is a validation interrupted before going live (§3.2) —
  /// « Validation à terminer ».
  bool get wentLive => wentLiveAt != null;

  /// A refusal the salon cannot answer by asking again (§4.3).
  bool get isFinalRefusal =>
      state == ValidationStates.refused &&
      kFinalRefusalCodes.contains(refusalCode);

  SalonValidation copyWith({DateTime? wentLiveAt, bool clearNote = false}) =>
      SalonValidation(
        providerId: providerId,
        state: state,
        submittedAt: submittedAt,
        decidedAt: decidedAt,
        decidedBy: decidedBy,
        refusalCode: refusalCode,
        refusalNote: clearNote ? null : refusalNote,
        wentLiveAt: wentLiveAt ?? this.wentLiveAt,
      );
}

/// One line of a salon's validation history (`salon_validation_events`).
class SalonValidationEvent {
  const SalonValidationEvent({
    required this.id,
    required this.providerId,
    required this.kind,
    required this.at,
    this.byAdmin,
    this.refusalCode,
    this.refusalNote,
  });

  /// Insertion order (`GENERATED ALWAYS AS IDENTITY`): the tie-break when
  /// two events share a time.
  final int id;
  final String providerId;

  /// One of [ValidationEventKinds].
  final String kind;

  /// When it happened (`occurred_at`).
  final DateTime at;

  /// The admin's id for a decision; null for the owner's request.
  final String? byAdmin;

  final String? refusalCode;

  /// Cleared on account erasure, like the state row's.
  final String? refusalNote;
}

/// What [SalonValidationRepository.submit] did.
///
/// [recorded] is true only when THIS call recorded a new request — a first
/// one, or a new one after a refusal that is not final. Only then does the
/// caller notify the admin (§3.1, §5.1): a double tap records once and sends
/// one e-mail. [validation] is the row as it stands after the call, re-read
/// when nothing was recorded, so the caller answers from the real state
/// (the admin may have decided at that very moment).
typedef SubmitOutcome = ({bool recorded, SalonValidation? validation});

/// What [SalonValidationRepository.goLive] did — exactly one call per salon
/// ever answers [live].
enum GoLiveOutcome {
  /// This call took the salon public: `went_live_at` set, `status` active.
  live,

  /// No validation, or not `approved`.
  notApproved,

  /// Another call already took it live (the single-winner step lost).
  alreadyLive,

  /// The salon is suspended — suspended between the checks and this step.
  suspended,

  /// The salon is not `draft` (already `active`, or gone): nothing to flip.
  notDraft,

  /// No active owner — an erased account. Nobody could run the salon.
  noOwner,
}

/// The validation record of each salon, and its history (migration 0044).
abstract interface class SalonValidationRepository {
  /// The salon's current validation, or null — never asked.
  Future<SalonValidation?> get(String providerId);

  /// [get] for a set, in ONE round trip (`/me/salons`, the admin queue).
  /// Salons without a row are absent from the map.
  Future<Map<String, SalonValidation>> getMany(Iterable<String> providerIds);

  /// The owner asks to go live (§3.1). In one transaction:
  ///
  /// - **no row:** a `pending` row — `INSERT … ON CONFLICT DO NOTHING`;
  /// - **`refused` with a code that is not final:** back to `pending`, the
  ///   refusal cleared from the state row — the same upsert's `DO UPDATE …
  ///   WHERE state = 'refused'`;
  /// - **anything else** (`pending`, `approved`, a final refusal): nothing;
  ///
  /// and a `submitted` event only when a row came back. See [SubmitOutcome].
  Future<SubmitOutcome> submit(String providerId, DateTime at);

  /// The admin's decision (§3.2 step 2, §3.3): a compare-and-set on
  /// `state = from`, with its event, in one transaction. Null when no row
  /// matched — a refuse that landed first, a second click, a stale tab: the
  /// loser writes nothing.
  ///
  /// The transitions are §2's: `pending → approved`, `pending → refused`,
  /// `refused → approved` (the admin corrects a refusal). Anything else, and a
  /// refusal without a [code], is a programming error ([ArgumentError]):
  /// `approved` is final. Approving clears the refusal from the state row;
  /// the history keeps it.
  Future<SalonValidation?> decide(
    String providerId, {
    required String from,
    required String to,
    required String adminId,
    String? code,
    String? note,
    DateTime? at,
  });

  /// The single-winner going-live (§3.2 step 4), all or nothing in ONE
  /// transaction:
  ///
  /// - `went_live_at` set where `state = 'approved' AND went_live_at IS NULL`;
  /// - `providers.status` set to `active` where it is `draft`;
  /// - an active owner membership exists.
  ///
  /// When any part does not match, nothing is written and the outcome says
  /// why. Only the caller that gets [GoLiveOutcome.live] fires the rebuild
  /// and the salon's notice.
  Future<GoLiveOutcome> goLive(String providerId, {DateTime? at});

  /// The admin queue (§3.5), `{ items, total }` for one [state]:
  ///
  /// - `pending`: oldest request first (`submitted_at`), **suspended salons
  ///   left out** — they come back when the suspension is lifted;
  /// - `refused`, `approved`: latest decision first, suspended included.
  Future<({List<SalonValidation> items, int total})> queue(
    String state, {
    int page = 1,
    int pageSize = 50,
  });

  /// The pending count, by the queue's definition (suspended salons left
  /// out): one number for the sidebar and the dashboard.
  Future<int> countPending();

  /// The salon's history, oldest first.
  Future<List<SalonValidationEvent>> events(String providerId);

  /// Account erasure (§3.4): drop a `pending` request — the queue must not
  /// keep an item for an erased owner. An `approved` or `refused` row stays
  /// with the salon. True when a row was deleted.
  Future<bool> deletePending(String providerId);

  /// Account erasure (§3.4): clear `refusal_note` on the state row AND in the
  /// history, in one transaction. The code stays.
  Future<void> clearNotes(String providerId);
}

/// Argument checks shared by both twins — the transitions §2 allows.
void checkDecision({
  required String from,
  required String to,
  String? code,
  String? note,
}) {
  const allowed = {
    (ValidationStates.pending, ValidationStates.approved),
    (ValidationStates.pending, ValidationStates.refused),
    (ValidationStates.refused, ValidationStates.approved),
  };
  if (!allowed.contains((from, to))) {
    throw ArgumentError('no validation transition $from → $to');
  }
  if (to == ValidationStates.refused) {
    if (code == null || !kRefusalCodes.contains(code)) {
      throw ArgumentError.value(code, 'code', 'a refusal needs a §4.3 code');
    }
  } else if (code != null || note != null) {
    throw ArgumentError('only a refusal carries a code or a note');
  }
}

/// Queue paging checks shared by both twins (the route clamps; this keeps a
/// wrong caller from reading an unbounded or negative page).
void checkQueueArgs(String state, int page, int pageSize) {
  if (!ValidationStates.all.contains(state)) {
    throw ArgumentError.value(state, 'state');
  }
  if (page < 1) throw ArgumentError.value(page, 'page');
  if (pageSize < 1) throw ArgumentError.value(pageSize, 'pageSize');
}

/// The in-memory twin.
///
/// **Single winner without a database.** Every write below is one
/// synchronous critical section — the check and the write with no `await`
/// between them — so two calls that interleave on the event loop resolve as
/// the Postgres twin's compare-and-set does: one wins, the other reads the
/// winner's state. That is why it reads the providers and the memberships
/// through their twins' synchronous `…Now` helpers rather than the async
/// interfaces.
class InMemorySalonValidationRepository implements SalonValidationRepository {
  /// Seeds an `approved` row that went live for every salon that is `active`
  /// when it is built — the in-memory twin of the dev boot backfill (§3.7):
  /// the seed's public salons are validated, nothing else is.
  InMemorySalonValidationRepository({
    required InMemoryProvidersRepository providers,
    required InMemoryMembershipRepository members,
  }) : _providers = providers,
       _members = members {
    final now = DateTime.now().toUtc();
    for (final id in providers.activeIdsNow()) {
      _rows[id] = SalonValidation(
        providerId: id,
        state: ValidationStates.approved,
        decidedAt: now,
        wentLiveAt: now,
      );
    }
  }

  final InMemoryProvidersRepository _providers;
  final InMemoryMembershipRepository _members;
  final Map<String, SalonValidation> _rows = {};
  final List<SalonValidationEvent> _events = [];
  int _seq = 0;

  void _event(
    String providerId,
    String kind,
    DateTime at, {
    String? byAdmin,
    String? code,
    String? note,
  }) => _events.add(
    SalonValidationEvent(
      id: ++_seq,
      providerId: providerId,
      kind: kind,
      at: at,
      byAdmin: byAdmin,
      refusalCode: code,
      refusalNote: note,
    ),
  );

  @override
  Future<SalonValidation?> get(String providerId) async => _rows[providerId];

  @override
  Future<Map<String, SalonValidation>> getMany(
    Iterable<String> providerIds,
  ) async => {
    for (final id in providerIds)
      if (_rows[id] != null) id: _rows[id]!,
  };

  @override
  Future<SubmitOutcome> submit(String providerId, DateTime at) async {
    final when = at.toUtc();
    final current = _rows[providerId];
    final asks =
        current == null ||
        (current.state == ValidationStates.refused && !current.isFinalRefusal);
    if (!asks) return (recorded: false, validation: current);
    final row = SalonValidation(
      providerId: providerId,
      state: ValidationStates.pending,
      submittedAt: when,
    );
    _rows[providerId] = row;
    _event(providerId, ValidationEventKinds.submitted, when);
    return (recorded: true, validation: row);
  }

  @override
  Future<SalonValidation?> decide(
    String providerId, {
    required String from,
    required String to,
    required String adminId,
    String? code,
    String? note,
    DateTime? at,
  }) async {
    checkDecision(from: from, to: to, code: code, note: note);
    final current = _rows[providerId];
    if (current == null || current.state != from) return null;
    final when = (at ?? DateTime.now()).toUtc();
    final refused = to == ValidationStates.refused;
    final row = SalonValidation(
      providerId: providerId,
      state: to,
      submittedAt: current.submittedAt,
      decidedAt: when,
      decidedBy: adminId,
      refusalCode: refused ? code : null,
      refusalNote: refused ? note : null,
      wentLiveAt: current.wentLiveAt,
    );
    _rows[providerId] = row;
    _event(
      providerId,
      to,
      when,
      byAdmin: adminId,
      code: refused ? code : null,
      note: refused ? note : null,
    );
    return row;
  }

  @override
  Future<GoLiveOutcome> goLive(String providerId, {DateTime? at}) async {
    // Every part is checked before anything is written — the in-memory
    // equivalent of the Postgres twin's write-then-roll-back.
    final current = _rows[providerId];
    if (current == null || current.state != ValidationStates.approved) {
      return GoLiveOutcome.notApproved;
    }
    if (current.wentLiveAt != null) return GoLiveOutcome.alreadyLive;
    final status = _providers.statusNow(providerId);
    if (status == 'suspended') return GoLiveOutcome.suspended;
    if (status != 'draft') return GoLiveOutcome.notDraft;
    if (!_members.hasActiveOwnerNow(providerId)) return GoLiveOutcome.noOwner;
    _providers.compareAndSetStatusNow(providerId, from: 'draft', to: 'active');
    _rows[providerId] = current.copyWith(
      wentLiveAt: (at ?? DateTime.now()).toUtc(),
    );
    return GoLiveOutcome.live;
  }

  /// The queue's definition of a row, shared with [countPending].
  bool _inQueue(SalonValidation v, String state) =>
      v.state == state &&
      (state != ValidationStates.pending ||
          _providers.statusNow(v.providerId) != 'suspended');

  @override
  Future<({List<SalonValidation> items, int total})> queue(
    String state, {
    int page = 1,
    int pageSize = 50,
  }) async {
    checkQueueArgs(state, page, pageSize);
    final all = [
      for (final v in _rows.values)
        if (_inQueue(v, state)) v,
    ];
    // The Postgres twin's ORDER BY, spelled out: pending by request time,
    // oldest first; the decided tabs by decision time, latest first; nulls
    // last both ways; the salon id breaks ties.
    final pending = state == ValidationStates.pending;
    all.sort((a, b) {
      final c = pending
          ? _nullsLast(a.submittedAt, b.submittedAt, (x, y) => x.compareTo(y))
          : _nullsLast(a.decidedAt, b.decidedAt, (x, y) => y.compareTo(x));
      return c != 0 ? c : a.providerId.compareTo(b.providerId);
    });
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <SalonValidation>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (items: items, total: all.length);
  }

  @override
  Future<int> countPending() async =>
      _rows.values.where((v) => _inQueue(v, ValidationStates.pending)).length;

  @override
  Future<List<SalonValidationEvent>> events(String providerId) async {
    final rows = [
      for (final e in _events)
        if (e.providerId == providerId) e,
    ];
    // The Postgres twin's `ORDER BY occurred_at, id`: the id is the
    // insertion order, so a tie keeps the order the events happened in.
    rows.sort((a, b) {
      final c = a.at.compareTo(b.at);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return rows;
  }

  @override
  Future<bool> deletePending(String providerId) async {
    if (_rows[providerId]?.state != ValidationStates.pending) return false;
    _rows.remove(providerId);
    return true;
  }

  @override
  Future<void> clearNotes(String providerId) async {
    final row = _rows[providerId];
    if (row != null) _rows[providerId] = row.copyWith(clearNote: true);
    for (var i = 0; i < _events.length; i++) {
      final e = _events[i];
      if (e.providerId != providerId || e.refusalNote == null) continue;
      _events[i] = SalonValidationEvent(
        id: e.id,
        providerId: e.providerId,
        kind: e.kind,
        at: e.at,
        byAdmin: e.byAdmin,
        refusalCode: e.refusalCode,
      );
    }
  }
}

/// [compare] on two times, a null after any time whatever the direction
/// (`NULLS LAST`).
int _nullsLast(
  DateTime? a,
  DateTime? b,
  int Function(DateTime, DateTime) compare,
) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return compare(a, b);
}
