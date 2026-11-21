import 'dart:convert';

import '../access/membership_repository.dart';
import '../email/email_provider.dart';
import '../email/salon_purge_emails.dart';
import '../email/send_budget.dart';
import '../providers_repository.dart';
import '../storage/storage_service.dart';
import 'salon_purge_repository.dart';

/// The purge of a deleted owner's salon (B0.24, decisions 153–158), the
/// maintenance cron's fifth task, run LAST so a failure never stops the
/// security prunes. Design: docs/design/deleted-owner-salon-purge.md §6.
///
/// The steps, the modes, the time budget and the tripwire live here; every
/// statement lives behind [SalonPurgeRepository]. No SQL, no `dart_frog`.
///
/// **Safe by construction, in this order** (§6.5–§6.6):
/// - it ships as [SalonPurgeMode.rehearse]: the real statements against the
///   real rows, always rolled back, no e-mail, no clock;
/// - two independent checks: the repository's candidate SQL, then the
///   [_tripwire] on the locked rows, which throws — the run stops and the
///   cron answers 500;
/// - a file another salon's document references is never deleted;
/// - the first real run is limited to one salon (`SALON_PURGE_MAX_PER_RUN`).
class SalonPurgeService {
  SalonPurgeService(
    this._repo,
    this._storage,
    this._notifier, {
    required this.mode,
    this.maxPerRun = kDefaultMaxPerRun,
    this.retention = kSalonPurgeRetention,
    Duration Function()? elapsed,
    void Function(String)? log,
  }) : _elapsed = elapsed,
       _log = log ?? print;

  /// Ten a night (§6.3); the first real run is set to 1 by the manifest.
  static const kDefaultMaxPerRun = 10;

  /// No new salon starts after this much of the purge's own time (§6.3).
  static const kSalonBudget = Duration(seconds: 60);

  /// No new file deletion after this much (§6.3). The job's attempt
  /// deadline is 180 s with no retries.
  static const kFileBudget = Duration(seconds: 90);

  /// The actor of the `salon.purge` audit row.
  static const kActor = 'system:salon-purge';

  /// What every finished run's line starts with (§6.9). The rehearsal reads
  /// filter on it, so the spec's and DEPLOYMENT.md's read commands are pinned
  /// to it by `salon_purge_wiring_test.dart`.
  static const kSummaryPrefix = 'salon_purge summary ';

  final SalonPurgeRepository _repo;
  final StorageService _storage;
  final SalonPurgeNotifier _notifier;
  final SalonPurgeMode mode;
  final int maxPerRun;
  final Duration retention;

  /// Injected in tests; a stopwatch started at [run] otherwise.
  final Duration Function()? _elapsed;
  final void Function(String) _log;

  /// One run, at [now]. Ids and counts only in the answer — never a name,
  /// an e-mail or a phone (T84).
  ///
  /// The answer is also logged, as one line of JSON after [kSummaryPrefix]
  /// (§6.9): the cron's response reaches only Cloud Scheduler, which keeps
  /// the status, so without the line a rehearsal could not be read. Every
  /// mode logs it, `off` too, so a night without one is a run that did not
  /// finish. A run that throws logs none: its 500 is that night's signal.
  Future<Map<String, Object?>> run(DateTime now) async {
    final answer = await _run(now);
    _log('$kSummaryPrefix${jsonEncode(answer)}');
    return answer;
  }

