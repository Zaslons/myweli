import '../storage/storage_service.dart';

/// The storage half of the salon purge (B0.24, decisions 153–158).
///
/// Every statement of docs/design/deleted-owner-salon-purge.md §4 lives behind
/// this interface; the steps, the modes, the time budget and the tripwire live
/// in `SalonPurgeService`, which holds no SQL.
///
/// « Ownerless » everywhere below means what the job's own definition says
/// (§6.3): no `provider_users.provider_id` link to the salon, no active
/// `owner` row in `provider_members`, and not the demo salon
/// (`demo_snapshot.provider_id`).

/// How the job runs, from `SALON_PURGE_MODE` (§6.3).
enum SalonPurgeMode {
  /// Nothing at all: the response says so.
  off,

  /// The default. Every statement runs against the real rows, in a
  /// transaction that is always rolled back; nothing is written, no e-mail
  /// goes, no clock starts.
  rehearse,

  /// Real purges. Switched on only on the owner's yes, after the rehearsals
  /// are read (§6.6 step 4).
  execute;

  /// Unset → [rehearse]. **An unknown value is [rehearse] too, never
  /// [execute]**: a typo must not delete anything. The caller logs the
  /// unknown value.
  static SalonPurgeMode parse(String? raw) {
    final v = raw?.trim().toLowerCase();
    for (final m in values) {
      if (m.name == v) return m;
    }
    return rehearse;
  }
}

/// Decision 153: 90 days from the clock's start. The texts that state it
/// (`/pro/suppression-compte`, the policy, Data safety) change only once real
/// purges run, and a test then pins them against this constant.
const Duration kSalonPurgeRetention = Duration(days: 90);

/// Decision 156: the reminder goes 7 days before the due day.
const Duration kSalonPurgeReminderLead = Duration(days: 7);

/// The audit row a purge writes (§6.3 step 4.8). A record with a named
/// `action:` so the admin console's label test sees the code.
typedef SalonPurgeAudit = ({String action, String actor});

/// One object to delete, in one bucket.
typedef PurgeObject = ({StorageBucket bucket, String key});

/// What the tripwire reads, from the rows the purge's transaction has
/// LOCKED (§6.5). Any of the four first flags set is a wrong predicate.
typedef LockedSalon = ({
  String providerId,
  String status,
  bool linked,
  bool activeOwner,
  bool demo,
  int openDisputes,
});

/// The tripwire's answer for a salon that may be purged.
enum PurgeVerdict { proceed, postpone }

/// What one salon's transaction did (§6.3 step 4).
sealed class PurgeOutcome {
  const PurgeOutcome();
}

/// The rows went (or, rehearsing, would have gone). [counts] holds numbers
/// only, by table; [objects] are the files its rows referenced, to delete
/// after the transaction (§4.4).
final class PurgeDone extends PurgeOutcome {
  const PurgeDone(this.counts, this.objects);
  final Map<String, int> counts;
  final List<PurgeObject> objects;
}

/// The tripwire said wait: an open dispute (§5.1). Nothing changed.
final class PurgePostponed extends PurgeOutcome {
  const PurgePostponed(this.reason);
  final String reason;
}

/// Not this run's: another run holds its queue row, the row is already
/// purged, or the salon no longer exists. Nothing changed.
final class PurgeSkipped extends PurgeOutcome {
  const PurgeSkipped(this.reason);
  final String reason;
}

/// A salon whose rows are purged and whose queue row still waits for its
/// files and its next-day pass (§6.3 steps 5–6).
typedef PurgedRow = ({
  String providerId,
  DateTime rowsPurgedAt,
  List<PurgeObject> pendingObjects,
});

/// A reminder claimed for sending (§6.3 step 2).
typedef ClaimedReminder = ({String providerId, DateTime dueAt});

abstract interface class SalonPurgeRepository {
  /// Step 0: queue rows not yet purged whose salon has an owner again, is
  /// the demo salon, or no longer exists. Deleted when [apply]; counted
  /// otherwise. Answers their ids.
  Future<List<String>> staleQueueRows({required bool apply});

  /// Step 1: ownerless salons with no queue row, by id.
  Future<List<String>> ownerlessNotQueued();

  /// Step 1: queued, not purged, still ownerless, and no clock yet (stamped
  /// while the job only rehearsed), by id.
  Future<List<String>> queuedWithoutClock();

