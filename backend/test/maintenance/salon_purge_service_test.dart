import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:myweli_backend/src/maintenance/salon_purge_repository.dart';
import 'package:myweli_backend/src/maintenance/salon_purge_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

/// The purge's STEPS, on the scripted repository
/// (docs/design/deleted-owner-salon-purge.md §6.3–§6.5, §9): the modes, the
/// tripwire, the postponement, the budget, the files and their shared-file
/// rule, the next-day pass, the e-mails. The SQL itself is proven on real
/// Postgres in `test/db/postgres_salon_purge_test.dart`.
void main() {
  final now = DateTime.utc(2027, 3, 1, 3, 30);
  final started = now.subtract(const Duration(days: 91));

  late InMemorySalonPurgeRepository repo;
  late FakeStorageService storage;
  late _Members members;
  late _Mail mail;
  late List<String> logs;

  setUp(() {
    repo = InMemorySalonPurgeRepository();
    storage = FakeStorageService();
    members = _Members();
    mail = _Mail();
    logs = [];
  });

  SalonPurgeService service(
    SalonPurgeMode mode, {
    int max = 10,
    Duration Function()? elapsed,
  }) => SalonPurgeService(
    repo,
    storage,
    SalonPurgeNotifier(
      members,
      InMemoryProvidersRepository([
        {'id': 's1', 'name': 'Chez <Awa>', 'timezone': 'Africa/Abidjan'},
        {'id': 's2', 'name': 'Salon Deux', 'timezone': 'Africa/Abidjan'},
      ]),
      mail,
      log: logs.add,
    ),
    mode: mode,
    maxPerRun: max,
    elapsed: elapsed,
    log: logs.add,
  );

  /// A salon due for its purge: queued, its clock 91 days old.
  void due(String id, {Map<String, int>? counts, List<PurgeObject>? objects}) {
    repo.salons[id] = FakePurgeSalon(id, counts: counts, objects: objects);
    repo.queue[id] = FakeQueueRow(
      ownerErasedAt: started,
      clockStartedAt: started,
    );
  }

  group('off', () {
    test('does nothing and says so', () async {
      due('s1');
      expect(await service(SalonPurgeMode.off).run(now), {'mode': 'off'});
      expect(repo.purgeCalls, isEmpty);
      expect(repo.queue['s1']!.rowsPurgedAt, isNull);
    });
  });

  group('rehearse (the default) — writes nothing, sends nothing', () {
    test('every ownerless salon is rehearsed, rolled back, queued or not, '
        'due or not', () async {
      repo.salons['s1'] = FakePurgeSalon('s1', counts: {'services': 2});
      repo.salons['s2'] = FakePurgeSalon('s2');
      repo.queue['s2'] = FakeQueueRow(ownerErasedAt: now);
      members.rows['s1'] = [_member('s1', 'a@x.com')];
      final body = await service(SalonPurgeMode.rehearse).run(now);
      expect(repo.purgeCalls, [('s1', false), ('s2', false)]);
      expect(body['mode'], 'rehearse');
      expect(body['rehearsed'], [
        {
          'id': 's1',
          'counts': {'providers': 1, 'services': 2},
        },
        {
          'id': 's2',
          'counts': {'providers': 1},
        },
      ]);
      expect(body['wouldRecord'], ['s1']);
      expect(body.containsKey('purged'), isFalse);
      // Nothing written: no clock, no new queue row, no e-mail.
      expect(repo.queue.keys, ['s2']);
      expect(repo.queue['s2']!.clockStartedAt, isNull);
      expect(repo.salons.keys, containsAll(['s1', 's2']));
      expect(repo.auditRows, isEmpty);
      expect(mail.sent, isEmpty);
      expect(repo.appliedSteps, isEmpty, reason: 'steps 7–8 only count');
    });

    test('a stale queue row is only counted', () async {
      repo.salons['s1'] = FakePurgeSalon('s1', linked: true);
      repo.queue['s1'] = FakeQueueRow(ownerErasedAt: now);
      final body = await service(SalonPurgeMode.rehearse).run(now);
      expect(body['unqueued'], 1);
      expect(repo.queue.containsKey('s1'), isTrue);
    });

    test('files are listed, never deleted; a shared one is reported', () async {
      repo.salons['s1'] = FakePurgeSalon(
        's1',
        objects: [(bucket: StorageBucket.public, key: 'gallery/s1/b.jpg')],
      );
      storage.listable[StorageBucket.public] = {
        'gallery/s1/a.jpg',
        'gallery/s1/b.jpg',
      };
      repo.otherDocuments['live'] = {'gallery/s1/b.jpg'};
      final body = await service(SalonPurgeMode.rehearse).run(now);
      expect(body['objectsWouldDelete'], 1);
      expect(body['keptShared'], 1);
      expect(storage.deleted, isEmpty);
    });

    test('storage down while rehearsing is reported, not a 500', () async {
      repo.salons['s1'] = FakePurgeSalon('s1');
      storage.ioThrows = StateError('down');
      final body = await service(SalonPurgeMode.rehearse).run(now);
      expect(body['listFailed'], 1);
    });
  });

  group('execute — test 1: a due salon is purged once', () {
    test('committed, audited once by the system actor, rows marked', () async {
      due('s1', counts: {'appointments': 3});
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(repo.purgeCalls, [('s1', true)]);
      expect(body['purged'], [
        {
          'id': 's1',
          'counts': {'providers': 1, 'appointments': 3},
        },
      ]);
      expect(repo.auditRows, [
        (action: 'salon.purge', actor: 'system:salon-purge', id: 's1'),
      ]);
      expect(repo.queue['s1']!.rowsPurgedAt, isNotNull);
      expect(repo.appliedSteps, ['reasons', 'queries']);
    });

    test('a second run purges nothing again', () async {
      due('s1');
      await service(SalonPurgeMode.execute).run(now);
      final again = await service(SalonPurgeMode.execute).run(now);
      expect(again['purged'], isEmpty);
      expect(repo.auditRows, hasLength(1));
    });
  });

  group('the tripwire (§6.5) — tests 3–6', () {
    for (final (name, salon) in [
      ('active', FakePurgeSalon('s1', status: 'active')),
      ('linked', FakePurgeSalon('s1', linked: true)),
      ('an active owner row', FakePurgeSalon('s1', activeOwner: true)),
      ('the demo salon', FakePurgeSalon('s1', demo: true)),
    ]) {
      test('$name, handed in by a wrong candidate query → it throws, the run '
          'stops, nothing committed', () async {
        // The twin's candidate read excludes such a salon, as the SQL does;
        // this one is forced in, which is what a widened predicate would do.
        final forced = _ForcedCandidates(repo, ['s1', 's2']);
        repo.salons['s1'] = salon;
        repo.salons['s2'] = FakePurgeSalon('s2');
        repo.queue['s2'] = FakeQueueRow(
          ownerErasedAt: started,
          clockStartedAt: started,
        );
        final svc = SalonPurgeService(
          forced,
          storage,
          SalonPurgeNotifier(members, InMemoryProvidersRepository([]), mail),
          mode: SalonPurgeMode.execute,
          log: logs.add,
        );
        await expectLater(svc.run(now), throwsA(isA<SalonPurgeTripwire>()));
        expect(repo.salons.containsKey('s1'), isTrue);
        expect(repo.purgeCalls.map((c) => c.$1), [
          's1',
        ], reason: 'the later salon is not processed');
        expect(repo.salons.containsKey('s2'), isTrue);
        expect(repo.auditRows, isEmpty);
        expect(logs.single, startsWith('salon_purge_tripwire id=s1 '));
      });
    }

    test('the same guard fires while rehearsing', () async {
      final forced = _ForcedCandidates(repo, ['s1']);
      repo.salons['s1'] = FakePurgeSalon('s1', linked: true);
      final svc = SalonPurgeService(
        forced,
        storage,
        SalonPurgeNotifier(members, InMemoryProvidersRepository([]), mail),
        mode: SalonPurgeMode.rehearse,
        log: logs.add,
      );
      await expectLater(svc.run(now), throwsA(isA<SalonPurgeTripwire>()));
    });
  });

  group('test 7: an open dispute postpones; nothing else does', () {
    test('postponed, untouched, reported every night', () async {
      due('s1');
      repo.salons['s1']!.openDisputes = 1;
      for (var night = 0; night < 2; night++) {
        final body = await service(SalonPurgeMode.execute).run(now);
        expect(body['postponed'], [
          {'id': 's1', 'reason': 'open_dispute'},
        ]);
      }
      expect(repo.salons.containsKey('s1'), isTrue);
      expect(repo.auditRows, isEmpty);
    });
  });

  group('the limit and the time budget (§6.3)', () {
    test('at most maxPerRun salons a night', () async {
      due('s1');
      due('s2');
      final body = await service(SalonPurgeMode.execute, max: 1).run(now);
      expect((body['purged']! as List).length, 1);
    });

    test('past 60 s, no new salon starts', () async {
      due('s1');
      final body = await service(
        SalonPurgeMode.execute,
        elapsed: () => const Duration(seconds: 61),
      ).run(now);
      expect(repo.purgeCalls, isEmpty);
      expect(body['budgetHit'], isTrue);
    });

    test('past 90 s, no new file deletion; the rest waits', () async {
      due(
        's1',
        objects: [(bucket: StorageBucket.public, key: 'gallery/s1/a.jpg')],
      );
      // The salon starts inside the budget; by its files, 91 s have passed.
      final body = await service(
        SalonPurgeMode.execute,
        elapsed: () => repo.purgeCalls.isEmpty
            ? Duration.zero
            : const Duration(seconds: 91),
      ).run(now);
      expect(body['purged'], hasLength(1));
      expect(storage.deleted, isEmpty);
      expect(body['objectsLeft'], 1);
      expect(body['budgetHit'], isTrue);
      expect(repo.queue['s1']!.pendingObjects, hasLength(1));
    });
  });

  group('files (§4.4) — tests 10, 12, 13', () {
    test('the two prefixes and the referenced keys go; a shared one stays, '
        'reported; nothing outside the four prefixes', () async {
      due(
        's1',
        objects: [
          (bucket: StorageBucket.public, key: 'review/u1/r.jpg'),
          (bucket: StorageBucket.deposit, key: 'deposit/u1/p.jpg'),
          (bucket: StorageBucket.public, key: 'pending/x.jpg'),
          (bucket: StorageBucket.kyc, key: 'kyc/a/doc.pdf'),
          (bucket: StorageBucket.public, key: 'other/s1/x.jpg'),
          (bucket: StorageBucket.public, key: 'gallery/s1/../../x.jpg'),
        ],
      );
      storage.listable[StorageBucket.public] = {
        'gallery/s1/a.jpg',
        'gallery/s1/shared.jpg',
        'logo/s1/l.jpg',
        'gallery/s10/not-mine.jpg',
      };
      repo.otherDocuments['live'] = {'gallery/s1/shared.jpg'};
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(
        storage.deleted,
        unorderedEquals([
          'gallery/s1/a.jpg',
          'logo/s1/l.jpg',
          'review/u1/r.jpg',
          'deposit/u1/p.jpg',
        ]),
      );
      expect(body['objectsDeleted'], 4);
      expect(body['keptShared'], 1);
      expect(body['objectsLeft'], 0);
    });

    test('test 10: storage down after the rows → the next run deletes the '
        'files and, a run later, the queue row', () async {
      due(
        's1',
        objects: [(bucket: StorageBucket.public, key: 'review/u1/r.jpg')],
      );
      storage.ioThrows = StateError('down');
      final first = await service(SalonPurgeMode.execute).run(now);
      expect(first['purged'], hasLength(1));
      expect(first['objectsLeft'], 1);
      expect(repo.queue['s1']!.pendingObjects, hasLength(1));

      storage.ioThrows = null;
      final second = await service(SalonPurgeMode.execute).run(now);
      expect(second['objectsDeleted'], 1);
      expect(
        repo.queue.containsKey('s1'),
        isTrue,
        reason: 'the queue row outlives this run',
      );

      await service(SalonPurgeMode.execute).run(now);
      expect(repo.queue.containsKey('s1'), isFalse);
    });
  });

  group('test 17: the next-day pass', () {
    test('sweeps a row written beside the purge, the night after', () async {
      due('s1');
      await service(SalonPurgeMode.execute).run(now);
      repo.stragglers['s1'] = 1;
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(body['stragglers'], 1);
      expect(repo.stragglers, isEmpty);
    });

    test('not in the night of the purge itself', () async {
      due('s1');
      repo.stragglers['s1'] = 1;
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(body['stragglers'], 0);
    });
  });

  group('test 16: the e-mails (decision 156)', () {
    test('none while rehearsing', () async {
      repo.salons['s1'] = FakePurgeSalon('s1');
      members.rows['s1'] = [_member('s1', 'a@x.com')];
      repo.queue['s1'] = FakeQueueRow(
        ownerErasedAt: started,
        clockStartedAt: now.subtract(const Duration(days: 85)),
      );
      await service(SalonPurgeMode.rehearse).run(now);
      expect(mail.sent, isEmpty);
    });

    test(
      'one when the clock starts, to the active members at an address',
      () async {
        repo.salons['s1'] = FakePurgeSalon('s1');
        members.rows['s1'] = [
          _member('s1', 'a@x.com'),
          _member('s1', '+2250700000000'),
          _member('s1', 'gone@x.com', status: 'revoked'),
          _member('s1', 'invited@x.com', status: 'invited'),
        ];
        final body = await service(SalonPurgeMode.execute).run(now);
        expect(body['recorded'], ['s1']);
        expect(body['clocksStarted'], 1);
        expect(mail.sent.map((m) => m.to), ['a@x.com']);
        expect(
          mail.sent.single.subject,
          'Chez <Awa> sera supprimé le 30 mai 2027',
        );
        expect(mail.sent.single.classification, EmailClass.warm);
        expect(mail.sent.single.html, contains('Chez &lt;Awa&gt;'));
        expect(repo.queue['s1']!.clockStartedAt, now);

        // The next night: the clock already started — no second e-mail.
        await service(
          SalonPurgeMode.execute,
        ).run(now.add(const Duration(days: 1)));
        expect(mail.sent, hasLength(1));
      },
    );

    test('a row stamped while rehearsing gets its clock, and its e-mail, on '
        'the first real night', () async {
      repo.salons['s1'] = FakePurgeSalon('s1');
      repo.queue['s1'] = FakeQueueRow(ownerErasedAt: started);
      members.rows['s1'] = [_member('s1', 'a@x.com')];
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(body['recorded'], isEmpty, reason: 'already queued');
      expect(body['clocksStarted'], 1);
      expect(mail.sent, hasLength(1));
    });

    test(
      'the reminder: once, 7 days before, claimed before it is sent',
      () async {
        repo.salons['s1'] = FakePurgeSalon('s1');
        members.rows['s1'] = [_member('s1', 'a@x.com')];
        repo.queue['s1'] = FakeQueueRow(
          ownerErasedAt: started,
          clockStartedAt: now.subtract(const Duration(days: 83)),
        );
        final body = await service(SalonPurgeMode.execute).run(now);
        expect(body['reminded'], 1);
        expect(
          mail.sent.single.subject,
          'Chez <Awa> sera supprimé dans 7 jours',
        );
        expect(repo.queue['s1']!.reminderSentAt, now);
        await service(SalonPurgeMode.execute).run(now);
        expect(mail.sent, hasLength(1), reason: 'never twice');
      },
    );

    test('a salon owned again gets no reminder', () async {
      repo.salons['s1'] = FakePurgeSalon('s1', activeOwner: true);
      members.rows['s1'] = [_member('s1', 'a@x.com')];
      repo.queue['s1'] = FakeQueueRow(
        ownerErasedAt: started,
        clockStartedAt: now.subtract(const Duration(days: 83)),
      );
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(body['reminded'], 0);
      expect(mail.sent, isEmpty);
      expect(body['unqueued'], 1);
    });

    test('a failed send is logged as a count and stops nothing', () async {
      repo.salons['s1'] = FakePurgeSalon('s1');
      members.rows['s1'] = [_member('s1', 'a@x.com')];
      mail.fail = true;
      final body = await service(SalonPurgeMode.execute).run(now);
      expect(body['clocksStarted'], 1);
      expect(logs, contains('salon_purge_email_failed id=s1 failed=1'));
    });
  });

  test(
    'the answer carries ids and counts only — no name, no address (T84)',
    () async {
      repo.salons['s1'] = FakePurgeSalon('s1');
      members.rows['s1'] = [_member('s1', 'a@x.com')];
      due('s2');
      final body = await service(SalonPurgeMode.execute).run(now);
      final text = body.toString();
      expect(text, isNot(contains('Awa')));
      expect(text, isNot(contains('Salon Deux')));
      expect(text, isNot(contains('@')));
    },
  );

  test(
    'SalonPurgeMode.parse: unset and unknown are rehearse, never execute',
    () {
      expect(SalonPurgeMode.parse(null), SalonPurgeMode.rehearse);
      expect(SalonPurgeMode.parse(''), SalonPurgeMode.rehearse);
      expect(SalonPurgeMode.parse('exectue'), SalonPurgeMode.rehearse);
      expect(SalonPurgeMode.parse(' Execute '), SalonPurgeMode.execute);
      expect(SalonPurgeMode.parse('off'), SalonPurgeMode.off);
    },
  );
}

