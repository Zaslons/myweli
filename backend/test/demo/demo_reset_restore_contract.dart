import 'dart:convert';

import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/demo/demo_reset_service.dart';
import 'package:myweli_backend/src/demo/demo_snapshot_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:test/test.dart';

/// The demo salon's reset, over a providers store and a snapshot store, run
/// against BOTH twins: in memory (`demo_reset_restore_test.dart`) and
/// Postgres (`db/postgres_repositories_test.dart`). Not a test file itself.
///
/// docs/design/demo-reset-restore.md §2.3, §5.1, §5.4 (B16.2, decisions
/// 250–252). The owner curates the salon, the snapshot is captured, then a
/// « reviewer » changes it, and the weekly reset must put back the curated
/// salon: its profile, services (list, fields, order), hours, before/after
/// pairs and artists, while leaving the admin's `featured` and the reviews'
/// rating alone.
///
/// **Only the real writers** make the salon and change it: `addService`,
/// `updateService`, `deleteService`, `replaceAvailability`, `addArtist`, … —
/// the paths a reviewer's app takes. A salon built through `updateProfile`
/// replaces its lists, which is why `demo_reset_test.dart` never saw any of
/// this (§2.4).
///
/// **The expected values are a JSON copy taken at the capture**, never a
/// reference: the in-memory store's `byId` hands out the live map, so a
/// reference would follow the reviewer's edits.
///
/// **The curated salon is in `Asia/Tokyo`, with a blocked day,** and the
/// reviewer moves it to `Africa/Abidjan` (through the repository, as an area
/// change would): restored in the wrong order, the blocked day is stored
/// under the reviewer's zone and reads back a day early (§5.1).
///
/// One scenario, run once ([setUpAll]); one test per part, each with its
/// reason text in brackets, so one red does not hide the next. The last case
/// runs a scenario of its own.
///
/// [created] gets each salon id (Postgres deletes them afterwards).
/// [ratingColumn], Postgres only, reads the `rating` column.
void demoResetRestoreContract({
  required ProvidersRepository Function() providers,
  required DemoSnapshotRepository Function() snapshots,
  required void Function(String id) created,
  Future<double> Function(String providerId)? ratingColumn,
}) {
  final t0 = DateTime.utc(2026, 8, 26, 3);
  final due = t0.add(const Duration(days: 7));
  final tag = DateTime.now().microsecondsSinceEpoch;

  Map<String, dynamic> copy(Object? o) =>
      jsonDecode(jsonEncode(o)) as Map<String, dynamic>;

  Map<String, dynamic> slot(String s, String e) => {
    'startTime': '2024-01-01T$s:00.000Z',
    'endTime': '2024-01-01T$e:00.000Z',
    'isAvailable': true,
  };

  Map<String, dynamic> service(
    String id,
    String name,
    double price,
    String pid,
  ) => {
    'id': id,
    'name': name,
    'description': '',
    'price': price,
    'priceMax': null,
    'durationMinutes': 30,
    'durationVariants': <String, dynamic>{},
    'providerId': pid,
    'artistIds': <dynamic>[],
    'active': true,
  };

  /// The hours as compared: each weekday's windows as a SET (Postgres reads
  /// them with no `ORDER BY`), the blocked days as a set.
  Object hours(Object? availability) {
    final a = availability as Map;
    Map<String, Set<String>> windows(Object? byDay) => {
      for (final e in ((byDay as Map?) ?? const {}).entries)
        e.key as String: {for (final s in e.value as List) jsonEncode(s)},
    };
    return {
      'bufferMinutes': a['bufferMinutes'],
      'bookingHorizonDays': a['bookingHorizonDays'],
      'minimumNoticeMinutes': a['minimumNoticeMinutes'],
      'weeklySchedule': windows(a['weeklySchedule']),
      'breaks': windows(a['breaks']),
      'blockedDates': {...(a['blockedDates'] as List? ?? const [])},
    };
  }

  /// A demo account owning a fresh salon, and the reset service over it.
  Future<
    ({
      String id,
      DemoResetService service,
      ProvidersRepository p,
      DemoSnapshotRepository snaps,
    })
  >
  demoWorld() async {
    final p = providers();
    final snaps = snapshots();
    final tokens = TokenService(secret: 'test-secret');
    final auth = InMemoryProviderAuthRepository(
      tokens: tokens,
      echoDevCode: true,
    );
    final members = InMemoryMembershipRepository();
    final appointments = InMemoryAppointmentRepository();
    final service = DemoResetService(
      auth,
      p,
      appointments,
      InMemoryClientsRepository(),
      InMemorySalonSubscriptionRepository(),
      members,
      BookingService(p, appointments, SlotService(p, appointments)),
      snaps,
      log: (_) {},
    );
    final reg = await auth.register(
      businessName: 'Maison Nala',
      businessType: 'salon',
      phoneNumber: '+2250700001603',
      email: kDemoProviderEmail,
      authProvider: 'email',
      emailCode: (await auth.requestEmailOtp(kDemoProviderEmail)).code,
    );
    final salon = await p.createSalon(
      name: 'Maison Nala',
      category: 'salon',
      phoneNumber: '+2250700001603',
    );
    final id = salon['id'] as String;
    created(id);
    await auth.linkProvider(reg.provider!.id, id);
    await members.ensureOwner(
      providerId: id,
      accountId: reg.provider!.id,
      email: kDemoProviderEmail,
    );
    return (id: id, service: service, p: p, snaps: snaps);
  }

  late Map<String, dynamic> expected;
  late Map<String, dynamic> after;
  late String outcome;
  late String salonId;
  late DemoSnapshotRepository snapshotStore;

  setUpAll(() async {
    final w = await demoWorld();
    salonId = w.id;
    snapshotStore = w.snaps;
    final p = w.p;
    final id = w.id;

    // The owner curates, through the real writers.
    await p.updateProfile(id, {
      'description': 'La vitrine de démonstration.',
      'timezone': 'Asia/Tokyo',
    });
    final s1 = 'b16_2_r1_$tag', s2 = 'b16_2_r2_$tag', s3 = 'b16_2_r3_$tag';
    for (final s in [
      service(s1, 'Coupe', 5000, id),
      service(s2, 'Brushing', 7000, id),
      service(s3, 'Tresses', 15000, id),
    ]) {
      await p.addService(id, s);
    }
    await p.replaceAvailability(id, {
      'weeklySchedule': {
        '1': [slot('09:00', '12:00'), slot('13:00', '18:00')],
        '6': [slot('10:00', '14:00')],
      },
      'breaks': {
        '1': [slot('12:00', '13:00')],
      },
      // Tokyo midnight of 2026-12-25 — the day, as a salon instant.
      'blockedDates': ['2026-12-24T15:00:00.000Z'],
      'bufferMinutes': 10,
      'bookingHorizonDays': 45,
      'minimumNoticeMinutes': 120,
    });
    await p.addArtist(id, {'id': 'b16_2_a1_$tag', 'name': 'Awa'});
    // The in-memory snapshot carries `featured` only if the key exists.
    await p.setFeatured(id, false);

    expected = copy(await p.byId(id));
    await w.service.capture(t0);

    // A reviewer, through the same writers.
    await p.addService(
      id,
      service('b16_2_r9_$tag', 'Ajout du relecteur', 1, id),
    );
    await p.updateService(id, s1, {'price': 1.0});
    await p.deleteService(id, s2);
    await p.replaceAvailability(id, {
      'weeklySchedule': <String, dynamic>{},
      'breaks': <String, dynamic>{},
      'blockedDates': <String>[],
      'bufferMinutes': 0,
    });
    await p.updateProfile(id, {
      'name': 'DEFACED',
      'timezone': 'Africa/Abidjan',
    });
    await p.updateBeforeAfters(id, [
      {'id': 'b16_2_ba_$tag', 'beforeUrl': 'b', 'afterUrl': 'a'},
    ]);
    await p.addArtist(id, {'id': 'b16_2_a9_$tag', 'name': 'Relecteur'});
    await p.updateArtist(id, 'b16_2_a1_$tag', {'name': 'Awa (renommée)'});
    // Not a reviewer: the admin's flag and the reviews' aggregate.
    await p.setFeatured(id, true);
    await p.updateRatings(id, rating: 4.5, reviewCount: 2);

    outcome = (await w.service.tickIfDue(due)).outcome;
    after = copy(await p.byId(id));
  });

  test('[profile] the control: the reset ran and put the name back', () {
    expect(outcome, 'ran', reason: '[profile] the reset did not run');
    expect(after['name'], expected['name'], reason: '[profile] name');
    expect(
      after['description'],
      expected['description'],
      reason: '[profile] description',
    );
  });

  test('[services] the curated list, each field, in its order', () {
    expect(
      after['services'],
      expected['services'],
      reason: '[services] not the curated services',
    );
  });

  test(
    '[hours] the curated hours, the blocked day under the salon\'s zone',
    () {
      expect(
        hours(after['availability']),
        hours(expected['availability']),
        reason: '[hours] not the curated hours',
      );
    },
  );

  test('[before-after] the curated pairs (none), not the reviewer\'s', () {
    expect(
      after['beforeAfters'] ?? const <dynamic>[],
      expected['beforeAfters'] ?? const <dynamic>[],
      reason: '[before-after] the reviewer\'s pairs stayed',
    );
  });

  test('[artists] the curated artists', () {
    expect(
      after['artists'],
      expected['artists'],
      reason: '[artists] not the curated artists',
    );
  });

  test('[featured] the admin\'s flag is left alone', () {
    expect(
      after['featured'],
      isTrue,
      reason: '[featured] the reset reverted it',
    );
  });

  test('[rating] the reviews\' rating is left alone', () {
    expect(after['rating'], 4.5, reason: '[rating] the reset reverted it');
    expect(
      after['reviewCount'],
      2,
      reason: '[rating] the reset reverted reviewCount',
    );
  });

  final readRating = ratingColumn;
  if (readRating != null) {
    test('[rating column] the column agrees with the document', () async {
      expect(
        await readRating(salonId),
        after['rating'],
        reason: '[rating column] column and document disagree',
      );
    });
  }

  test(
    '[snapshot kept] the snapshot still holds the curated services',
    () async {
      expect(
        copy((await snapshotStore.read())!.doc)['services'],
        expected['services'],
        reason: '[snapshot kept] the reviewer\'s edits reached the snapshot',
      );
    },
  );

  test('[bad snapshot] a snapshot the writers cannot take is refused, and '
      'nothing changes', () async {
    final w = await demoWorld();
    await w.p.addService(w.id, service('b16_2_bad_$tag', 'Coupe', 5000, w.id));
    final before = copy(await w.p.byId(w.id));
    // A captured document whose service lacks its duration, and whose name
    // differs: a merge before the refusal would show.
    final bad = copy(before)
      ..['name'] = 'Nom du cliché'
      ..['services'] = [
        {'id': 'b16_2_bad2_$tag', 'name': 'Sans durée', 'price': 1.0},
      ];
    await w.snaps.capture(providerId: w.id, doc: bad, capturedAt: t0);

    String got;
    try {
      got = (await w.service.tickIfDue(due)).outcome;
    } on Object catch (e) {
      got = 'threw: $e';
    }
    expect(got, 'refused:bad_snapshot', reason: '[bad snapshot] not refused');
    final now = copy(await w.p.byId(w.id));
    expect(now['name'], before['name'], reason: '[bad snapshot] name changed');
    expect(
      now['services'],
      before['services'],
      reason: '[bad snapshot] services changed',
    );
  });
}
