import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/validation/salon_validation_repository.dart';
import 'package:test/test.dart';

/// The three repositories a validation test touches — the validation twin and
/// the two whose rows its going-live reads and writes.
typedef ValidationWorld = ({
  SalonValidationRepository validations,
  ProvidersRepository providers,
  MembershipRepository members,
});

/// The contract of [SalonValidationRepository], run against BOTH twins — the
/// in-memory one (`salon_validation_repository_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself: each
/// caller runs it inside its own group.
///
/// docs/design/salon-go-live-approval.md §2, §3.1–§3.5, §8.1. The races are
/// the point: a double tap records one request, a validate and a refuse
/// together have one winner, two « finish » clicks take the salon live once.
/// On Postgres they race for real; on the in-memory twin the calls interleave
/// on the event loop, and the synchronous critical sections must hold the
/// same line.
///
/// [world] builds the repositories under test (each test calls it once).
/// [salon] makes a fresh `draft` salon in that world — with an active owner
/// unless `withOwner` is false — and owns its cleanup.
void salonValidationContract({
  required ValidationWorld Function() world,
  required Future<String> Function(ValidationWorld w, {bool withOwner}) salon,
}) {
  final t0 = DateTime.utc(2026, 11, 12, 9);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));
  const admin = 'admin_1';

  Future<String> statusOf(ValidationWorld w, String id) async =>
      (await w.providers.byId(id))!['status'] as String;

  /// A salon with a request in — the state every decision starts from.
  Future<String> pendingSalon(
    ValidationWorld w, {
    bool withOwner = true,
  }) async {
    final id = await salon(w, withOwner: withOwner);
    final r = await w.validations.submit(id, at(0));
    expect(r.recorded, isTrue);
    return id;
  }

  /// A salon validated by the admin, not yet live (§3.2 between steps 2–4).
  Future<String> approvedSalon(
    ValidationWorld w, {
    bool withOwner = true,
  }) async {
    final id = await pendingSalon(w, withOwner: withOwner);
    final d = await w.validations.decide(
      id,
      from: ValidationStates.pending,
      to: ValidationStates.approved,
      adminId: admin,
      at: at(5),
    );
    expect(d, isNotNull);
    return id;
  }

  group('submit (§3.1)', () {
    test('a first request is recorded: pending, its time, one event', () async {
      final w = world();
      final id = await salon(w);
      final r = await w.validations.submit(id, at(1));
      expect(r.recorded, isTrue);
      expect(r.validation!.state, ValidationStates.pending);
      expect(r.validation!.submittedAt, at(1));
      expect(r.validation!.decidedAt, isNull);
      expect(r.validation!.wentLive, isFalse);
      final stored = (await w.validations.get(id))!;
      expect(stored.state, ValidationStates.pending);
      expect(stored.submittedAt, at(1));
      final events = await w.validations.events(id);
      expect(events.map((e) => e.kind), [ValidationEventKinds.submitted]);
      expect(events.single.at, at(1));
      expect(events.single.byAdmin, isNull);
    });

    test('asking again while pending records nothing: no event, the first '
        'request time kept', () async {
      final w = world();
      final id = await pendingSalon(w);
      final r = await w.validations.submit(id, at(9));
      expect(r.recorded, isFalse);
      expect(r.validation!.state, ValidationStates.pending);
      expect(r.validation!.submittedAt, at(0));
      expect(await w.validations.events(id), hasLength(1));
    });

    test('two requests at once (the double tap) record ONE: one event, '
        'so one admin e-mail', () async {
      final w = world();
      final id = await salon(w);
      final results = await Future.wait([
        w.validations.submit(id, at(1)),
        w.validations.submit(id, at(1)),
      ]);
      expect(results.where((r) => r.recorded), hasLength(1));
      expect(
        results.map((r) => r.validation?.state),
        everyElement(ValidationStates.pending),
        reason: 'the loser answers from the real state',
      );
      expect(await w.validations.events(id), hasLength(1));
    });

    test('after a refusal that is not final, a new request is recorded; the '
        'refusal leaves the state row and the history keeps it', () async {
      final w = world();
      final id = await pendingSalon(w);
      await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.refused,
        adminId: admin,
        code: 'photos',
        note: 'Plus de photos du salon.',
        at: at(5),
      );
      final seen = (await w.validations.get(id))!;
      final r = await w.validations.submit(id, at(10), seen: seen);
      expect(r.recorded, isTrue);
      final v = r.validation!;
      expect(v.state, ValidationStates.pending);
      expect(v.submittedAt, at(10));
      expect(v.refusalCode, isNull);
      expect(v.refusalNote, isNull);
      expect(v.decidedAt, isNull);
      expect(v.decidedBy, isNull);
      final events = await w.validations.events(id);
      expect(events.map((e) => e.kind), [
        ValidationEventKinds.submitted,
        ValidationEventKinds.refused,
        ValidationEventKinds.submitted,
      ]);
      expect(events[1].refusalCode, 'photos');
      expect(events[1].refusalNote, 'Plus de photos du salon.');
    });

    test('a request that read « never asked » never overwrites a row that '
        'appeared since — not even a refusal (the slow second tap)', () async {
      final w = world();
      final id = await pendingSalon(w);
      await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.refused,
        adminId: admin,
        code: 'photos',
        at: at(5),
      );
      final r = await w.validations.submit(id, at(10));
      expect(r.recorded, isFalse);
      expect(r.validation!.state, ValidationStates.refused);
      expect(r.validation!.refusalCode, 'photos');
      expect((await w.validations.get(id))!.state, ValidationStates.refused);
      expect(await w.validations.events(id), hasLength(2));
    });

    test('a request that read one refusal never reopens a NEWER one', () async {
      final w = world();
      final id = await pendingSalon(w);
      await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.refused,
        adminId: admin,
        code: 'photos',
        at: at(5),
      );
      final first = (await w.validations.get(id))!;
      // Asked again, and refused again — a new decision.
      expect(
        (await w.validations.submit(id, at(10), seen: first)).recorded,
        isTrue,
      );
      await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.refused,
        adminId: admin,
        code: 'unconfirmed',
        at: at(20),
      );
      // A request still carrying the FIRST refusal arrives late.
      final r = await w.validations.submit(id, at(30), seen: first);
      expect(r.recorded, isFalse);
      expect(r.validation!.state, ValidationStates.refused);
      expect(r.validation!.refusalCode, 'unconfirmed');
      expect(await w.validations.events(id), hasLength(4));
    });

    test('a request from any other state is a programming error, and writes '
        'nothing', () async {
      final w = world();
      final id = await pendingSalon(w);
      final pending = (await w.validations.get(id))!;
      await expectLater(
        w.validations.submit(id, at(10), seen: pending),
        throwsArgumentError,
      );
      final other = await salon(w);
      await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.refused,
        adminId: admin,
        code: 'test_salon',
        at: at(5),
      );
      final finalRefusal = (await w.validations.get(id))!;
      await expectLater(
        w.validations.submit(id, at(10), seen: finalRefusal),
        throwsArgumentError,
      );
      await expectLater(
        w.validations.submit(other, at(10), seen: finalRefusal),
        throwsArgumentError,
        reason: 'another salon\'s validation',
      );
      expect(await w.validations.get(other), isNull);
      expect(await w.validations.events(id), hasLength(2));
    });

    for (final code in kFinalRefusalCodes) {
      test('after a FINAL refusal ($code), a new request is not recorded and '
          'the refusal stands', () async {
        final w = world();
        final id = await pendingSalon(w);
        await w.validations.decide(
          id,
          from: ValidationStates.pending,
          to: ValidationStates.refused,
          adminId: admin,
          code: code,
          at: at(5),
        );
        final r = await w.validations.submit(id, at(10));
        expect(r.recorded, isFalse);
        expect(r.validation!.state, ValidationStates.refused);
        expect(r.validation!.refusalCode, code);
        expect(r.validation!.isFinalRefusal, isTrue);
        expect(await w.validations.events(id), hasLength(2));
      });
    }

    test(
      'a validated salon asking records nothing — finishing or live',
      () async {
        final w = world();
        final id = await approvedSalon(w);
        final finishing = await w.validations.submit(id, at(10));
        expect(finishing.recorded, isFalse);
        expect(finishing.validation!.state, ValidationStates.approved);
        expect(await w.validations.goLive(id), GoLiveOutcome.live);
        final live = await w.validations.submit(id, at(20));
        expect(live.recorded, isFalse);
        expect(live.validation!.wentLive, isTrue);
        expect(await w.validations.events(id), hasLength(2));
      },
    );
  });

  group('decide (§3.2 step 2, §3.3)', () {
    test('pending → approved: the admin, the time, an approved event; not '
        'live yet, still draft', () async {
      final w = world();
      final id = await pendingSalon(w);
      final v = await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.approved,
        adminId: admin,
        at: at(5),
      );
      expect(v!.state, ValidationStates.approved);
      expect(v.decidedAt, at(5));
      expect(v.decidedBy, admin);
      expect(v.submittedAt, at(0));
      expect(v.wentLive, isFalse);
      expect(await statusOf(w, id), 'draft');
      final last = (await w.validations.events(id)).last;
      expect(last.kind, ValidationEventKinds.approved);
      expect(last.byAdmin, admin);
      expect(last.at, at(5));
    });

    test('pending → refused: the code and the note on the row and in the '
        'event', () async {
      final w = world();
      final id = await pendingSalon(w);
      final v = await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.refused,
        adminId: admin,
        code: 'other',
        note: 'Le nom ne correspond pas aux photos.',
        at: at(5),
      );
      expect(v!.state, ValidationStates.refused);
      expect(v.refusalCode, 'other');
      expect(v.refusalNote, 'Le nom ne correspond pas aux photos.');
      expect(v.isFinalRefusal, isFalse);
      final last = (await w.validations.events(id)).last;
      expect(last.kind, ValidationEventKinds.refused);
      expect(last.refusalCode, 'other');
      expect(last.refusalNote, 'Le nom ne correspond pas aux photos.');
      expect(last.byAdmin, admin);
    });

    test('a decision from a state the row is not in writes nothing', () async {
      final w = world();
      final id = await approvedSalon(w);
      final before = await w.validations.events(id);
      final v = await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.refused,
        adminId: 'admin_2',
        code: 'photos',
      );
      expect(v, isNull);
      final stored = (await w.validations.get(id))!;
      expect(stored.state, ValidationStates.approved);
      expect(stored.decidedBy, admin);
      expect(await w.validations.events(id), hasLength(before.length));
    });

    test('no request: null, and no row appears', () async {
      final w = world();
      final id = await salon(w);
      final v = await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.approved,
        adminId: admin,
      );
      expect(v, isNull);
      expect(await w.validations.get(id), isNull);
      expect(await w.validations.events(id), isEmpty);
    });

    test('validate and refuse at once: ONE winner, ONE decision event, the '
        'row is the winner’s', () async {
      final w = world();
      final id = await pendingSalon(w);
      final results = await Future.wait([
        w.validations.decide(
          id,
          from: ValidationStates.pending,
          to: ValidationStates.approved,
          adminId: 'admin_a',
        ),
        w.validations.decide(
          id,
          from: ValidationStates.pending,
          to: ValidationStates.refused,
          adminId: 'admin_b',
          code: 'unconfirmed',
        ),
      ]);
      final winners = results.whereType<SalonValidation>().toList();
      expect(winners, hasLength(1));
      final stored = (await w.validations.get(id))!;
      expect(stored.state, winners.single.state);
      expect(stored.decidedBy, winners.single.decidedBy);
      final decisions = (await w.validations.events(
        id,
      )).where((e) => e.kind != ValidationEventKinds.submitted);
      expect(decisions, hasLength(1));
      expect(decisions.single.kind, winners.single.state);
    });

    test(
      'two validations at once (a double click, two tabs): ONE winner',
      () async {
        final w = world();
        final id = await pendingSalon(w);
        final results = await Future.wait([
          for (var i = 0; i < 2; i++)
            w.validations.decide(
              id,
              from: ValidationStates.pending,
              to: ValidationStates.approved,
              adminId: 'admin_$i',
            ),
        ]);
        expect(results.whereType<SalonValidation>(), hasLength(1));
        expect(
          (await w.validations.events(
            id,
          )).where((e) => e.kind == ValidationEventKinds.approved),
          hasLength(1),
        );
      },
    );

    test('refused → approved (from « Refusés »): the refusal leaves the state '
        'row, the history keeps it', () async {
      final w = world();
      final id = await pendingSalon(w);
      await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.refused,
        adminId: admin,
        code: 'outside_ci',
        note: 'Épingle à Dakar.',
        at: at(5),
      );
      final v = await w.validations.decide(
        id,
        from: ValidationStates.refused,
        to: ValidationStates.approved,
        adminId: 'admin_2',
        at: at(30),
      );
      expect(v!.state, ValidationStates.approved);
      expect(v.refusalCode, isNull);
      expect(v.refusalNote, isNull);
      expect(v.decidedBy, 'admin_2');
      expect(v.decidedAt, at(30));
      final events = await w.validations.events(id);
      expect(events.map((e) => e.kind), [
        ValidationEventKinds.submitted,
        ValidationEventKinds.refused,
        ValidationEventKinds.approved,
      ]);
      expect(events[1].refusalCode, 'outside_ci');
      expect(events[1].refusalNote, 'Épingle à Dakar.');
    });

    test('transitions §2 does not allow are programming errors, and write '
        'nothing', () async {
      final w = world();
      final id = await pendingSalon(w);
      Future<SalonValidation?> d(
        String from,
        String to, {
        String? code,
        String? note,
      }) => w.validations.decide(
        id,
        from: from,
        to: to,
        adminId: admin,
        code: code,
        note: note,
      );
      // `approved` is final; a state never becomes itself (a CAS that keeps
      // the state would let two identical calls both win); nothing goes back
      // to `pending` but the owner's request.
      await expectLater(
        d(ValidationStates.approved, ValidationStates.refused, code: 'photos'),
        throwsArgumentError,
      );
      await expectLater(
        d(ValidationStates.pending, ValidationStates.pending),
        throwsArgumentError,
      );
      await expectLater(
        d(ValidationStates.approved, ValidationStates.approved),
        throwsArgumentError,
      );
      await expectLater(
        d(ValidationStates.refused, ValidationStates.pending),
        throwsArgumentError,
      );
      // A refusal needs a code from the closed list; a validation carries
      // neither code nor note.
      await expectLater(
        d(ValidationStates.pending, ValidationStates.refused),
        throwsArgumentError,
      );
      await expectLater(
        d(ValidationStates.pending, ValidationStates.refused, code: 'rude'),
        throwsArgumentError,
      );
      await expectLater(
        d(ValidationStates.pending, ValidationStates.approved, note: 'ok'),
        throwsArgumentError,
      );
      expect((await w.validations.get(id))!.state, ValidationStates.pending);
      expect(await w.validations.events(id), hasLength(1));
    });
  });

  group('goLive (§3.2 step 4) — one winner, all or nothing', () {
    test('approved, draft, an active owner: live — went_live_at set, the '
        'salon active', () async {
      final w = world();
      final id = await approvedSalon(w);
      expect(await w.validations.goLive(id, at: at(6)), GoLiveOutcome.live);
      final v = (await w.validations.get(id))!;
      expect(v.wentLiveAt, at(6));
      expect(v.state, ValidationStates.approved);
      expect(await statusOf(w, id), 'active');
    });

    test(
      'two « finish » calls at once: ONE live, the other alreadyLive',
      () async {
        final w = world();
        final id = await approvedSalon(w);
        final results = await Future.wait([
          w.validations.goLive(id, at: at(6)),
          w.validations.goLive(id, at: at(7)),
        ]);
        expect(results.where((o) => o == GoLiveOutcome.live), hasLength(1));
        expect(results, contains(GoLiveOutcome.alreadyLive));
        expect(await statusOf(w, id), 'active');
      },
    );

    test('a later call: alreadyLive, the first time kept', () async {
      final w = world();
      final id = await approvedSalon(w);
      await w.validations.goLive(id, at: at(6));
      expect(
        await w.validations.goLive(id, at: at(60)),
        GoLiveOutcome.alreadyLive,
      );
      expect((await w.validations.get(id))!.wentLiveAt, at(6));
    });

    test('pending: notApproved, nothing written', () async {
      final w = world();
      final id = await pendingSalon(w);
      expect(await w.validations.goLive(id), GoLiveOutcome.notApproved);
      expect((await w.validations.get(id))!.wentLiveAt, isNull);
      expect(await statusOf(w, id), 'draft');
    });

    test('refused: notApproved', () async {
      final w = world();
      final id = await pendingSalon(w);
      await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.refused,
        adminId: admin,
        code: 'photos',
      );
      expect(await w.validations.goLive(id), GoLiveOutcome.notApproved);
      expect(await statusOf(w, id), 'draft');
    });

    test('never asked: notApproved', () async {
      final w = world();
      final id = await salon(w);
      expect(await w.validations.goLive(id), GoLiveOutcome.notApproved);
      expect(await statusOf(w, id), 'draft');
    });

    test('suspended since the checks: suspended — and the validation step is '
        'rolled back, so a later finish can still take it live', () async {
      final w = world();
      final id = await approvedSalon(w);
      await w.providers.setStatus(id, 'suspended');
      expect(await w.validations.goLive(id), GoLiveOutcome.suspended);
      expect((await w.validations.get(id))!.wentLiveAt, isNull);
      expect(await statusOf(w, id), 'suspended');
      await w.providers.liftSuspension(id, to: 'draft');
      expect(await w.validations.goLive(id), GoLiveOutcome.live);
    });

    test('no active owner (an erased account): noOwner — both steps rolled '
        'back, nothing public', () async {
      final w = world();
      final id = await approvedSalon(w, withOwner: false);
      expect(await w.validations.goLive(id), GoLiveOutcome.noOwner);
      expect((await w.validations.get(id))!.wentLiveAt, isNull);
      expect(await statusOf(w, id), 'draft');
    });

    test('not draft (already active, e.g. an older image published it): '
        'notDraft, the validation step rolled back', () async {
      final w = world();
      final id = await approvedSalon(w);
      await w.providers.setStatus(id, 'active');
      expect(await w.validations.goLive(id), GoLiveOutcome.notDraft);
      expect((await w.validations.get(id))!.wentLiveAt, isNull);
    });
  });

  group(
    'handBack (§9.3) — only an approved validation that never went live',
    () {
      test(
        'approved, never live, the salon an older image left active: '
        'handed back to draft — then the going-live takes it public',
        () async {
          final w = world();
          final id = await approvedSalon(w);
          await w.providers.setStatus(id, 'active'); // the rollback's flip
          expect(await w.validations.handBack(id), isTrue);
          expect(await statusOf(w, id), 'draft');
          expect(await w.validations.goLive(id), GoLiveOutcome.live);
          expect(await statusOf(w, id), 'active');
        },
      );

      test('a validation that already went live: false — a stale « finish » '
          'never hides a live salon', () async {
        final w = world();
        final id = await approvedSalon(w);
        expect(await w.validations.goLive(id), GoLiveOutcome.live);
        expect(await w.validations.handBack(id), isFalse);
        expect(await statusOf(w, id), 'active');
      });

      test(
        'a going-live and a hand-back at once: the salon ends public',
        () async {
          final w = world();
          final id = await approvedSalon(w);
          final results = await Future.wait([
            w.validations.goLive(id),
            w.validations.handBack(id),
          ]);
          // Either order: the hand-back first finds a draft (false) and the
          // going-live wins; or the going-live first, and the hand-back finds it
          // went live (false). Never a live validation with a hidden salon.
          expect(results.last, isFalse);
          expect(results.first, GoLiveOutcome.live);
          expect(await statusOf(w, id), 'active');
        },
      );

      test(
        'pending, refused, never asked: false, the status untouched',
        () async {
          final w = world();
          final pending = await pendingSalon(w);
          final refused = await pendingSalon(w);
          await w.validations.decide(
            refused,
            from: ValidationStates.pending,
            to: ValidationStates.refused,
            adminId: admin,
            code: 'photos',
          );
          final never = await salon(w);
          for (final id in [pending, refused, never]) {
            await w.providers.setStatus(id, 'active');
            expect(await w.validations.handBack(id), isFalse, reason: id);
            expect(await statusOf(w, id), 'active', reason: id);
          }
        },
      );

      test('approved, never live, already a draft (or suspended): false, '
          'nothing written', () async {
        final w = world();
        final id = await approvedSalon(w);
        expect(await w.validations.handBack(id), isFalse);
        expect(await statusOf(w, id), 'draft');
        await w.providers.setStatus(id, 'suspended');
        expect(await w.validations.handBack(id), isFalse);
        expect(await statusOf(w, id), 'suspended');
      });
    },
  );

  group('queue and count (§3.5)', () {
    test('pending: oldest request first; a suspended salon is left out of '
        'the queue AND the count, and comes back once lifted', () async {
      final w = world();
      final v = w.validations;
      final countBefore = await v.countPending();
      final totalBefore = (await v.queue(ValidationStates.pending)).total;
      final late = await salon(w);
      final early = await salon(w);
      final middle = await salon(w);
      await v.submit(late, at(30));
      await v.submit(early, at(10));
      await v.submit(middle, at(20));
      final mine = {late, early, middle};

      final q = await v.queue(ValidationStates.pending, pageSize: 100);
      expect(q.total, totalBefore + 3);
      expect(await v.countPending(), countBefore + 3);
      expect(
        [
          for (final i in q.items)
            if (mine.contains(i.providerId)) i.providerId,
        ],
        [early, middle, late],
      );

      await w.providers.setStatus(middle, 'suspended');
      final q2 = await v.queue(ValidationStates.pending, pageSize: 100);
      expect(q2.total, totalBefore + 2);
      expect(await v.countPending(), countBefore + 2);
      expect(q2.items.map((i) => i.providerId), isNot(contains(middle)));

      await w.providers.liftSuspension(middle, to: 'draft');
      expect(await v.countPending(), countBefore + 3);
    });

    test('refused and approved: latest decision first; a suspended salon '
        'stays listed', () async {
      final w = world();
      final v = w.validations;
      final first = await pendingSalon(w);
      final second = await pendingSalon(w);
      for (final (id, minutes) in [(first, 5), (second, 15)]) {
        await v.decide(
          id,
          from: ValidationStates.pending,
          to: ValidationStates.refused,
          adminId: admin,
          code: 'photos',
          at: at(minutes),
        );
      }
      await w.providers.setStatus(first, 'suspended');
      final refused = await v.queue(ValidationStates.refused, pageSize: 100);
      expect(
        [
          for (final i in refused.items)
            if (i.providerId == first || i.providerId == second) i.providerId,
        ],
        [second, first],
      );

      final approved = await approvedSalon(w);
      final a = await v.queue(ValidationStates.approved, pageSize: 100);
      expect(a.items.map((i) => i.providerId), contains(approved));
      expect(
        a.items.map((i) => i.providerId),
        isNot(contains(first)),
        reason: 'one state per tab',
      );
    });

    test('countPending is the queue’s total — one definition', () async {
      final w = world();
      await pendingSalon(w);
      expect(
        await w.validations.countPending(),
        (await w.validations.queue(ValidationStates.pending)).total,
      );
    });

    test('pageSize bounds the page; total counts every row', () async {
      final w = world();
      await pendingSalon(w);
      await pendingSalon(w);
      final page = await w.validations.queue(
        ValidationStates.pending,
        pageSize: 1,
      );
      expect(page.items, hasLength(1));
      expect(page.total, greaterThanOrEqualTo(2));
      final far = await w.validations.queue(
        ValidationStates.pending,
        page: 100000,
        pageSize: 1,
      );
      expect(far.items, isEmpty);
      expect(far.total, page.total);
    });

    test('an unknown state or a page below 1 is a programming error', () async {
      final w = world();
      await expectLater(w.validations.queue('done'), throwsArgumentError);
      await expectLater(
        w.validations.queue(ValidationStates.pending, page: 0),
        throwsArgumentError,
      );
      await expectLater(
        w.validations.queue(ValidationStates.pending, pageSize: 0),
        throwsArgumentError,
      );
    });
  });

  group('reads and erasure (§3.4, §3.5)', () {
    test('getMany: one map, only the salons that have a row', () async {
      final w = world();
      final asked = await pendingSalon(w);
      final never = await salon(w);
      final m = await w.validations.getMany([asked, never]);
      expect(m.keys, [asked]);
      expect(m[asked]!.state, ValidationStates.pending);
      expect(await w.validations.getMany(const []), isEmpty);
    });

    test('events: oldest first, a tie kept in the order it happened', () async {
      final w = world();
      final id = await salon(w);
      await w.validations.submit(id, at(1));
      await w.validations.decide(
        id,
        from: ValidationStates.pending,
        to: ValidationStates.refused,
        adminId: admin,
        code: 'photos',
        at: at(1),
      );
      final events = await w.validations.events(id);
      expect(events.map((e) => e.kind), [
        ValidationEventKinds.submitted,
        ValidationEventKinds.refused,
      ]);
      expect(events.first.id, lessThan(events.last.id));
    });

    test(
      'deletePending: a pending request goes; a decided row stays',
      () async {
        final w = world();
        final pending = await pendingSalon(w);
        final approved = await approvedSalon(w);
        final refused = await pendingSalon(w);
        await w.validations.decide(
          refused,
          from: ValidationStates.pending,
          to: ValidationStates.refused,
          adminId: admin,
          code: 'photos',
        );
        expect(await w.validations.deletePending(pending), isTrue);
        expect(await w.validations.get(pending), isNull);
        expect(await w.validations.deletePending(approved), isFalse);
        expect(await w.validations.deletePending(refused), isFalse);
        expect(await w.validations.get(approved), isNotNull);
        expect(await w.validations.get(refused), isNotNull);
      },
    );

    test(
      'clearNotes: the note leaves the row AND the history; the code stays',
      () async {
        final w = world();
        final id = await pendingSalon(w);
        await w.validations.decide(
          id,
          from: ValidationStates.pending,
          to: ValidationStates.refused,
          adminId: admin,
          code: 'other',
          note: 'Appelez le 07 07 07 07 07.',
        );
        await w.validations.clearNotes(id);
        final v = (await w.validations.get(id))!;
        expect(v.refusalNote, isNull);
        expect(v.refusalCode, 'other');
        final refused = (await w.validations.events(
          id,
        )).singleWhere((e) => e.kind == ValidationEventKinds.refused);
        expect(refused.refusalNote, isNull);
        expect(refused.refusalCode, 'other');
      },
    );

    test('clearNotes touches only that salon', () async {
      final w = world();
      final mine = await pendingSalon(w);
      final other = await pendingSalon(w);
      for (final id in [mine, other]) {
        await w.validations.decide(
          id,
          from: ValidationStates.pending,
          to: ValidationStates.refused,
          adminId: admin,
          code: 'other',
          note: 'Note.',
        );
      }
      await w.validations.clearNotes(mine);
      expect((await w.validations.get(other))!.refusalNote, 'Note.');
      expect((await w.validations.events(other)).last.refusalNote, 'Note.');
    });
  });
}

