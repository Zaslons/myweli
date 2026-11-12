import 'package:myweli_backend/src/validation/salon_place_notice_repository.dart';
import 'package:test/test.dart';

/// The contract of [SalonPlaceNoticeRepository] (decision 133 — the cap on
/// the place-change e-mails, docs/design/salon-go-live-approval.md §5.1),
/// run against BOTH twins: the in-memory one
/// (`salon_place_notice_repository_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`, CI only). Not a test file itself.
///
/// The races are the point: two saves in a quiet hour send ONE e-mail, two
/// ticks send ONE summary. On Postgres they race for real; on the in-memory
/// twin the calls interleave on the event loop.
///
/// [repo] builds the repository under test; [salon] makes a fresh salon (a
/// `providers` row — Postgres's foreign key) and owns its cleanup.
/// [contended], when given (Postgres), runs the races on an existing row
/// under contention every time — see [ContendedRace]; without it they run
/// with `Future.wait`.
void salonPlaceNoticeContract({
  required SalonPlaceNoticeRepository Function() repo,
  required Future<String> Function() salon,
  ContendedRace? contended,
}) {
  final t0 = DateTime.utc(2026, 11, 12, 9);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

  Future<List<T>> atOnce<T>(String id, List<Future<T> Function()> calls) {
    final held = contended;
    return held == null
        ? Future.wait([for (final c in calls) c()])
        : held<T>(id, calls);
  }

  Map<String, String?> place(String phone) => {
    'location': '5.35, -3.99',
    'address': 'Rue des Jardins',
    'commune': 'Cocody, Abidjan',
    'phone': phone,
  };

  Future<PlaceNoticeTurn> save(
    SalonPlaceNoticeRepository r,
    String id,
    DateTime when, {
    String phone = '+2250700000001',
    List<String> fields = const ['phone'],
  }) => r.recordSave(id, when, after: place(phone), fields: fields);

  group('the save (recordSave)', () {
    test('the first change of a quiet hour is e-mailed at once: the time and '
        'the place it reported are kept, nothing pending', () async {
      final r = repo();
      final id = await salon();
      expect(await r.get(id), isNull, reason: 'no row before any change');
      expect(await save(r, id, at(0)), PlaceNoticeTurn.sendNow);
      final row = (await r.get(id))!;
      expect(row.lastSentAt, at(0));
      expect(row.reported, place('+2250700000001'));
      expect(row.pendingCount, 0);
      expect(row.pendingSince, isNull);
      expect(row.pendingFields, isEmpty);
    });

    test('the changes in the hour after it are recorded, not e-mailed: the '
        'count grows, the first one\'s time stays, the kinds add up in the '
        'e-mail\'s order', () async {
      final r = repo();
      final id = await salon();
      await save(r, id, at(0));
      expect(
        await save(r, id, at(10), phone: '+2250700000002'),
        PlaceNoticeTurn.recorded,
      );
      expect(
        await save(r, id, at(20), fields: ['address', 'location']),
        PlaceNoticeTurn.recorded,
      );
      expect(await save(r, id, at(59)), PlaceNoticeTurn.recorded);
      final row = (await r.get(id))!;
      expect(row.pendingCount, 3);
      expect(row.pendingSince, at(10));
      expect(row.pendingFields, ['location', 'address', 'phone']);
      expect(row.lastSentAt, at(0), reason: 'no e-mail went');
      expect(
        row.reported,
        place('+2250700000001'),
        reason: 'the reported place is the last E-MAIL\'s, not the last save',
      );
    });

    test('the window\'s edge: one minute short of the hour is still recorded '
        '— exactly the hour, with nothing pending, is quiet again', () async {
      final r = repo();
      final early = await salon();
      await save(r, early, at(0));
      expect(
        await save(r, early, at(0).add(const Duration(minutes: 59))),
        PlaceNoticeTurn.recorded,
      );

      final onTime = await salon();
      await save(r, onTime, at(0));
      expect(
        await save(r, onTime, at(0).add(kPlaceNoticeWindow)),
        PlaceNoticeTurn.sendNow,
      );
      expect((await r.get(onTime))!.lastSentAt, at(60));
    });

    test('a change after the hour while a summary is still owed joins it '
        '(the tick sends it) — never an immediate e-mail from the wrong '
        '« before »', () async {
      final r = repo();
      final id = await salon();
      await save(r, id, at(0));
      await save(r, id, at(30));
      expect(await save(r, id, at(70)), PlaceNoticeTurn.recorded);
      final row = (await r.get(id))!;
      expect(row.pendingCount, 2);
      expect(row.pendingSince, at(30));
    });

    test('a summary owed and kPlaceSummaryGrace past its hour — the cron has '
        'not sent it: the save is counted AND told so, the caller sends it; '
        'a minute short of that, only counted', () async {
      final r = repo();
      final id = await salon();
      await save(r, id, at(0));
      await save(r, id, at(10));
      expect(await save(r, id, at(89)), PlaceNoticeTurn.recorded);
      expect(await save(r, id, at(90)), PlaceNoticeTurn.summaryOverdue);
      final row = (await r.get(id))!;
      expect(row.pendingCount, 3, reason: 'the summary carries this save');
      expect(row.pendingSince, at(10));
      expect(row.lastSentAt, at(0));
    });

    // On Postgres a NEW row serialises these by itself: the insert of the
    // first waits out the others' pre-check. The lock is tested on an
    // existing row, below.
    test('TWO SAVES AT ONCE in a quiet hour → exactly one e-mail; the other '
        'is recorded', () async {
      final r = repo();
      final id = await salon();
      final turns = await Future.wait([
        save(r, id, at(0)),
        save(r, id, at(0), phone: '+2250700000002'),
        save(r, id, at(0), phone: '+2250700000003'),
      ]);
      expect(turns.where((t) => t == PlaceNoticeTurn.sendNow), hasLength(1));
      expect((await r.get(id))!.pendingCount, 2);
    });

    test('SAVES AT ONCE on a salon already e-mailed, its hour over → '
        'exactly one e-mail, the others recorded — the row exists, only its '
        'lock decides', () async {
      final r = repo();
      final id = await salon();
      expect(await save(r, id, at(0)), PlaceNoticeTurn.sendNow);
      final turns = await atOnce(id, [
        () => save(r, id, at(60)),
        () => save(r, id, at(60), phone: '+2250700000002'),
        () => save(r, id, at(60), phone: '+2250700000003'),
      ]);
      expect(turns.where((t) => t == PlaceNoticeTurn.sendNow), hasLength(1));
      final row = (await r.get(id))!;
      expect(row.pendingCount, 2);
      expect(row.lastSentAt, at(60));
    });

    test('each salon has its own hour', () async {
      final r = repo();
      final a = await salon();
      final b = await salon();
      expect(await save(r, a, at(0)), PlaceNoticeTurn.sendNow);
      expect(await save(r, b, at(1)), PlaceNoticeTurn.sendNow);
      expect(await save(r, a, at(2)), PlaceNoticeTurn.recorded);
      expect((await r.get(b))!.pendingCount, 0);
    });
  });

  group('the summary (due, claimSummary)', () {
    Future<String> owing(SalonPlaceNoticeRepository r, {int start = 0}) async {
      final id = await salon();
      await save(r, id, at(start));
      await save(r, id, at(start + 10), phone: '+2250700000002');
      await save(r, id, at(start + 20), fields: ['address']);
      return id;
    }

    test('not due before the hour; due from the hour on', () async {
      final r = repo();
      final id = await owing(r);
      expect(await r.due(at(59)), isNot(contains(id)));
      expect(
        await r.claimSummary(id, at(59), current: place('x'), seenSaves: 2),
        isNull,
      );
      expect(await r.due(at(60)), contains(id));
    });

    test('the claim hands over what was reported, the count, the first '
        'time and the kinds — and starts a new hour, the CURRENT place now '
        'reported, nothing pending', () async {
      final r = repo();
      final id = await owing(r);
      final now = place('+2250700000002');
      final c = (await r.claimSummary(id, at(75), current: now, seenSaves: 2))!;
      expect(c.reported, place('+2250700000001'));
      expect(c.saves, 2);
      expect(c.since, at(10));
      expect(c.fields, ['address', 'phone']);
      final row = (await r.get(id))!;
      expect(row.lastSentAt, at(75));
      expect(row.reported, now);
      expect(row.pendingCount, 0);
      expect(row.pendingSince, isNull);
      expect(row.pendingFields, isEmpty);
      expect(await r.due(at(200)), isNot(contains(id)));
    });

    test('a summary opens a new hour: a change right after it is recorded; '
        'an hour later with nothing owed, one is e-mailed at once', () async {
      final r = repo();
      final id = await owing(r);
      await r.claimSummary(id, at(75), current: place('y'), seenSaves: 2);
      expect(await save(r, id, at(80)), PlaceNoticeTurn.recorded);
      expect(await r.due(at(134)), isNot(contains(id)));
      expect(await r.due(at(135)), contains(id));

      final quiet = await owing(r);
      await r.claimSummary(quiet, at(75), current: place('y'), seenSaves: 2);
      expect(await save(r, quiet, at(135)), PlaceNoticeTurn.sendNow);
    });

    test('the claim is CONDITIONAL on the saves its caller read: a save '
        'counted since makes it miss, nothing cleared; a claim on the new '
        'count takes it, that save in it', () async {
      final r = repo();
      final id = await owing(r);
      final seen = (await r.get(id))!.pendingCount;
      expect(
        await save(r, id, at(61), phone: '+2250700000077'),
        PlaceNoticeTurn.recorded,
      );
      expect(
        await r.claimSummary(
          id,
          at(62),
          current: place('+2250700000002'),
          seenSaves: seen,
        ),
        isNull,
        reason: 'the place read before that save may lack it',
      );
      final row = (await r.get(id))!;
      expect(row.pendingCount, 3);
      expect(row.lastSentAt, at(0));
      expect(row.reported, place('+2250700000001'));

      final c = (await r.claimSummary(
        id,
        at(62),
        current: place('+2250700000077'),
        seenSaves: 3,
      ))!;
      expect(c.saves, 3);
      expect((await r.get(id))!.reported, place('+2250700000077'));
    });

    test('TWO TICKS AT ONCE → one summary; and a tick run again claims '
        'nothing (idempotent)', () async {
      final r = repo();
      final id = await owing(r);
      final claims = await atOnce(id, [
        () => r.claimSummary(id, at(60), current: place('a'), seenSaves: 2),
        () => r.claimSummary(id, at(60), current: place('b'), seenSaves: 2),
      ]);
      expect(claims.whereType<PlaceSummaryClaim>(), hasLength(1));
      expect(
        await r.claimSummary(id, at(61), current: place('c'), seenSaves: 2),
        isNull,
      );
      expect(await r.due(at(61)), isNot(contains(id)));
    });

    test('due lists the oldest owed first, and at most the limit', () async {
      final r = repo();
      final later = await owing(r, start: 5);
      final earlier = await owing(r);
      final due = await r.due(at(120));
      expect(due.indexOf(earlier), lessThan(due.indexOf(later)));
      expect(await r.due(at(120), limit: 1), [earlier]);
    });
  });

  group('dropping and forgetting', () {
    test('dropPending clears what is owed — the e-mail time and the '
        'reported place stay; a second drop finds nothing', () async {
      final r = repo();
      final id = await salon();
      await save(r, id, at(0));
      await save(r, id, at(10));
      expect(await r.dropPending(id), isTrue);
      final row = (await r.get(id))!;
      expect(row.pendingCount, 0);
      expect(row.pendingSince, isNull);
      expect(row.pendingFields, isEmpty);
      expect(row.lastSentAt, at(0));
      expect(row.reported, place('+2250700000001'));
      expect(await r.dropPending(id), isFalse);
      expect(await r.due(at(120)), isNot(contains(id)));
    });

    test('forget deletes the row — the reported phone and address with it '
        '(account erasure)', () async {
      final r = repo();
      final id = await salon();
      await save(r, id, at(0));
      await save(r, id, at(10));
      await r.forget(id);
      expect(await r.get(id), isNull);
      expect(await r.due(at(120)), isNot(contains(id)));
      await r.forget(id); // nothing left: no error
    });
  });
}

/// Runs [calls] at once while another transaction holds the salon's row
/// `FOR UPDATE`, and lets go only once every call waits on that lock: the
/// race then happens on every run, not when the timing allows. Code that
/// read the row without the lock has read it before any call writes, and
/// loses the race every time. Postgres only; the row must exist.
typedef ContendedRace =
    Future<List<T>> Function<T>(
      String providerId,
      List<Future<T> Function()> calls,
    );