  /// Step 1, `execute` only: queues [providerId] with both dates at [now]
  /// (`ON CONFLICT DO NOTHING`), or starts the clock of its existing row
  /// that has none. True when a clock started here.
  Future<bool> recordAndStartClock(String providerId, DateTime now);

  /// Step 2, `execute` only: claims, at most once each, the reminders of the
  /// rows due within [lead] that are not purged and still ownerless
  /// (re-checked in the same statement). Claimed before sent, so one is never
  /// sent twice; a lost e-mail is not resent.
  Future<List<ClaimedReminder>> claimReminders(
    DateTime now, {
    required Duration retention,
    required Duration lead,
  });

  /// Step 3, `execute`: queue rows whose clock started more than [retention]
  /// before [now], not purged, whose salon exists, is not `active` and is
  /// ownerless — oldest clock first, at most [limit].
  Future<List<String>> dueCandidates(
    DateTime now, {
    required Duration retention,
    required int limit,
  });

  /// Step 3, `rehearse`: every ownerless salon that is not `active`, queued
  /// or not, due or not — by id, at most [limit].
  Future<List<String>> rehearsalCandidates({required int limit});

  /// Step 4: one salon, one transaction. Locks its queue row
  /// `FOR UPDATE SKIP LOCKED` when [queued], then the salon row; hands
  /// [guard] what it locked (the tripwire may throw, which rolls everything
  /// back and escapes); then runs every statement of §4.1–§4.2 and writes
  /// [audit]. Commits when [commit], otherwise **always rolls back** —
  /// the counts are what each statement affected either way.
  Future<PurgeOutcome> purgeOne(
    String providerId, {
    required bool commit,
    required bool queued,
    required PurgeVerdict Function(LockedSalon) guard,
    required SalonPurgeAudit audit,
  });

  /// Steps 5–6: the rows already purged, waiting for files or their pass.
  Future<List<PurgedRow>> purgedRows();

  /// Step 5: what is left to delete for [providerId].
  Future<void> setPendingObjects(String providerId, List<PurgeObject> left);

  /// Step 5's shared-file rule: the keys each salon's document references,
  /// by salon id, read through the stored string (§4.4).
  Future<Map<String, Set<String>>> documentKeysBySalon();

  /// Step 6: runs step 4.7's deletes again for an already purged id, to
  /// catch a row written beside the purge. Answers how many rows it found;
  /// deletes them when [apply].
  Future<int> sweepStragglers(String providerId, {required bool apply});

  /// Step 6: the salon is done — rows, pass and files.
  Future<void> dequeue(String providerId);

  /// Step 7 (§4.2): `reason = NULL` on the `provider_account` rows of
  /// accounts that no longer exist, older than [retention], but
  /// `provider_account.erase`. Applied when [apply], counted otherwise.
  Future<int> eraseDeletedAccountReasons(
    DateTime now, {
    required Duration retention,
    required bool apply,
  });

  /// Step 8 (decision 157): the `query` key removed from the `clients.list`
  /// rows older than [retention], in every salon, the row kept. Applied
  /// when [apply], counted otherwise.
  Future<int> scrubSearchText(
    DateTime now, {
    required Duration retention,
    required bool apply,
  });

  /// The deletion's stamp (§6.2): queues [providerId], **overwriting** a row
  /// left by a creation's ownerless instant. Its clock starts at [now] only
  /// when [startClock] (real purges on); the reminder is cleared.
  Future<void> stampDeletion(
    String providerId,
    DateTime now, {
    required bool startClock,
  });
}

/// The repository without a database (dev, and the service tests).
///
/// **Scripted, not a replica.** An in-memory copy of every purge statement
/// over the fifteen in-memory repositories would prove nothing about the SQL
/// — the twins have no foreign keys, no locks and no transactions, which is
/// exactly what the purge rests on. So the SQL is proven on real Postgres
/// (`test/db/postgres_salon_purge_test.dart`, its own database), and this
/// twin drives the service's logic: a test fills [salons] and the queue,
/// and reads back what the service asked for. Built empty, as in dev, it
/// finds no salon and the job answers zeros.
class InMemorySalonPurgeRepository implements SalonPurgeRepository {
  /// The salons this twin knows, by id.
  final Map<String, FakePurgeSalon> salons = {};

