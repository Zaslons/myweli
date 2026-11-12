import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:myweli_backend/src/provider_account_service.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:myweli_backend/src/validation/salon_place_notice_repository.dart';
import 'package:myweli_backend/src/validation/salon_place_notice_service.dart';
import 'package:myweli_backend/src/validation/salon_validation_repository.dart';
import 'package:test/test.dart';

import 'validation_world.dart';

/// The cap can be read no more: every write throws.
class _BrokenNotices extends InMemorySalonPlaceNoticeRepository {
  @override
  Future<PlaceNoticeTurn> recordSave(
    String providerId,
    DateTime now, {
    required Map<String, String?> after,
    required Iterable<String> fields,
  }) => throw StateError('salon_place_notices is unreachable');
}

/// One salon's claim fails; the others go through.
class _FailingClaim extends InMemorySalonPlaceNoticeRepository {
  _FailingClaim(this.failing);

  final String failing;

  @override
  Future<PlaceSummaryClaim?> claimSummary(
    String providerId,
    DateTime now, {
    required Map<String, String?> current,
    required int seenSaves,
  }) async {
    if (providerId == failing) {
      throw StateError('+2250700000009 Rue des Jardins admin@myweli.com');
    }
    return super.claimSummary(
      providerId,
      now,
      current: current,
      seenSaves: seenSaves,
    );
  }
}

/// A save lands right after the tick read the salon: once [afterNextRead] is
/// set, the next [byId] hands back a COPY of the salon as it was — Postgres
/// hands back a copy, the in-memory twin the live document — then runs it.
class _SaveLandsAfterRead extends InMemoryProvidersRepository {
  _SaveLandsAfterRead() : super([]);

  Future<void> Function()? afterNextRead;

  @override
  Future<Map<String, dynamic>?> byId(String id) async {
    final hook = afterNextRead;
    if (hook == null) return super.byId(id);
    afterNextRead = null;
    final doc = await super.byId(id);
    final read = doc == null ? null : Map<String, dynamic>.of(doc);
    await hook();
    return read;
  }
}

