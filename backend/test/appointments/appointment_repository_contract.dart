import 'dart:convert';

import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

/// The contract of [AppointmentRepository], run against BOTH twins — the
/// in-memory one (`appointment_repository_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself: each caller
/// runs it inside its own group, on an empty `appointments` table.
///
/// docs/design/appointment-currency-stamp.md §8.2;
/// docs/design/appointment-twin-update.md §8.1–§8.3.
///
/// **Why it exists.** The booking service stamped every booking with its
/// salon's currency, and the Postgres repository dropped it on the floor: no
/// column in the INSERT, no key in the read. Every service and handler test
/// runs on the in-memory twin, which then stored the caller's own map, so
/// none of them could see it. The defect was not « `currency` is missing », it was
/// « the twins disagree about which keys survive », and this contract is
/// aimed at that class: the next key the service writes without a column turns
/// it red, whatever the key is called.
///
/// [repo] builds the repository under test (each test calls it once).
void appointmentRepositoryContract({
  required AppointmentRepository Function() repo,
}) {
  /// A salon of its own — never the shared, MUTABLE `seedProviders` entry —
  /// in a currency that is not XOF, so no XOF default or fallback can pass.
  /// A deposit is required so the deposit and balance are not both zero.
  ///
  /// With [team], a roster of two (R1): the kept name has to come from
  /// somewhere, and two names make a lookup of the wrong one visible. Empty
  /// working hours inherit the salon's.
  InMemoryProvidersRepository salon({bool team = false}) {
    final doc =
        jsonDecode(jsonEncode(seedProviders.first)) as Map<String, dynamic>
          ..['id'] = 'p_currency_contract'
          ..['slug'] = 'p-currency-contract'
          ..['currency'] = 'XAF'
          ..['depositRequired'] = true;
    if (team) {
      doc['artists'] = [
        {
          'id': 'artist-awa',
          'name': 'Awa',
          'workingHours': <String, dynamic>{},
        },
        {
          'id': 'artist-binta',
          'name': 'Binta',
          'workingHours': <String, dynamic>{},
        },
      ];
    }
    final services = (doc['services'] as List).cast<Map<String, dynamic>>();
    for (final s in services) {
      s['providerId'] = 'p_currency_contract';
    }
    (doc['availability'] as Map<String, dynamic>)['providerId'] =
        'p_currency_contract';
    return InMemoryProvidersRepository([doc]);
  }

  /// A future Mon–Sat 09:00 UTC — an open slot in the seed schedule, far
  /// enough ahead for the notice and inside the horizon.
  DateTime slot() {
    final now = DateTime.now().toUtc();
    var d = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 7));
    while (d.weekday == DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime.utc(d.year, d.month, d.day, 9);
  }

  /// Comparable form of a stored value: every number as a double, every ISO
  /// instant as microseconds since the epoch, lists element by element. The
  /// twins may spell `0` as `0.0` or a date with a different suffix; neither
  /// is a lost value, and both would make a plain `equals` red for the wrong
  /// reason.
  Object? norm(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String && v.contains('T')) {
      final t = DateTime.tryParse(v);
      if (t != null) return t.toUtc().microsecondsSinceEpoch;
    }
    if (v is List) return [for (final e in v) norm(e)];
    return v;
  }

  /// Every key of [written] is in [read], with the same value — except the
  /// keys a read path changed on purpose.
  void expectCarries(
    Map<String, dynamic>? read,
    Map<String, dynamic> written, {
    required String where,
    Set<String> except = const {},
  }) {
    expect(read, isNotNull, reason: '$where returned nothing');
    for (final k in written.keys) {
      if (except.contains(k)) continue;
      expect(
        read!.containsKey(k),
        isTrue,
        reason: '$where lost "$k": the service wrote it, the read dropped it',
      );
      expect(norm(read[k]), norm(written[k]), reason: '$where changed "$k"');
    }
  }

  group('every key the booking service writes comes back from every read', () {
    test('book (a client booking)', () async {
      final rec = _Recording(repo());
      final providers = salon();
      final at = slot();
      final r =
          await BookingService(
            providers,
            rec,
            SlotService(providers, rec),
          ).book(
            userId: 'u_contract',
            providerId: 'p_currency_contract',
            serviceIds: const ['service1'],
            appointmentDateTime: at,
          );
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      final written = rec.written.single;
      expect(
        written['currency'],
        'XAF',
        reason: 'the service stamps the SALON currency at write time',
      );
      final id = written['id'] as String;

      expectCarries(r.appointment, written, where: 'create');
      expectCarries(await rec.byId(id), written, where: 'byId');
      expectCarries(
        (await rec.listForUser('u_contract')).single,
        written,
        where: 'listForUser',
      );
      expectCarries(
        (await rec.listForProvider('p_currency_contract')).single,
        written,
        where: 'listForProvider',
      );

      // `book` creates `pending`; confirming it is a change of `status` on
      // purpose, and the reminder window only sees `confirmed` rows.
      final confirmed = await rec.update(id, {'status': 'confirmed'});
      expectCarries(
        confirmed,
        written,
        where: 'update',
        except: const {'status'},
      );
      expectCarries(
        (await rec.confirmedInWindow(
          at.subtract(const Duration(minutes: 1)),
          at,
        )).single,
        written,
        where: 'confirmedInWindow',
        except: const {'status'},
      );
    });

    test('bookManual (the salon’s own entry)', () async {
      final rec = _Recording(repo());
      final providers = salon();
      final at = slot();
      final r =
          await BookingService(
            providers,
            rec,
            SlotService(providers, rec),
          ).bookManual(
            providerId: 'p_currency_contract',
            serviceIds: const ['service1'],
            appointmentDateTime: at,
            clientName: 'Awa',
            clientPhone: '+2250700000777',
            notes: 'Première visite',
          );
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      final written = rec.written.single;
      expect(written['currency'], 'XAF');
      final id = written['id'] as String;

      expectCarries(r.appointment, written, where: 'create');
      expectCarries(await rec.byId(id), written, where: 'byId');
      expectCarries(
        (await rec.listForUser('manual')).single,
        written,
        where: 'listForUser',
      );
      expectCarries(
        (await rec.listForProvider('p_currency_contract')).single,
        written,
        where: 'listForProvider',
      );
      expectCarries(
        (await rec.confirmedInWindow(
          at.subtract(const Duration(minutes: 1)),
          at,
        )).single,
        written,
        where: 'confirmedInWindow',
      );
      // `bookManual` writes `confirmed`; an arrival is a change on purpose.
      expectCarries(
        await rec.update(id, {'arrivedAt': at.toIso8601String()}),
        written,
        where: 'update',
      );
    });
  });

  // docs/design/pro-revenue-analytics.md §8.1–§8.2 (R1, decisions 241–243):
  // what a booking keeps so a salon's revenue can be split by prestation,
  // collaborateur and channel after the catalogue, the roster or a price has
  // changed. On BOTH twins: the in-memory one keeps whatever it is handed, so
  // only the Postgres run of this group can see a column go missing.
  group('R1: a booking keeps its lines, its collaborateur’s name and its '
      'channel', () {
    BookingService service(
      AppointmentRepository r,
      InMemoryProvidersRepository p,
    ) => BookingService(p, r, SlotService(p, r));

    // The salon's prices and names when the booking was made: one line per
    // entry of `serviceIds`, in the order booked — a duplicate is two lines.
    const lines = [
      {
        'serviceId': 'service2',
        'name': 'Soin du visage',
        'price': 12000,
        'durationMinutes': 60,
      },
      {
        'serviceId': 'service1',
        'name': 'Tresses',
        'price': 15000,
        'durationMinutes': 180,
      },
      {
        'serviceId': 'service2',
        'name': 'Soin du visage',
        'price': 12000,
        'durationMinutes': 60,
      },
    ];

    /// Every read a booking comes back through, for [id] at [at].
    Future<List<(String, Map<String, dynamic>?)>> reads(
      AppointmentRepository r,
      Map<String, dynamic>? created,
      String id,
    ) async => [
      ('create', created),
      ('byId', await r.byId(id)),
      (
        'listForProvider',
        (await r.listForProvider('p_currency_contract')).single,
      ),
    ];

    test('book: the lines in the order booked, the collaborateur’s name, and '
        '« app »', () async {
      final r = repo();
      final res = await service(r, salon(team: true)).book(
        userId: 'u_contract',
        providerId: 'p_currency_contract',
        serviceIds: const ['service2', 'service1', 'service2'],
        appointmentDateTime: slot(),
        artistId: 'artist-binta',
      );
      expect(res.ok, isTrue, reason: 'error was ${res.error}');
      for (final (where, read) in await reads(
        r,
        res.appointment,
        res.appointment!['id'] as String,
      )) {
        expect(read!['serviceLines'], lines, reason: '$where: the lines');
        expect(read['artistNameKept'], 'Binta', reason: '$where: the name');
        expect(read['channel'], 'app', reason: '$where: the channel');
      }
      // The invariant the revenue reads stand on: the lines add up to the
      // price the client was quoted.
      expect(
        res.appointment!['totalPrice'],
        lines.fold<num>(0, (s, l) => s + (l['price']! as num)),
      );
    });

    test('book from the website: « web »', () async {
      final r = repo();
      final res = await service(r, salon()).book(
        userId: 'u_contract',
        providerId: 'p_currency_contract',
        serviceIds: const ['service1'],
        appointmentDateTime: slot(),
        onWebsite: true,
      );
      expect(res.ok, isTrue, reason: 'error was ${res.error}');
      for (final (where, read) in await reads(
        r,
        res.appointment,
        res.appointment!['id'] as String,
      )) {
        expect(read!['channel'], 'web', reason: '$where: the channel');
        expect(
          read['artistNameKept'],
          isNull,
          reason: '$where: no collaborateur, no name',
        );
      }
    });

    test('bookManual: « salon », and the name of the collaborateur the salon '
        'chose', () async {
      final r = repo();
      final res = await service(r, salon(team: true)).bookManual(
        providerId: 'p_currency_contract',
        serviceIds: const ['service2', 'service1', 'service2'],
        appointmentDateTime: slot(),
        artistId: 'artist-awa',
        clientName: 'Awa',
      );
      expect(res.ok, isTrue, reason: 'error was ${res.error}');
      for (final (where, read) in await reads(
        r,
        res.appointment,
        res.appointment!['id'] as String,
      )) {
        expect(read!['serviceLines'], lines, reason: '$where: the lines');
        expect(read['artistNameKept'], 'Awa', reason: '$where: the name');
        expect(read['channel'], 'salon', reason: '$where: the channel');
      }
    });

    // §3.3: « Sans collaborateur attribué » is `artistId` null. An empty
    // string used to be stored as sent, and would have been a collaborateur
    // with no name.
    for (final kind in ['book', 'bookManual']) {
      test('$kind: an empty collaborateur is stored as none', () async {
        final r = repo();
        final s = service(r, salon(team: true));
        final res = kind == 'book'
            ? await s.book(
                userId: 'u_contract',
                providerId: 'p_currency_contract',
                serviceIds: const ['service1'],
                appointmentDateTime: slot(),
                artistId: '',
              )
            : await s.bookManual(
                providerId: 'p_currency_contract',
                serviceIds: const ['service1'],
                appointmentDateTime: slot(),
                artistId: '',
              );
        expect(res.ok, isTrue, reason: 'error was ${res.error}');
        for (final (where, read) in await reads(
          r,
          res.appointment,
          res.appointment!['id'] as String,
        )) {
          expect(read!['artistId'], isNull, reason: '$where: artistId');
          expect(read['artistNameKept'], isNull, reason: '$where: the name');
        }
      });
    }
  });

  test('the currency is immutable: an update naming it is refused, and the '
      'stamp stays', () async {
    final r = repo();
    await r.create(_booking(id: 'a_immutable', currency: 'XAF'));
    await expectLater(
      r.update('a_immutable', {'currency': 'EUR', 'status': 'confirmed'}),
      throwsA(isA<ArgumentError>()),
      reason:
          'refused: a booking is priced in the currency it was made in (the '
          'Fresha rule), so no update may name it',
    );
    final after = (await r.byId('a_immutable'))!;
    expect(after['currency'], 'XAF');
    expect(
      after['status'],
      'pending',
      reason: 'half-written: the refused update changed the status',
    );
  });

  // docs/design/appointment-twin-update.md §8.1–§8.3 (decisions 214, 216).
  // In memory, `update` wrote any key and any value and handed out its own
  // maps; Postgres writes six keys (seven since R1), ignores the rest without a word, rejects
  // some values, and builds a fresh map on every read. Each test below holds
  // BOTH twins to the same answer.
  group('update writes only what Postgres writes', () {
    const id = 'a_twin';
    final at = DateTime.utc(2030, 6, 25, 9);

    test('the readable keys round-trip (the control)', () async {
      final moved = at.add(const Duration(days: 1));
      final cases = <String, Map<String, dynamic>>{
        'status': {'status': 'confirmed'},
        // With `endsAt`, as the reschedule sends it: Postgres's exclusion
        // range is (appointment_date, ends_at), and a start past the end is
        // not a range.
        'appointmentDate': {
          'appointmentDate': moved.toIso8601String(),
          'endsAt': moved.add(const Duration(minutes: 30)).toIso8601String(),
        },
        'depositScreenshotUrl': {'depositScreenshotUrl': 'deposit/p/a.jpg'},
        'arrivedAt': {
          'arrivedAt': at.add(const Duration(minutes: 5)).toIso8601String(),
        },
        'artistId': {'artistId': 'artist-a'},
        // R1 (pro-revenue-analytics.md §8.1): a reassignment keeps the new
        // collaborateur's name with the id, in the same write.
        'artistNameKept': {'artistId': 'artist-a', 'artistNameKept': 'Awa'},
      };
      var n = 0;
      for (final MapEntry(key: key, value: changes) in cases.entries) {
        final r = repo();
        // Each booking in its own slot: Postgres refuses a second one in a
        // taken slot, and the test would then be red for that.
        await r.create(
          _booking(
            id: '${id}_$key',
            currency: 'XAF',
            at: at.add(Duration(hours: 2 * n++)),
          ),
        );
        final updated = await r.update('${id}_$key', changes);
        expect(
          norm(updated?[key]),
          norm(changes[key]),
          reason: 'the update did not apply "$key"',
        );
        expect(
          norm((await r.byId('${id}_$key'))![key]),
          norm(changes[key]),
          reason: 'the read lost "$key"',
        );
      }
    });

    test('a key Postgres does not write is refused, and nothing is '
        'half-written', () async {
      final foreign = <String, Object?>{
        'clientPhone': '+2250700000002',
        'clientName': 'Koffi',
        'notes': 'après',
        'totalPrice': 1,
        'providerId': 'provider2',
        'madeUpKey': 'x',
        // R1: what the booking was sold as, and where, never change — like
        // `currency` (pro-revenue-analytics.md §8.1).
        'serviceLines': [
          {
            'serviceId': 'service1',
            'name': 'Tresses',
            'price': 1,
            'durationMinutes': 30,
          },
        ],
        'channel': 'web',
      };
      var n = 0;
      for (final MapEntry(:key, :value) in foreign.entries) {
        final r = repo();
        await r.create(
          _booking(
            id: '${id}_$key',
            currency: 'XAF',
            at: at.add(Duration(hours: 2 * n++)),
          ),
        );
        await expectLater(
          r.update('${id}_$key', {key: value, 'status': 'confirmed'}),
          throwsA(isA<ArgumentError>()),
          reason: 'refused: "$key" is not a key update writes',
        );
        final after = (await r.byId('${id}_$key'))!;
        expect(
          after['status'],
          'pending',
          reason: 'half-written: the refused update changed the status',
        );
        expect(
          after[key],
          isNot(value),
          reason: 'stored: "$key" came back with the refused value',
        );
      }
    });

    test('a value Postgres cannot store is refused, and nothing is '
        'half-written', () async {
      final bad = <String, Map<String, dynamic>>{
        'status: null': {'status': null},
        'appointmentDate: null': {
          'appointmentDate': null,
          'status': 'confirmed',
        },
        'appointmentDate: not a date': {
          'appointmentDate': 'not a date',
          'status': 'confirmed',
        },
        'endsAt: 42': {'endsAt': 42, 'status': 'confirmed'},
        'arrivedAt: yesterday': {
          'arrivedAt': 'yesterday',
          'status': 'confirmed',
        },
        'artistId: 7': {'artistId': 7, 'status': 'confirmed'},
        'artistNameKept: 7': {
          'artistId': 'artist-a',
          'artistNameKept': 7,
          'status': 'confirmed',
        },
        // R1: a name without the id it names would leave a booking under one
        // collaborateur and its revenue under another.
        'artistNameKept without artistId': {
          'artistNameKept': 'Awa',
          'status': 'confirmed',
        },
      };
      var n = 0;
      for (final MapEntry(key: label, value: changes) in bad.entries) {
        final r = repo();
        final own = at.add(Duration(hours: 2 * n));
        final bid = '${id}_bad${n++}';
        await r.create(_booking(id: bid, currency: 'XAF', at: own));
        await expectLater(
          r.update(bid, changes),
          throwsA(isA<ArgumentError>()),
          reason: 'refused: $label is not a value Postgres can store',
        );
        final after = (await r.byId(bid))!;
        expect(
          after['status'],
          'pending',
          reason:
              'half-written: the refused update ($label) changed the '
              'status',
        );
        expect(
          norm(after['appointmentDate']),
          norm(own.toIso8601String()),
          reason: 'half-written: the refused update ($label) moved the date',
        );
      }
    });

    test('what a twin hands out is a copy, never what it stores', () async {
      final r = repo();
      final arg = _booking(id: id, currency: 'XAF');

      Future<void> untouched(String where) async {
        final now = (await r.byId(id))!;
        expect(
          now['notes'],
          isNull,
          reason: 'aliased: editing the map $where changed the store',
        );
        expect(
          now['serviceIds'],
          ['service1'],
          reason:
              'aliased (nested): editing a list inside the map $where '
              'changed the store',
        );
      }

      void edit(Map<String, dynamic> m) {
        m['notes'] = 'EDITED';
        (m['serviceIds'] as List).add('EDITED');
      }

      final created = (await r.create(arg))!;
      edit(arg);
      await untouched('passed to create');
      edit(created);
      await untouched('create returned');
      edit((await r.byId(id))!);
      await untouched('byId returned');
      edit((await r.listForUser('u_contract')).single);
      await untouched('listForUser returned');
      edit((await r.listForProvider('p_currency_contract')).single);
      await untouched('listForProvider returned');
      edit((await r.update(id, {'status': 'confirmed'}))!);
      await untouched('update returned');
      edit(
        (await r.confirmedInWindow(
          at.subtract(const Duration(minutes: 1)),
          at,
        )).single,
      );
      await untouched('confirmedInWindow returned');
    });

    test('endsAt is written, never read back — on either twin', () async {
      final r = repo();
      await r.create(_booking(id: id, currency: 'XAF'));
      final moved = at.add(const Duration(days: 2));
      final updated = await r.update(id, {
        'appointmentDate': moved.toIso8601String(),
        'endsAt': moved.add(const Duration(minutes: 30)).toIso8601String(),
      });
      final reads = <String, Map<String, dynamic>?>{
        'update': updated,
        'byId': await r.byId(id),
        'listForUser': (await r.listForUser('u_contract')).single,
        'listForProvider': (await r.listForProvider(
          'p_currency_contract',
        )).single,
      };
      for (final MapEntry(key: where, value: read) in reads.entries) {
        expect(
          read!.containsKey('endsAt'),
          isFalse,
          reason:
              'shape: $where returned endsAt, which Postgres never reads '
              'back',
        );
      }
    });
  });

  // ---- R2: the revenue reads (docs/design/pro-revenue-analytics.md §8.3) ----
  group('R2: the revenue reads', () {
    const pid = 'p_revenue_contract';
    final base = DateTime.utc(2031, 3, 10, 9);

    Map<String, dynamic> booking(
      String id, {
      required DateTime at,
      String status = 'completed',
      String? artistId,
      String userId = 'u_rev',
      String? channel = 'app',
      List<String> serviceIds = const ['svc-a'],
      String providerId = pid,
      int minutes = 60,
      String? phone,
    }) => {
      'id': id,
      'currency': 'XOF',
      'userId': userId,
      'providerId': providerId,
      'serviceIds': serviceIds,
      'artistId': artistId,
      'appointmentDate': at.toIso8601String(),
      'durationMinutes': minutes,
      'status': status,
      'totalPrice': 10000,
      'depositAmount': 0,
      'balanceDue': 10000,
      'cancellationWindowHours': 24,
      'clientName': null,
      'clientPhone': phone,
      'notes': null,
      'depositScreenshotUrl': null,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'serviceLines': [
        for (final s in serviceIds)
          {
            'serviceId': s,
            'name': 'Nom $s',
            'price': 10000 / serviceIds.length,
            'durationMinutes': 60,
          },
      ],
      'artistNameKept': null,
      'channel': channel,
    };

    test('revenueRows: the range is [from, to), ordered by start then id, '
        'this salon only, the narrow keys only', () async {
      final r = repo();
      await r.create(
        booking('r-before', at: base.subtract(const Duration(seconds: 1))),
      );
      await r.create(booking('r-from-b', at: base, phone: '+2250700000001'));
      await r.create(booking('r-from-a', at: base));
      await r.create(booking('r-mid', at: base.add(const Duration(hours: 5))));
      await r.create(booking('r-to', at: base.add(const Duration(days: 1))));
      await r.create(
        booking(
          'r-other',
          at: base.add(const Duration(hours: 1)),
          providerId: 'p_other_salon',
        ),
      );

      final rows = await r.revenueRows(
        pid,
        base,
        base.add(const Duration(days: 1)),
      );
      expect(
        [for (final x in rows) x['id']],
        ['r-from-a', 'r-from-b', 'r-mid'],
        reason: 'from is included, to excluded; ties by id',
      );
      for (final x in rows) {
        expect(
          x.keys.toSet(),
          kRevenueRowKeys,
          reason: 'no client field, no deposit, nothing but the fold\'s',
        );
      }
      final first = rows.first;
      expect(first['serviceIds'], [
        'svc-a',
      ], reason: 'a list, whatever the storage form');
      expect(first['serviceLines'], isA<List<dynamic>>());
      expect((first['serviceLines'] as List).single['serviceId'], 'svc-a');
      expect(first['totalPrice'], isA<double>());
      expect(first['durationMinutes'], 60);
      expect(first['channel'], 'app');
      expect(DateTime.parse(first['appointmentDate'] as String), base);
    });

    test('revenueLedger: statuses; « upcoming » / « toClose » by the END '
        'against asOf', () async {
      final r = repo();
      final asOf = base.add(const Duration(hours: 3));
      await r.create(booking('l-done', at: base));
      await r.create(
        booking('l-noshow', at: base, status: 'noShow', artistId: 'art-1'),
      );
      await r.create(
        booking('l-cancel', at: base, status: 'cancelled', artistId: 'art-2'),
      );
      // Ends exactly at asOf (2 h + 60 min): still « upcoming ».
      await r.create(
        booking(
          'l-ends-now',
          status: 'confirmed',
          at: base.add(const Duration(hours: 2)),
          artistId: 'art-3',
        ),
      );
      // Ended a minute before asOf: « toClose ».
      await r.create(
        booking(
          'l-ended',
          status: 'confirmed',
          at: base.add(const Duration(hours: 1, minutes: 59)),
          artistId: 'art-4',
        ),
      );
      // Began before asOf, ends after (a 3-hour booking): « upcoming ».
      await r.create(
        booking(
          'l-running',
          status: 'confirmed',
          at: base.add(const Duration(hours: 1)),
          minutes: 180,
          artistId: 'art-5',
        ),
      );
      await r.create(
        booking(
          'l-pending',
          status: 'pending',
          at: base.add(const Duration(hours: 6)),
          artistId: 'art-6',
        ),
      );

      Future<List<Object?>> ids(RevenueLedgerStatus status) async {
        final page = await r.revenueLedger(
          pid,
          fromUtc: base,
          toUtcExclusive: base.add(const Duration(days: 1)),
          status: status,
          asOf: asOf,
          limit: 50,
          offset: 0,
        );
        expect(page.total, page.items.length);
        return [for (final x in page.items) x['id']];
      }

      expect(await ids(RevenueLedgerStatus.completed), ['l-done']);
      expect(await ids(RevenueLedgerStatus.noShow), ['l-noshow']);
      expect(await ids(RevenueLedgerStatus.cancelled), ['l-cancel']);
      expect(await ids(RevenueLedgerStatus.upcoming), [
        'l-running',
        'l-ends-now',
      ], reason: 'soonest first');
      expect(await ids(RevenueLedgerStatus.toClose), ['l-ended']);
    });

    test('revenueLedger: the filters — none and empty artist alike, the '
        'filed channel, a prestation in either storage form', () async {
      final r = repo();
      await r.create(booking('f-null', at: base));
      await r.create(
        booking(
          'f-empty',
          at: base.add(const Duration(hours: 1)),
          artistId: '',
        ),
      );
      await r.create(
        booking(
          'f-art',
          at: base.add(const Duration(hours: 2)),
          artistId: 'art-1',
          channel: 'web',
        ),
      );
      await r.create(
        booking(
          'f-manual',
          at: base.add(const Duration(hours: 3)),
          userId: 'manual',
          channel: null,
          serviceIds: ['svc-b', 'svc-a'],
        ),
      );
      await r.create(
        booking(
          'f-old-online',
          at: base.add(const Duration(hours: 4)),
          channel: null,
          serviceIds: ['svc-c'],
        ),
      );

      Future<List<Object?>> ids({
        String? artistId,
        String? serviceId,
        String? channel,
      }) async {
        final page = await r.revenueLedger(
          pid,
          fromUtc: base,
          toUtcExclusive: base.add(const Duration(days: 1)),
          status: RevenueLedgerStatus.completed,
          asOf: base,
          limit: 50,
          offset: 0,
          artistId: artistId,
          serviceId: serviceId,
          channel: channel,
        );
        return [for (final x in page.items) x['id']]..sort();
      }

      expect(await ids(artistId: 'none'), [
        'f-empty',
        'f-manual',
        'f-null',
        'f-old-online',
      ]);
      expect(await ids(artistId: 'art-1'), ['f-art']);
      expect(await ids(channel: 'web'), ['f-art']);
      expect(await ids(channel: 'salon'), [
        'f-manual',
      ], reason: 'a manual booking with no channel is the salon\'s');
      expect(await ids(channel: 'online'), [
        'f-old-online',
      ], reason: 'an online booking with no channel is « online »');
      expect(await ids(channel: 'app'), ['f-empty', 'f-null']);
      expect(await ids(serviceId: 'svc-a'), [
        'f-art',
        'f-empty',
        'f-manual',
        'f-null',
      ]);
      expect(await ids(serviceId: 'svc-b'), ['f-manual']);
      expect(await ids(serviceId: 'svc-z'), isEmpty);
    });

    test('revenueLedger: newest first, ties by id; pages; the total counts '
        'every match; the phone travels, for the name lookup', () async {
      final r = repo();
      for (var i = 0; i < 5; i++) {
        await r.create(
          booking(
            'p-$i',
            at: base.add(Duration(hours: i)),
            phone: '+22507000000$i',
          ),
        );
      }
      // A tie on the start with p-4 (no collaborateur, so no slot guard).
      await r.create(booking('p-0b', at: base.add(const Duration(hours: 4))));

      Future<({List<Map<String, dynamic>> items, int total})> page(
        int offset,
      ) => r.revenueLedger(
        pid,
        fromUtc: base,
        toUtcExclusive: base.add(const Duration(days: 1)),
        status: RevenueLedgerStatus.completed,
        asOf: base,
        limit: 2,
        offset: offset,
      );

      final p1 = await page(0);
      final p2 = await page(2);
      final p3 = await page(4);
      final p4 = await page(6);
      expect(p1.total, 6);
      expect(p4.total, 6, reason: 'an empty page still says the total');
      expect(p4.items, isEmpty);
      expect(
        [
          for (final p in [p1, p2, p3])
            for (final x in p.items) x['id'],
        ],
        ['p-0b', 'p-4', 'p-3', 'p-2', 'p-1', 'p-0'],
      );
      expect(p1.items.last['clientPhone'], '+225070000004');
      expect(p1.items.last.keys.toSet(), {...kRevenueRowKeys, 'clientPhone'});
    });

    test('hasCompleted: this salon\'s, ever', () async {
      final r = repo();
      await r.create(booking('h-other', at: base, providerId: 'p_other_salon'));
      await r.create(booking('h-confirmed', at: base, status: 'confirmed'));
      expect(await r.hasCompleted(pid), isFalse);
      await r.create(
        booking('h-done', at: base.subtract(const Duration(days: 900))),
      );
      expect(await r.hasCompleted(pid), isTrue);
    });
  });
}