Member _member(String salon, String email, {String status = 'active'}) =>
    Member(
      id: 'm_${email.hashCode}_$status',
      providerId: salon,
      email: email,
      role: 'staff',
      status: status,
      invitedAt: DateTime.utc(2026),
      accountId: status == 'invited' ? null : 'acct_$email',
    );

class _Members extends InMemoryMembershipRepository {
  final Map<String, List<Member>> rows = {};

  @override
  Future<List<Member>> listForProvider(String providerId) async =>
      rows[providerId] ?? const [];
}

class _Mail implements EmailProvider {
  final sent =
      <
        ({String to, String subject, String? html, EmailClass classification})
      >[];
  bool fail = false;

  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    required EmailClass classification,
    String? html,
  }) async {
    if (fail) return (ok: false, providerMessageId: null, error: 'down');
    sent.add((
      to: to,
      subject: subject,
      html: html,
      classification: classification,
    ));
    return (ok: true, providerMessageId: 'm${sent.length}', error: null);
  }
}

/// A candidate query widened on purpose: it hands in [ids] whatever they
/// are, so only the tripwire stands between them and a purge.
class _ForcedCandidates implements SalonPurgeRepository {
  _ForcedCandidates(this._inner, this._ids);
  final InMemorySalonPurgeRepository _inner;
  final List<String> _ids;