  /// The queue, by salon id.
  final Map<String, FakeQueueRow> queue = {};

  /// Every `purgeOne` call, in order: `(id, commit)`.
  final List<(String, bool)> purgeCalls = [];

  /// Thrown from [purgeOne] after the guard, to simulate a crash.
  Object? purgeThrows;

  bool _ownerless(FakePurgeSalon s) => !s.linked && !s.activeOwner && !s.demo;

  @override
  Future<List<String>> staleQueueRows({required bool apply}) async {
    final stale = [
      for (final MapEntry(:key, :value) in queue.entries)
        if (value.rowsPurgedAt == null &&
            (salons[key] == null || !_ownerless(salons[key]!)))
          key,
    ]..sort();
    if (apply) stale.forEach(queue.remove);
    return stale;
  }

  @override
  Future<List<String>> ownerlessNotQueued() async => [
    for (final s in salons.values)
      if (s.status != 'active' && _ownerless(s) && !queue.containsKey(s.id))
        s.id,
  ]..sort();

  @override
  Future<List<String>> queuedWithoutClock() async => [
    for (final MapEntry(:key, :value) in queue.entries)
      if (value.rowsPurgedAt == null &&
          value.clockStartedAt == null &&
          salons[key] != null &&
          salons[key]!.status != 'active' &&
          _ownerless(salons[key]!))
        key,
  ]..sort();

  @override
  Future<bool> recordAndStartClock(String providerId, DateTime now) async {
    final row = queue[providerId];
    if (row == null) {
      queue[providerId] = FakeQueueRow(ownerErasedAt: now, clockStartedAt: now);
      return true;
    }
    if (row.clockStartedAt != null) return false;
    row.clockStartedAt = now;
    return true;
  }

  @override
  Future<List<ClaimedReminder>> claimReminders(
    DateTime now, {
    required Duration retention,
    required Duration lead,
  }) async {
    final out = <ClaimedReminder>[];
    for (final MapEntry(:key, :value) in queue.entries) {
      final clock = value.clockStartedAt;
      final s = salons[key];
      if (clock == null || value.reminderSentAt != null) continue;
      if (value.rowsPurgedAt != null || s == null) continue;
      if (s.status == 'active' || !_ownerless(s)) continue;
      final due = clock.add(retention);
      // Due within [lead] and still ahead, as the SQL reads it.
      if (due.subtract(lead).isAfter(now) || !due.isAfter(now)) continue;
      value.reminderSentAt = now;
      out.add((providerId: key, dueAt: due));
    }
    return out..sort((a, b) => a.providerId.compareTo(b.providerId));
  }

  @override
  Future<List<String>> dueCandidates(
    DateTime now, {
    required Duration retention,
    required int limit,
  }) async {
    final due =
        [
          for (final MapEntry(:key, :value) in queue.entries)
            if (value.rowsPurgedAt == null &&
                value.clockStartedAt != null &&
                value.clockStartedAt!.isBefore(now.subtract(retention)) &&
                salons[key] != null &&
                salons[key]!.status != 'active' &&
                _ownerless(salons[key]!))
              key,
        ]..sort(
          (a, b) =>
              queue[a]!.clockStartedAt!.compareTo(queue[b]!.clockStartedAt!),
        );
    return due.take(limit).toList();
  }

  @override
  Future<List<String>> rehearsalCandidates({required int limit}) async => ([
    for (final s in salons.values)
      if (s.status != 'active' && _ownerless(s)) s.id,
  ]..sort()).take(limit).toList();

  @override
  Future<PurgeOutcome> purgeOne(
    String providerId, {
    required bool commit,
    required bool queued,
    required PurgeVerdict Function(LockedSalon) guard,
    required SalonPurgeAudit audit,
  }) async {
    purgeCalls.add((providerId, commit));
    final s = salons[providerId];
    if (s == null) return const PurgeSkipped('gone');
    if (queued && queue[providerId]?.rowsPurgedAt != null) {
      return const PurgeSkipped('already_purged');
    }
    final verdict = guard((
      providerId: s.id,
      status: s.status,
      linked: s.linked,
      activeOwner: s.activeOwner,
      demo: s.demo,
      openDisputes: s.openDisputes,
    ));
    if (verdict == PurgeVerdict.postpone) {
      return const PurgePostponed('open_dispute');
    }
    if (purgeThrows != null) throw purgeThrows!;
    final done = PurgeDone({'providers': 1, ...s.counts}, [...s.objects]);
    if (commit) {
      salons.remove(providerId);
      auditRows.add((action: audit.action, actor: audit.actor, id: providerId));
      final row = queue[providerId];
      if (row != null) {
        row.rowsPurgedAt = DateTime.now().toUtc();
        row.pendingObjects = [...s.objects];
      }
    }
    return done;
  }