/// Decision 133 — the cap on the admin's place-change e-mails
/// (docs/design/salon-go-live-approval.md §5.1, T82): the first change of a
/// quiet hour at once, the rest in one summary once the hour has passed,
/// nothing for a suspended salon. Over the in-memory world, the catalogue's
/// real save path, and the reminders cron's tick.
void main() {
  late ValidationWorld w;

  setUp(() => w = ValidationWorld());

  ProviderCatalogService catalog([SalonPlaceNoticeService? notices]) =>
      ProviderCatalogService(
        w.providers,
        w.auth,
        MembershipService(w.members, w.auth),
        validations: w.validations,
        placeNotices: notices ?? w.placeNoticeService,
      );

  /// A salon validated and live, the admin's inbox emptied.
  Future<({String id, String ownerId})> validated({
    String name = 'Salon Awa',
  }) async {
    final s = await w.salon(name: name);
    await w.validateLive(s.id);
    w.adminMail.sent.clear();
    return s;
  }

  Future<void> save(
    ({String id, String ownerId}) s,
    Map<String, dynamic> body, {
    int atMinute = 0,
  }) async {
    w.now = DateTime.utc(2026, 11, 12, 9).add(Duration(minutes: atMinute));
    final r = await catalog().updateProfile(s.ownerId, s.id, body);
    expect(r.ok, isTrue, reason: '${r.error}');
  }

  Future<int> tick(int atMinute) {
    w.now = DateTime.utc(2026, 11, 12, 9).add(Duration(minutes: atMinute));
    return w.placeNoticeService.tick(w.now);
  }

  group('the save path (ProviderCatalogService)', () {
    test('the first change of a quiet hour is e-mailed at once, exactly as '
        'before the cap; the changes in the hour after it are recorded, not '
        'e-mailed', () async {
      final s = await validated();
      await save(s, {'phoneNumber': '+2250700000010'});
      final first = w.adminMail.sent.single;
      expect(first.subject, 'Salon Awa a modifié son téléphone');
      expect(
        first.text,
        contains('Téléphone : +2250700000009 → +2250700000010'),
      );

      await save(s, {'address': 'Rue Neuve'}, atMinute: 10);
      await save(s, {'phoneNumber': '+2250700000011'}, atMinute: 20);
      expect(w.adminMail.sent, hasLength(1), reason: 'recorded, not e-mailed');
      final row = (await w.placeNotices.get(s.id))!;
      expect(row.pendingCount, 2);
      expect(row.pendingFields, ['address', 'phone']);
      expect(row.reported['phone'], '+2250700000010');
      expect(
        w.placeLogs.where((l) => l.contains('outcome=recorded')),
        hasLength(2),
      );
    });

    test('two saves at once in a quiet hour → ONE e-mail', () async {
      final s = await validated();
      w.now = DateTime.utc(2026, 11, 12, 9);
      final results = await Future.wait([
        catalog().updateProfile(s.ownerId, s.id, {
          'phoneNumber': '+2250700000010',
        }),
        catalog().updateProfile(s.ownerId, s.id, {'address': 'Rue Neuve'}),
      ]);
      expect(results.every((r) => r.ok), isTrue);
      expect(w.adminMail.sent, hasLength(1));
      expect((await w.placeNotices.get(s.id))!.pendingCount, 1);
    });

    test('a SUSPENDED salon\'s save records nothing and sends nothing — the '
        'admin already acted', () async {
      final s = await validated();
      await w.admin.suspend('admin_1', s.id, null);
      await save(s, {'phoneNumber': '+2250700000010'});
      expect(w.adminMail.sent, isEmpty);
      expect(await w.placeNotices.get(s.id), isNull);
      expect(
        (await w.providers.byId(s.id))!['phoneNumber'],
        '+2250700000010',
        reason: 'the save itself stands',
      );
    });

    test('a save that changes none of the four records nothing', () async {
      final s = await validated();
      await save(s, {
        'name': 'Salon Awa & Fils',
        'latitude': 5.35,
        'longitude': -3.99,
        'phoneNumber': '+2250700000009',
      });
      expect(w.adminMail.sent, isEmpty);
      expect(await w.placeNotices.get(s.id), isNull);
    });

    test('the cap cannot be read → the e-mail goes as before the cap, and '
        'the log says so without the address', () async {
      final s = await validated();
      final notices = SalonPlaceNoticeService(
        _BrokenNotices(),
        w.providers,
        w.validations,
        w.adminNotifier,
        clock: () => w.now,
        log: w.placeLogs.add,
      );
      final r = await catalog(
        notices,
      ).updateProfile(s.ownerId, s.id, {'phoneNumber': '+2250700000010'});
      expect(r.ok, isTrue);
      expect(w.adminMail.sent, hasLength(1));
      expect(
        w.placeLogs.single,
        'place_notice provider=${s.id} outcome=cap_unavailable '
        'error=StateError',
      );
    });
  });

  group('the summary (tick, by the reminders cron)', () {
    /// The first save e-mailed at 09:00, two more recorded at 09:10 and
    /// 09:20.
    Future<({String id, String ownerId})> owing() async {
      final s = await validated();
      await save(s, {'phoneNumber': '+2250700000010'});
      await save(s, {'address': 'Rue Neuve'}, atMinute: 10);
      await save(s, {'phoneNumber': '+2250700000011'}, atMinute: 20);
      w.adminMail.sent.clear();
      return s;
    }

    test('nothing before the hour; once it has passed, ONE summary — the '
        'values last reported → the values now, the kinds, how many saves, '
        'since when; a tick run again sends nothing', () async {
      final s = await owing();
      expect(await tick(59), 0);
      expect(w.adminMail.sent, isEmpty);

      expect(await tick(60), 1);
      final mail = w.adminMail.sent.single;
      expect(mail.to, 'admin@myweli.com');
      expect(mail.classification, EmailClass.warm);
      expect(
        mail.subject,
        'Salon Awa a encore modifié son adresse et son téléphone',
      );
      expect(
        mail.text,
        contains(
          '2 modifications depuis le 12/11/2026 à 09:10 (heure d’Abidjan)',
        ),
      );
      expect(mail.text, contains('Adresse : Rue des Jardins → Rue Neuve'));
      expect(
        mail.text,
        contains('Téléphone : +2250700000010 → +2250700000011'),
      );
      expect(mail.text, isNot(contains('Emplacement')));
      expect(
        mail.text,
        contains('https://admin.myweli.com/#/admin/providers/${s.id}'),
      );

      expect(await tick(75), 0, reason: 'claimed once');
      expect(w.adminMail.sent, hasLength(1));
      final row = (await w.placeNotices.get(s.id))!;
      expect(row.pendingCount, 0);
      expect(row.reported['phone'], '+2250700000011');
      expect(row.reported['address'], 'Rue Neuve');
    });

    test('A SAVE LANDING BETWEEN THE TICK\'S READ AND ITS CLAIM is never '
        'lost: the claim misses, nothing is cleared, and the next tick sends '
        'it with the salon as it stands', () async {
      final hooked = _SaveLandsAfterRead();
      w = ValidationWorld(providers: hooked);
      final s = await owing();
      hooked.afterNextRead = () async {
        final r = await catalog().updateProfile(s.ownerId, s.id, {
          'phoneNumber': '+2250700000077',
        });
        expect(r.ok, isTrue, reason: '${r.error}');
      };

      expect(
        await tick(60),
        0,
        reason: 'the salon was read before that save: no summary from it',
      );
      expect(w.adminMail.sent, isEmpty);
      final row = (await w.placeNotices.get(s.id))!;
      expect(row.pendingCount, 3, reason: 'that save counted, nothing cleared');
      expect(row.lastSentAt, DateTime.utc(2026, 11, 12, 9));
      expect(row.reported['phone'], '+2250700000010');

      expect(await tick(75), 1);
      final mail = w.adminMail.sent.single;
      expect(
        mail.text,
        contains(
          '3 modifications depuis le 12/11/2026 à 09:10 (heure d’Abidjan)',
        ),
      );
      expect(
        mail.text,
        contains('Téléphone : +2250700000010 → +2250700000077'),
      );
      expect(
        (await w.placeNotices.get(s.id))!.reported['phone'],
        '+2250700000077',
      );
    });

    test('a value saved back to the one last reported reads « identique au '
        'dernier e-mail », never « X → X »', () async {
      final s = await validated();
      await save(s, {'phoneNumber': '+2250700000010'});
      await save(s, {'phoneNumber': '+2250700000009'}, atMinute: 10);
      await save(s, {'phoneNumber': '+2250700000010'}, atMinute: 20);
      w.adminMail.sent.clear();
      expect(await tick(60), 1);
      final mail = w.adminMail.sent.single;
      expect(mail.subject, 'Salon Awa a encore modifié son téléphone');
      expect(
        mail.text,
        contains('Téléphone : +2250700000010 (identique au dernier e-mail)'),
      );
      expect(mail.text, contains('2 modifications'));
    });

    test('A SALON THAT KEEPS SAVING yields at most one e-mail an hour — '
        'three hours of saves every 10 minutes, ticks every 15', () async {
      final s = await validated();
      final sentAt = <DateTime>[];
      var phone = 0;
      for (var m = 0; m <= 180; m += 5) {
        final before = w.adminMail.sent.length;
        if (m % 10 == 0) {
          await save(s, {
            'phoneNumber': '+22507000000${10 + (phone++ % 2)}',
          }, atMinute: m);
        }
        if (m % 15 == 0) await tick(m);
        if (w.adminMail.sent.length > before) sentAt.add(w.now);
      }
      expect(sentAt.first, DateTime.utc(2026, 11, 12, 9), reason: 'at once');
      for (var i = 1; i < sentAt.length; i++) {
        expect(
          sentAt[i].difference(sentAt[i - 1]),
          greaterThanOrEqualTo(kPlaceNoticeWindow),
          reason: 'e-mail $i',
        );
      }
      expect(sentAt, hasLength(4), reason: '09:00, 10:00, 11:00, 12:00');
    });

    test('THE CRON STOPPED: once the summary owed is 30 minutes past its '
        'hour, the salon\'s next save sends it — one summary, that save in '
        'it; a minute before, the save is only recorded', () async {
      final s = await validated();
      await save(s, {'phoneNumber': '+2250700000010'});
      await save(s, {'address': 'Rue Neuve'}, atMinute: 10);
      w.adminMail.sent.clear();

      await save(s, {'phoneNumber': '+2250700000011'}, atMinute: 89);
      expect(w.adminMail.sent, isEmpty, reason: 'not overdue yet');

      await save(s, {'phoneNumber': '+2250700000012'}, atMinute: 90);
      final mail = w.adminMail.sent.single;
      expect(
        mail.subject,
        'Salon Awa a encore modifié son adresse et son téléphone',
      );
      expect(
        mail.text,
        contains(
          '3 modifications depuis le 12/11/2026 à 09:10 (heure d’Abidjan)',
        ),
      );
      expect(mail.text, contains('Adresse : Rue des Jardins → Rue Neuve'));
      expect(
        mail.text,
        contains('Téléphone : +2250700000010 → +2250700000012'),
      );
      expect(
        w.placeLogs,
        contains('place_notice provider=${s.id} outcome=summary_overdue'),
      );
      final row = (await w.placeNotices.get(s.id))!;
      expect(row.pendingCount, 0);
      expect(row.lastSentAt, DateTime.utc(2026, 11, 12, 10, 30));
      expect(row.reported['phone'], '+2250700000012');

      expect(await tick(105), 0, reason: 'a late tick finds it sent');
      expect(w.adminMail.sent, hasLength(1));
    });

    test('a salon SUSPENDED by the time its summary is due → dropped, not '
        'sent', () async {
      final s = await owing();
      await w.admin.suspend('admin_1', s.id, null);
      expect(await tick(60), 0);
      expect(w.adminMail.sent, isEmpty);
      expect((await w.placeNotices.get(s.id))!.pendingCount, 0);
      expect(
        w.placeLogs.last,
        'place_notice provider=${s.id} outcome=dropped reason=suspended',
      );
    });

    test('a salon no longer validated → dropped; a salon gone → its row '
        'forgotten', () async {
      final s = await owing();
      final unvalidated = SalonPlaceNoticeService(
        w.placeNotices,
        w.providers,
        // A validation record that no longer says approved.
        InMemorySalonValidationRepository(
          providers: InMemoryProvidersRepository([]),
          members: w.members,
        ),
        w.adminNotifier,
        log: w.placeLogs.add,
      );
      w.now = DateTime.utc(2026, 11, 12, 10);
      expect(await unvalidated.tick(w.now), 0);
      expect((await w.placeNotices.get(s.id))!.pendingCount, 0);
      expect(w.placeLogs.last, contains('reason=not_validated'));

      final t = await owing();
      final gone = SalonPlaceNoticeService(
        w.placeNotices,
        InMemoryProvidersRepository([]),
        w.validations,
        w.adminNotifier,
        log: w.placeLogs.add,
      );
      w.now = DateTime.utc(2026, 11, 12, 10);
      expect(await gone.tick(w.now), 0);
      expect(await w.placeNotices.get(t.id), isNull);
      expect(w.adminMail.sent, isEmpty);
    });

    test(
      'one salon\'s failure never stops the others, and its log line '
      'carries the salon id and the error type — nothing the salon typed',
      () async {
        final a = await owing();
        final b = await owing();
        final notices = _FailingClaim(a.id);
        // Move both salons' rows into the failing twin, as they stand.
        for (final id in [a.id, b.id]) {
          final row = (await w.placeNotices.get(id))!;
          await notices.recordSave(
            id,
            row.lastSentAt!,
            after: row.reported,
            fields: const [],
          );
          await notices.recordSave(
            id,
            row.pendingSince!,
            after: row.reported,
            fields: row.pendingFields,
          );
        }
        final logs = <String>[];
        final service = SalonPlaceNoticeService(
          notices,
          w.providers,
          w.validations,
          w.adminNotifier,
          log: logs.add,
        );
        expect(await service.tick(DateTime.utc(2026, 11, 12, 10, 30)), 1);
        expect(w.adminMail.sent, hasLength(1));
        expect(logs, [
          'place_notice provider=${a.id} outcome=failed error=StateError',
        ]);
      },
    );

    test('the values the salon typed are ESCAPED in the summary\'s HTML '
        '(T73)', () async {
      final s = await validated(name: 'Salon <b>Awa</b>');
      await save(s, {'phoneNumber': '+2250700000010'});
      await save(s, {'address': '<img src=x onerror=alert(1)>'}, atMinute: 5);
      w.adminMail.sent.clear();
      await tick(60);
      final mail = w.adminMail.sent.single;
      expect(mail.html, isNot(contains('<img src=x')));
      expect(mail.html, isNot(contains('<b>Awa</b>')));
      expect(mail.html, contains('&lt;img src=x onerror=alert(1)&gt;'));
    });
  });

  group('account erasure', () {
    test('forgets the place last reported — the phone and address in it — and '
        'any summary owed', () async {
      final s = await validated();
      await save(s, {'phoneNumber': '+2250700000010'});
      await save(s, {'address': 'Rue Neuve'}, atMinute: 10);
      final r = await ProviderAccountService(
        w.auth,
        w.providers,
        InMemoryAppointmentRepository(),
        FakeStorageService(),
        w.members,
        validations: w.validations,
        placeNotices: w.placeNotices,
      ).deleteAccount(s.ownerId);
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(await w.placeNotices.get(s.id), isNull);
      expect(await tick(60), 0);
    });
  });
}