  Future<Map<String, Object?>> _run(DateTime now) async {
    if (mode == SalonPurgeMode.off) return {'mode': 'off'};
    final execute = mode == SalonPurgeMode.execute;
    final watch = Stopwatch()..start();
    Duration elapsed() => _elapsed?.call() ?? watch.elapsed;
    var budgetHit = false;

    // 0 — a salon caught in a creation's ownerless instant, owned since, or
    // gone: off the queue (counted only while rehearsing).
    final unqueued = await _repo.staleQueueRows(apply: execute);

    // 1 — record and start clocks (execute only).
    final toRecord = await _repo.ownerlessNotQueued();
    final noClock = await _repo.queuedWithoutClock();
    var clocksStarted = 0;
    final recorded = <String>[];
    if (execute) {
      for (final id in {...toRecord, ...noClock}) {
        if (await _repo.recordAndStartClock(id, now)) {
          clocksStarted++;
          if (toRecord.contains(id)) recorded.add(id);
          await _notifier.clockStarted(id, now.add(retention));
        }
      }
    }

    // 2 — the reminder, claimed before it is sent (execute only).
    var reminded = 0;
    if (execute) {
      final claimed = await _repo.claimReminders(
        now,
        retention: retention,
        lead: kSalonPurgeReminderLead,
      );
      for (final r in claimed) {
        await _notifier.reminder(r.providerId, r.dueAt, now);
        reminded++;
      }
    }

    // 3 — choose.
    final limit = maxPerRun < 0 ? 0 : maxPerRun;
    final candidates = execute
        ? await _repo.dueCandidates(now, retention: retention, limit: limit)
        : await _repo.rehearsalCandidates(limit: limit);

    // 4 — one transaction per salon; the tripwire may throw, which stops
    // the run here (a 500 the cron alert sees).
    final done = <({String id, Map<String, int> counts})>[];
    final postponed = <({String id, String reason})>[];
    final skipped = <({String id, String reason})>[];
    final purgedThisRun = <String>{};
    final rehearsedObjects = <String, List<PurgeObject>>{};
    for (final id in candidates) {
      if (elapsed() >= kSalonBudget) {
        budgetHit = true;
        break;
      }
      final outcome = await _repo.purgeOne(
        id,
        commit: execute,
        queued: execute,
        guard: _tripwire,
        audit: (action: 'salon.purge', actor: kActor),
      );
      switch (outcome) {
        case PurgeDone(:final counts, :final objects):
          done.add((id: id, counts: counts));
          if (execute) {
            purgedThisRun.add(id);
          } else {
            rehearsedObjects[id] = objects;
          }
        case PurgePostponed(:final reason):
          postponed.add((id: id, reason: reason));
        case PurgeSkipped(:final reason):
          skipped.add((id: id, reason: reason));
      }
    }

    // 5 — files. The shared-file rule reads every salon's document once.
    var objectsDeleted = 0;
    var objectsWouldDelete = 0;
    var keptShared = 0;
    var objectsLeft = 0;
    final docs = await _repo.documentKeysBySalon();
    bool sharedWithAnother(String salonId, String key) =>
        docs.entries.any((e) => e.key != salonId && e.value.contains(key));

    // Rehearsing: list only — what would go, what would be kept.
    var listFailed = 0;
    for (final MapEntry(key: id, value: objects) in rehearsedObjects.entries) {
      final List<PurgeObject> candidatesFor;
      try {
        candidatesFor = await _fileCandidates(id, objects);
      } catch (e) {
        // Storage down while rehearsing: reported, never the run's 500 —
        // only the tripwire may stop a run.
        _log('salon_purge_list_failed id=$id ${e.runtimeType}');
        listFailed++;
        continue;
      }
      for (final o in candidatesFor) {
        if (o.bucket == StorageBucket.public && sharedWithAnother(id, o.key)) {
          keptShared++;
        } else {
          objectsWouldDelete++;
        }
      }
    }

    final purged = execute ? await _repo.purgedRows() : const <PurgedRow>[];
    final filesDoneBefore = {
      for (final r in purged)
        if (r.pendingObjects.isEmpty && !purgedThisRun.contains(r.providerId))
          r.providerId,
    };
    for (final row in purged) {
      List<PurgeObject> pending;
      try {
        pending = await _fileCandidates(row.providerId, row.pendingObjects);
      } catch (e) {
        // The listing failed (storage down): everything stays pending, the
        // next run tries again.
        _log('salon_purge_list_failed id=${row.providerId} ${e.runtimeType}');
        objectsLeft += row.pendingObjects.length;
        listFailed++;
        continue;
      }
      final left = <PurgeObject>[];
      for (final o in pending) {
        if (o.bucket == StorageBucket.public &&
            sharedWithAnother(row.providerId, o.key)) {
          // Another salon's photo too: kept, reported, never deleted later.
          keptShared++;
          continue;
        }
        if (elapsed() >= kFileBudget) {
          budgetHit = true;
          left.add(o);
          continue;
        }
        try {
          await _storage.deleteObject(key: o.key, bucket: o.bucket);
          objectsDeleted++;
        } catch (e) {
          _log(
            'salon_purge_delete_failed id=${row.providerId} '
            '${e.runtimeType}',
          );
          left.add(o);
        }
      }
      objectsLeft += left.length;
      await _repo.setPendingObjects(row.providerId, left);
    }

    // 6 — the next-day pass, for the salons purged BEFORE this run: the
    // rows a write slipped in beside the purge; then, once their files were
    // done by an earlier run, the queue row goes.
    var stragglers = 0;
    for (final row in purged) {
      if (purgedThisRun.contains(row.providerId)) continue;
      stragglers += await _repo.sweepStragglers(row.providerId, apply: true);
      if (filesDoneBefore.contains(row.providerId)) {
        await _repo.dequeue(row.providerId);
      }
    }

    // 7–8 — the deleted accounts' reasons, and the Clients search text in
    // every salon (decisions 158 and 157). Counted only while rehearsing.
    final reasonsErased = await _repo.eraseDeletedAccountReasons(
      now,
      retention: retention,
      apply: execute,
    );
    final queriesScrubbed = await _repo.scrubSearchText(
      now,
      retention: retention,
      apply: execute,
    );

    return {
      'mode': mode.name,
      'unqueued': unqueued.length,
      if (execute) 'recorded': recorded else 'wouldRecord': toRecord,
      if (execute)
        'clocksStarted': clocksStarted
      else
        'wouldStartClocks': noClock.length + toRecord.length,
      'reminded': reminded,
      execute ? 'purged' : 'rehearsed': [
        for (final d in done) {'id': d.id, 'counts': d.counts},
      ],
      'postponed': [
        for (final p in postponed) {'id': p.id, 'reason': p.reason},
      ],
      'skipped': [
        for (final s in skipped) {'id': s.id, 'reason': s.reason},
      ],
      if (execute)
        'objectsDeleted': objectsDeleted
      else
        'objectsWouldDelete': objectsWouldDelete,
      'keptShared': keptShared,
      'objectsLeft': objectsLeft,
      'stragglers': stragglers,
      execute ? 'reasonsErased' : 'reasonsWouldErase': reasonsErased,
      execute ? 'queriesScrubbed' : 'queriesWouldScrub': queriesScrubbed,
      'listFailed': listFailed,
      'budgetHit': budgetHit,
    };
  }

