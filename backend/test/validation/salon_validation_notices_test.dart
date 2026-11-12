import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/admin/admin_notifier.dart';
import 'package:myweli_backend/src/messaging/salon_notifier.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/provider_catalog_service.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:test/test.dart';

import 'validation_world.dart';

/// The notifications around the validation (B0.18 —
/// docs/design/salon-go-live-approval.md §5): the « @ » guard every owner
/// sender goes through, and the admin's e-mail on a validated salon's place
/// change (Q6).
void main() {
  late ValidationWorld w;

  setUp(() => w = ValidationWorld());

  group('Member.emailOrNull', () {
    Member member(String email) => Member(
      id: 'm',
      providerId: 'p',
      email: email,
      role: 'owner',
      status: 'active',
      invitedAt: DateTime.utc(2026),
    );

    test('an address is itself; a phone number is no address', () {
      expect(member('awa@salon.ci').emailOrNull, 'awa@salon.ci');
      expect(member('+2250700000001').emailOrNull, isNull);
      expect(member('').emailOrNull, isNull);
    });
  });

  group('THE « @ » GUARD — a phone-registered owner gets the push and the '
      'feed row, and NO e-mail, from every sender', () {
    test('the validation notice', () async {
      final phone = await w.salon(phoneOwner: true);
      await w.notice.approved(phone.id);
      expect(w.pushes.sends, hasLength(1));
      expect(await w.feed.listForUser(phone.ownerId), hasLength(1));
      expect(w.ownerMail.sent, isEmpty);

      final mail = await w.salon();
      await w.notice.refused(mail.id, code: 'photos');
      expect(w.ownerMail.sent, hasLength(1), reason: 'the control: an address');
    });

    test("the subscription scheduler's notices (`_notifyOwner`)", () async {
      final phone = await w.salon(phoneOwner: true);
      final mail = await w.salon();
      for (final s in [phone, mail]) {
        await w.validateLive(s.id);
      }
      w.pushes.sends.clear();
      w.ownerMail.sent.clear();

      w.now = w.now.add(const Duration(days: 80)); // J-14 for both
      final r = await w.scheduler().tick(w.now);
      expect(r.notices, 2);
      expect(w.pushes.sends, hasLength(2), reason: 'both owners get the push');
      expect(w.ownerMail.sent, hasLength(1));
      expect(w.ownerMail.sent.single.to, contains('@'));
    });

    test("the salon alerts (`SalonNotifier`'s e-mail fallback)", () async {
      final phone = await w.salon(phoneOwner: true);
      final mail = await w.salon();
      // No device: the case where the e-mail is the fallback.
      final devices = InMemoryDeviceTokenRepository();
      final notifier = SalonNotifier(
        w.members,
        PushService(w.pushes, devices),
        w.feed,
        InMemoryNotificationPrefsRepository(),
        w.providers,
        email: w.ownerMail,
      );
      for (final s in [phone, mail]) {
        await notifier.notify({
          'id': 'a-${s.id}',
          'providerId': s.id,
          'appointmentDate': '2026-12-01T10:00:00.000Z',
        }, SalonEvent.newBooking);
      }
      expect(w.ownerMail.sent, hasLength(1));
      expect(w.ownerMail.sent.single.to, contains('@'));
      expect(
        await w.feed.listForUser(phone.ownerId),
        hasLength(1),
        reason: 'the feed row still reaches the phone owner',
      );
    });
  });

  group('the place-change e-mail (Q6)', () {
    ProviderCatalogService catalog({bool withNotifier = true}) =>
        ProviderCatalogService(
          w.providers,
          w.auth,
          MembershipService(w.members, w.auth),
          validations: w.validations,
          placeNotices: withNotifier ? w.placeNoticeService : null,
        );

    Future<({String id, String ownerId})> validated() async {
      final s = await w.salon();
      await w.validateLive(s.id);
      w.adminMail.sent.clear();
      return s;
    }

    test('a save that moves the PIN → one e-mail, old and new values, the '
        'link to the salon; the salon stays online', () async {
      final s = await validated();
      final r = await catalog().updateProfile(s.ownerId, s.id, {
        'latitude': 14.69,
        'longitude': -17.44,
      });
      expect(r.ok, isTrue, reason: '${r.error}');
      final mail = w.adminMail.sent.single;
      expect(mail.to, 'admin@myweli.com');
      expect(mail.subject, 'Salon Awa a modifié son emplacement');
      expect(mail.text, contains('Emplacement : 5.35, -3.99 → 14.69, -17.44'));
      expect(
        mail.text,
        contains('https://admin.myweli.com/#/admin/providers/${s.id}'),
      );
      expect(await w.statusOf(s.id), 'active');
    });

    test('address AND phone in one save → ONE e-mail naming both', () async {
      final s = await validated();
      await catalog().updateProfile(s.ownerId, s.id, {
        'address': 'Avenue Bourguiba, Dakar',
        'phoneNumber': '+221770000000',
      });
      final mail = w.adminMail.sent.single;
      expect(mail.subject, 'Salon Awa a modifié son adresse et son téléphone');
      expect(
        mail.text,
        contains('Adresse : Rue des Jardins → Avenue Bourguiba, Dakar'),
      );
      expect(mail.text, contains('Téléphone : +2250700000009 → +221770000000'));
    });

    test('a new COMMUNE (by area) → « son adresse », the old and new '
        'commune and city', () async {
      final s = await validated();
      await catalog().updateProfile(s.ownerId, s.id, {'areaId': 'plateau'});
      final mail = w.adminMail.sent.single;
      expect(mail.subject, 'Salon Awa a modifié son adresse');
      expect(mail.text, contains('Commune : Cocody, Abidjan → Plateau'));
    });

    test('a save that changes none of them → no e-mail (the name, the '
        'description, the same pin again)', () async {
      final s = await validated();
      await catalog().updateProfile(s.ownerId, s.id, {
        'name': 'Salon Awa & Fils',
        'description': 'Nouveau texte.',
        'latitude': 5.35,
        'longitude': -3.99,
        'address': 'Rue des Jardins',
      });
      expect(w.adminMail.sent, isEmpty);

      // A pin stored as integers and sent again as doubles is the same pin.
      await w.providers.updateProfile(s.id, {'latitude': 5, 'longitude': -4});
      await catalog().updateProfile(s.ownerId, s.id, {
        'latitude': 5.0,
        'longitude': -4.0,
      });
      expect(w.adminMail.sent, isEmpty);
    });

    test('an UNVALIDATED salon (never asked, or pending) moving its pin → '
        'no e-mail', () async {
      final never = await w.salon();
      await catalog().updateProfile(never.ownerId, never.id, {
        'latitude': 14.69,
        'longitude': -17.44,
      });
      final pending = await w.salon();
      await w.provisioning.publish(pending.id);
      w.adminMail.sent.clear();
      await catalog().updateProfile(pending.ownerId, pending.id, {
        'latitude': 14.69,
        'longitude': -17.44,
      });
      expect(w.adminMail.sent, isEmpty);
    });

    test('a failed e-mail never fails the save', () async {
      final s = await validated();
      w.adminMail.explode = true;
      final r = await catalog().updateProfile(s.ownerId, s.id, {
        'phoneNumber': '+221770000000',
      });
      expect(r.ok, isTrue);
      expect((await w.providers.byId(s.id))!['phoneNumber'], '+221770000000');
      expect(w.adminLogs.last, contains('outcome=failed'));
    });

    test('values typed by the salon are ESCAPED in the HTML (T73)', () async {
      final s = await validated();
      await catalog().updateProfile(s.ownerId, s.id, {
        'address': '<img src=x onerror=alert(1)>',
      });
      final mail = w.adminMail.sent.single;
      expect(mail.html, isNot(contains('<img src=x')));
      expect(mail.html, contains('&lt;img src=x onerror=alert(1)&gt;'));
    });
  });

  group('AdminNotifier', () {
    test(
      'an address that is no address (or unset) → no-op, said in the log',
      () async {
        for (final raw in [null, '', 'not-an-address']) {
          final logs = <String>[];
          await AdminNotifier(
            w.adminMail,
            adminEmail: raw,
            log: logs.add,
          ).newSalonRequest(providerId: 'p1', salonName: 'Salon');
          expect(logs.single, contains('outcome=skipped'));
        }
        expect(w.adminMail.sent, isEmpty);
      },
    );
  });
}