  @override
  Future<List<String>> dueCandidates(
    DateTime now, {
    required Duration retention,
    required int limit,
  }) async => _ids;

  @override
  Future<List<String>> rehearsalCandidates({required int limit}) async => _ids;

  @override
  dynamic noSuchMethod(Invocation i) => Function.apply(
    switch (i.memberName) {
      #staleQueueRows => _inner.staleQueueRows,
      #ownerlessNotQueued => _inner.ownerlessNotQueued,
      #queuedWithoutClock => _inner.queuedWithoutClock,
      #recordAndStartClock => _inner.recordAndStartClock,
      #claimReminders => _inner.claimReminders,
      #purgeOne => _inner.purgeOne,
      #purgedRows => _inner.purgedRows,
      #setPendingObjects => _inner.setPendingObjects,
      #documentKeysBySalon => _inner.documentKeysBySalon,
      #sweepStragglers => _inner.sweepStragglers,
      #dequeue => _inner.dequeue,
      #eraseDeletedAccountReasons => _inner.eraseDeletedAccountReasons,
      #scrubSearchText => _inner.scrubSearchText,
      #stampDeletion => _inner.stampDeletion,
      _ => throw UnimplementedError('${i.memberName}'),
    },
    i.positionalArguments,
    i.namedArguments,
  );
}