  /// §6.5's second check, on the rows the transaction LOCKED — independent
  /// of the candidate SQL. A live, linked, owned or demo salon here means the
  /// predicate is wrong: throw, so nothing of it is committed and the run
  /// stops. An open dispute is a legitimate state: postpone (§5.1).
  PurgeVerdict _tripwire(LockedSalon s) {
    final hits = [
      if (s.status == 'active') 'active',
      if (s.linked) 'linked',
      if (s.activeOwner) 'active_owner',
      if (s.demo) 'demo',
    ];
    if (hits.isNotEmpty) {
      _log('salon_purge_tripwire id=${s.providerId} ${hits.join(',')}');
      throw SalonPurgeTripwire(s.providerId, hits);
    }
    return s.openDisputes > 0 ? PurgeVerdict.postpone : PurgeVerdict.proceed;
  }

  /// The files to delete for a purged salon (§4.4): the listing of its two
  /// public prefixes, plus [referenced] — kept only inside the four
  /// prefixes, in their own buckets. `pending/` (the lifecycle rule's) and
  /// `kyc/` (the deletion's) are never touched.
  Future<List<PurgeObject>> _fileCandidates(
    String id,
    List<PurgeObject> referenced,
  ) async {
    final out = <String, PurgeObject>{};
    for (final prefix in ['gallery/$id/', 'logo/$id/']) {
      for (final key in await _storage.listKeys(
        prefix: prefix,
        bucket: StorageBucket.public,
      )) {
        if (_allowed(key, StorageBucket.public)) {
          out['public:$key'] = (bucket: StorageBucket.public, key: key);
        }
      }
    }
    for (final o in referenced) {
      if (_allowed(o.key, o.bucket)) out['${o.bucket.name}:${o.key}'] = o;
    }
    return out.values.toList();
  }