/// The contract of `providers.suspended_from` (B0.18 §3.4) on
/// [ProvidersRepository], run against both twins. [salon] makes a fresh
/// `draft` salon and owns its cleanup.
void suspendedFromContract({
  required ProvidersRepository Function() repo,
  required Future<String> Function(ProvidersRepository r) salon,
}) {
  test('suspending records the status it interrupted; a second suspension '
      'keeps the first value', () async {
    final r = repo();
    final id = await salon(r);
    await r.setStatus(id, 'active');
    expect(await r.suspendedFrom(id), isNull);
    await r.setStatus(id, 'suspended');
    expect(await r.suspendedFrom(id), 'active');
    await r.setStatus(id, 'suspended');
    expect(
      await r.suspendedFrom(id),
      'active',
      reason: 'a second suspend must not record « suspended »',
    );
  });

  test('a draft suspended records draft', () async {
    final r = repo();
    final id = await salon(r);
    await r.setStatus(id, 'suspended');
    expect(await r.suspendedFrom(id), 'draft');
  });

  test('liftSuspension: from suspended only, to the status asked, clearing '
      'the memory', () async {
    final r = repo();
    final id = await salon(r);
    await r.setStatus(id, 'active');
    await r.setStatus(id, 'suspended');
    final lifted = await r.liftSuspension(id, to: 'draft');
    expect(lifted!['status'], 'draft');
    expect((await r.byId(id))!['status'], 'draft');
    expect(await r.suspendedFrom(id), isNull);
    // Not suspended any more: a second lift writes nothing.
    expect(await r.liftSuspension(id, to: 'active'), isNull);
    expect((await r.byId(id))!['status'], 'draft');
  });

  test('liftSuspension on a salon that is not suspended: null, the status '
      'untouched', () async {
    final r = repo();
    final id = await salon(r);
    expect(await r.liftSuspension(id, to: 'active'), isNull);
    expect((await r.byId(id))!['status'], 'draft');
    expect(await r.liftSuspension('no_such_salon', to: 'draft'), isNull);
  });

  test('any other status write ends the suspension: nothing is remembered, and '
      'the next suspension records afresh', () async {
    // Two layers hold this, so neither alone turns it red: the write
    // clears the memory, and the read goes through the status — which also
    // covers an older image's write, which cannot clear a column it has
    // never heard of (the Postgres group pins that case).
    final r = repo();
    final id = await salon(r);
    await r.setStatus(id, 'active');
    await r.setStatus(id, 'suspended');
    await r.setStatus(id, 'draft'); // e.g. account erasure
    expect(await r.suspendedFrom(id), isNull);
    await r.setStatus(id, 'suspended');
    expect(await r.suspendedFrom(id), 'draft', reason: 'recorded afresh');
  });

  test('never in the provider document — that is the public payload', () async {
    final r = repo();
    final id = await salon(r);
    await r.setStatus(id, 'suspended');
    final doc = (await r.byId(id))!;
    expect(doc.keys, isNot(contains('suspendedFrom')));
    expect(doc.keys, isNot(contains('suspended_from')));
  });

  test(
    'a lift target other than active or draft is a programming error',
    () async {
      final r = repo();
      final id = await salon(r);
      await r.setStatus(id, 'suspended');
      await expectLater(
        r.liftSuspension(id, to: 'suspended'),
        throwsArgumentError,
      );
      expect((await r.byId(id))!['status'], 'suspended');
    },
  );
}