/// A booking map shaped like the one the service builds, for the paths that
/// do not need the service.
Map<String, dynamic> _booking({
  required String id,
  required String currency,
  DateTime? at,
}) {
  at ??= DateTime.utc(2030, 6, 25, 9);
  return {
    'id': id,
    'currency': currency,
    'userId': 'u_contract',
    'providerId': 'p_currency_contract',
    'serviceIds': ['service1'],
    'artistId': null,
    'appointmentDate': at.toIso8601String(),
    'durationMinutes': 30,
    'status': 'pending',
    'totalPrice': 15000.0,
    'depositAmount': 4500.0,
    'balanceDue': 10500.0,
    'cancellationWindowHours': 24,
    'clientName': null,
    'clientPhone': null,
    'notes': null,
    'depositScreenshotUrl': null,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  };
}

/// Delegates to [_inner] and keeps a DEEP COPY of every map handed to
/// `create`. A copy, not the reference: the in-memory twin used to store the
/// caller's own map and mutate it in place on `update`, so a kept reference
/// followed every later change and the twin was compared with itself. Both
/// twins now copy (docs/design/appointment-twin-update.md §5.4); this copy
/// stays, so the record does not depend on that.
class _Recording implements AppointmentRepository {
  _Recording(this._inner);

  final AppointmentRepository _inner;
  final written = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>?> create(Map<String, dynamic> appointment) {
    written.add(jsonDecode(jsonEncode(appointment)) as Map<String, dynamic>);
    return _inner.create(appointment);
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    String? status,
    String? matchPhone,
  }) => _inner.listForUser(userId, status: status, matchPhone: matchPhone);

  @override
  Future<List<Map<String, dynamic>>> listForProvider(
    String providerId, {
    String? status,
  }) => _inner.listForProvider(providerId, status: status);

  @override
  Future<Map<String, dynamic>?> byId(String id) => _inner.byId(id);

  @override
  Future<Map<String, dynamic>?> update(
    String id,
    Map<String, dynamic> changes,
  ) => _inner.update(id, changes);

  @override
  Future<List<String>> anonymizeUser(String userId) =>
      _inner.anonymizeUser(userId);

  @override
  Future<int> wipeForProvider(String providerId) =>
      _inner.wipeForProvider(providerId);

  @override
  Future<Map<String, int>> countsByStatus() => _inner.countsByStatus();

  @override
  Future<List<Map<String, dynamic>>> completedForAnalytics(DateTime from) =>
      _inner.completedForAnalytics(from);

  @override
  Future<List<Map<String, dynamic>>> confirmedInWindow(
    DateTime from,
    DateTime to,
  ) => _inner.confirmedInWindow(from, to);

  @override
  Future<List<Map<String, dynamic>>> revenueRows(
    String providerId,
    DateTime fromUtc,
    DateTime toUtcExclusive,
  ) => _inner.revenueRows(providerId, fromUtc, toUtcExclusive);

  @override
  Future<({List<Map<String, dynamic>> items, int total})> revenueLedger(
    String providerId, {
    required DateTime fromUtc,
    required DateTime toUtcExclusive,
    required RevenueLedgerStatus status,
    required DateTime asOf,
    required int limit,
    required int offset,
    String? artistId,
    String? serviceId,
    String? channel,
  }) => _inner.revenueLedger(
    providerId,
    fromUtc: fromUtc,
    toUtcExclusive: toUtcExclusive,
    status: status,
    asOf: asOf,
    limit: limit,
    offset: offset,
    artistId: artistId,
    serviceId: serviceId,
    channel: channel,
  );

  @override
  Future<bool> hasCompleted(String providerId) =>
      _inner.hasCompleted(providerId);
}