  static bool _allowed(String key, StorageBucket bucket) {
    if (key.isEmpty || key.split('/').any((s) => s == '..' || s.isEmpty)) {
      return false;
    }
    return switch (bucket) {
      StorageBucket.public =>
        key.startsWith('gallery/') ||
            key.startsWith('logo/') ||
            key.startsWith('review/'),
      StorageBucket.deposit => key.startsWith('deposit/'),
      StorageBucket.kyc => false,
    };
  }
}

/// The tripwire fired: the candidate predicate let through a salon that is
/// live, linked, owned or the demo. Nothing of it was committed; the run
/// stopped. Escapes to the cron route — a 500.
class SalonPurgeTripwire implements Exception {
  SalonPurgeTripwire(this.providerId, this.hits);
  final String providerId;
  final List<String> hits;

  @override
  String toString() =>
      'SalonPurgeTripwire: $providerId (${hits.join(', ')}) — the purge '
      'stopped; nothing of this salon was committed';
}

/// Decision 156's two e-mails, to the salon's **active** members at an
/// address. Best effort: a failure is logged as a count and never stops the
/// deletion or the job.
class SalonPurgeNotifier {
  SalonPurgeNotifier(
    this._members,
    this._providers,
    this._email, {
    void Function(String)? log,
  }) : _log = log ?? print;

  final MembershipRepository _members;
  final ProvidersRepository _providers;
  final EmailProvider _email;
  final void Function(String) _log;

  /// When the clock starts: « {Salon} sera supprimé le {date} ».
  Future<int> clockStarted(String providerId, DateTime dueAt) =>
      _send(providerId, dueAt, reminderAt: null);

  /// Seven days before: « {Salon} sera supprimé dans 7 jours ».
  Future<int> reminder(String providerId, DateTime dueAt, DateTime now) =>
      _send(providerId, dueAt, reminderAt: now);

  Future<int> _send(
    String providerId,
    DateTime dueAt, {
    required DateTime? reminderAt,
  }) async {
    var sent = 0;
    try {
      final salon = await _providers.byId(providerId);
      final name = (salon?['name'] as String?)?.trim();
      final salonName = name == null || name.isEmpty ? 'votre salon' : name;
      final day = salonPurgeDay(dueAt, salon?['timezone'] as String?);
      final subject = reminderAt == null
          ? salonPurgeNoticeSubject(salonName, day)
          : salonPurgeReminderSubject(
              salonName,
              (dueAt.difference(reminderAt).inHours / 24).ceil(),
            );
      final members = await _members.listForProvider(providerId);
      final to = {
        for (final m in members)
          // Only to an address: a phone-registered owner's row holds a phone
          // in `email` (salon_notifier.dart).
          if (m.status == 'active' && m.emailOrNull != null) m.emailOrNull!,
      };
      for (final address in to) {
        final r = await _email.send(
          to: address,
          subject: subject,
          text: renderSalonPurgeText(salonName, day),
          html: renderSalonPurgeHtml(salonName, day),
          // About the members' own salon, chosen by no anonymous caller.
          classification: EmailClass.warm,
        );
        if (r.ok) sent++;
      }
      if (sent < to.length) {
        _log(
          'salon_purge_email_failed id=$providerId '
          'failed=${to.length - sent}',
        );
      }
    } catch (e) {
      _log('salon_purge_email_failed id=$providerId ${e.runtimeType}');
    }
    return sent;
  }
}