  /// The `salon.purge` rows written.
  final List<({String action, String actor, String id})> auditRows = [];

  @override
  Future<List<PurgedRow>> purgedRows() async => [
    for (final MapEntry(:key, :value) in queue.entries)
      if (value.rowsPurgedAt != null)
        (
          providerId: key,
          rowsPurgedAt: value.rowsPurgedAt!,
          pendingObjects: [...value.pendingObjects],
        ),
  ]..sort((a, b) => a.providerId.compareTo(b.providerId));

  @override
  Future<void> setPendingObjects(
    String providerId,
    List<PurgeObject> left,
  ) async => queue[providerId]?.pendingObjects = [...left];

  /// Keys referenced by documents of salons that are NOT in [salons] (a
  /// live salon's photo, for the shared-file rule), by salon id.
  final Map<String, Set<String>> otherDocuments = {};

  @override
  Future<Map<String, Set<String>>> documentKeysBySalon() async => {
    for (final s in salons.values) s.id: s.documentKeys,
    ...otherDocuments,
  };

  /// Rows a test planted beside a purge, by salon id (step 6).
  final Map<String, int> stragglers = {};

  @override
  Future<int> sweepStragglers(String providerId, {required bool apply}) async {
    final n = stragglers[providerId] ?? 0;
    if (apply) stragglers.remove(providerId);
    return n;
  }

  @override
  Future<void> dequeue(String providerId) async => queue.remove(providerId);

  /// What steps 7 and 8 report; a test sets them.
  int accountReasons = 0;
  int searchQueries = 0;
  final List<String> appliedSteps = [];

  @override
  Future<int> eraseDeletedAccountReasons(
    DateTime now, {
    required Duration retention,
    required bool apply,
  }) async {
    if (apply) appliedSteps.add('reasons');
    return accountReasons;
  }

  @override
  Future<int> scrubSearchText(
    DateTime now, {
    required Duration retention,
    required bool apply,
  }) async {
    if (apply) appliedSteps.add('queries');
    return searchQueries;
  }

  /// Every stamp, in order.
  final List<({String id, bool startClock})> stamps = [];

  /// Thrown from [stampDeletion], to prove the deletion tolerates it.
  Object? stampThrows;

  @override
  Future<void> stampDeletion(
    String providerId,
    DateTime now, {
    required bool startClock,
  }) async {
    if (stampThrows != null) throw stampThrows!;
    stamps.add((id: providerId, startClock: startClock));
    queue[providerId] = FakeQueueRow(
      ownerErasedAt: now,
      clockStartedAt: startClock ? now : null,
    );
  }
}

/// A salon as [InMemorySalonPurgeRepository] sees it.
class FakePurgeSalon {
  FakePurgeSalon(
    this.id, {
    this.status = 'draft',
    this.linked = false,
    this.activeOwner = false,
    this.demo = false,
    this.openDisputes = 0,
    Map<String, int>? counts,
    List<PurgeObject>? objects,
    Set<String>? documentKeys,
  }) : counts = counts ?? const {},
       objects = objects ?? const [],
       documentKeys = documentKeys ?? const {};

  final String id;
  String status;
  bool linked;
  bool activeOwner;
  bool demo;
  int openDisputes;
  final Map<String, int> counts;
  final List<PurgeObject> objects;
  final Set<String> documentKeys;
}

/// A queue row as [InMemorySalonPurgeRepository] holds it.
class FakeQueueRow {
  FakeQueueRow({
    required this.ownerErasedAt,
    this.clockStartedAt,
    this.reminderSentAt,
    this.rowsPurgedAt,
    List<PurgeObject>? pendingObjects,
  }) : pendingObjects = pendingObjects ?? [];

  final DateTime ownerErasedAt;
  DateTime? clockStartedAt;
  DateTime? reminderSentAt;
  DateTime? rowsPurgedAt;
  List<PurgeObject> pendingObjects;
}
