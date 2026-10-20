import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/messaging/salon_notifier.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/push/push_provider.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:test/test.dart';

class _MockProviders extends Mock implements ProvidersRepository {}

/// Captures every provider send so the tests can assert recipients + payload
/// (the tokens identify the account — one token per account is seeded).
class _RecordingPushProvider implements PushProvider {
  final sends =
      <
        ({
          List<String> tokens,
          String title,
          String body,
          Map<String, String> data,
        })
      >[];

  @override
  Future<PushSendResult> send({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    sends.add((tokens: tokens, title: title, body: body, data: data));
    return (sent: tokens.length, invalidTokens: const <String>[], error: null);
  }
}

/// The provider-directed booking events (design:
/// docs/design/push-notifications-fcm.md §10): capability-scoped recipients,
/// per-account push-pref gating, feed-always, salon wall-clock copy.
void main() {
  late InMemoryMembershipRepository members;
  late InMemoryDeviceTokenRepository tokens;
  late _RecordingPushProvider pushes;
  late InMemoryNotificationsRepository feed;
  late InMemoryNotificationPrefsRepository prefs;
  late _MockProviders providers;
  late SalonNotifier notifier;

  setUp(() async {
    members = InMemoryMembershipRepository();
    tokens = InMemoryDeviceTokenRepository();
    pushes = _RecordingPushProvider();
    feed = InMemoryNotificationsRepository();
    prefs = InMemoryNotificationPrefsRepository();
    providers = _MockProviders();
    when(() => providers.byId(any())).thenAnswer(
      (_) async => {'name': 'Beauté Divine', 'timezone': 'Africa/Abidjan'},
    );
    notifier = SalonNotifier(
      members,
      PushService(pushes, tokens),
      feed,
      prefs,
      providers,
      email: LogEmailProvider(),
    );
  });

  Future<void> registerDevice(String accountId) => tokens.upsert(
    token: 'tok-$accountId',
    userId: accountId,
    role: 'provider',
    platform: 'android',
  );

  /// Seeds a membership through the repo's real lifecycle API and registers
  /// one device per linked account (the token names the account, so the
  /// recording provider's `tokens` identify the recipients).
  Future<Member> seed({
    required String role,
    String? accountId,
    String status = 'active',
    String? artistId,
  }) async {
    final email =
        '${accountId ?? role}-${DateTime.now().microsecondsSinceEpoch}@salon.test';
    if (role == 'owner') {
      final m = await members.ensureOwner(
        providerId: 'p1',
        accountId: accountId!,
        email: email,
      );
      await registerDevice(accountId);
      if (status == 'revoked') await members.revoke(m.id);
      return m;
    }
    var m = (await members.invite(
      providerId: 'p1',
      email: email,
      role: role,
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
      artistId: artistId,
    ))!;
    if (status == 'invited') return m; // pending — no account link
    m = (await members.activate(m.id, accountId!))!;
    await registerDevice(accountId);
    if (status == 'revoked') m = (await members.revoke(m.id))!;
    return m;
  }

  Map<String, dynamic> appointment({String? artistId}) => {
    'id': 'a1',
    'providerId': 'p1',
    'userId': 'u1',
    'appointmentDate': '2026-06-28T14:30:00.000Z',
    if (artistId != null) 'artistId': artistId,
  };

  test('view-all roles (owner/manager/reception) get every event; the feed '
      'row rides along with the pro deep-link route', () async {
    await seed(role: 'owner', accountId: 'acc-owner');
    await seed(role: 'manager', accountId: 'acc-mgr');
    await seed(role: 'reception', accountId: 'acc-rec');

    await notifier.notify(appointment(), SalonEvent.newBooking);

    expect(pushes.sends, hasLength(3));
    final tokensPushed = pushes.sends.expand((s) => s.tokens).toSet();
    expect(tokensPushed, {'tok-acc-owner', 'tok-acc-mgr', 'tok-acc-rec'});
    final s = pushes.sends.first;
    expect(s.title, 'Nouvelle réservation');
    expect(s.data['event'], 'new_booking');
    expect(s.data['appointmentId'], 'a1');
    expect(s.data['providerId'], 'p1');
    // The route carries the salon: the pro app switches to it before opening
    // the booking (a multi-salon owner may be on another one).
    expect(s.data['route'], '/pro/appointment/a1?salon=p1');

    final rows = await feed.listForUser('acc-owner');
    expect(rows.single['type'], 'general');
    // The FEED row has no `providerId` field of its own — the salon rides in
    // the route, so a tap from the notification center switches too.
    expect(rows.single['route'], '/pro/appointment/a1?salon=p1');
  });

  test('own-scope staff: notified ONLY for their own artist’s bookings; an '
      'unassigned booking reaches view-all members only', () async {
    await seed(role: 'owner', accountId: 'acc-owner');
    await seed(role: 'staff', accountId: 'acc-staff', artistId: 'ar1');

    await notifier.notify(appointment(artistId: 'ar1'), SalonEvent.newBooking);
    expect(pushes.sends.expand((s) => s.tokens).toSet(), {
      'tok-acc-owner',
      'tok-acc-staff',
    });

    pushes.sends.clear();
    await notifier.notify(
      appointment(artistId: 'ar2'), // another chair
      SalonEvent.newBooking,
    );
    expect(pushes.sends.expand((s) => s.tokens).toSet(), {'tok-acc-owner'});

    pushes.sends.clear();
    await notifier.notify(appointment(), SalonEvent.newBooking); // unassigned
    expect(pushes.sends.expand((s) => s.tokens).toSet(), {'tok-acc-owner'});
  });

  test(
    'invited / revoked members (and unlinked accounts) are skipped',
    () async {
      await seed(role: 'owner', accountId: 'acc-owner');
      await seed(role: 'manager', accountId: 'acc-gone', status: 'revoked');
      await seed(role: 'manager', status: 'invited'); // pending, no account

      await notifier.notify(appointment(), SalonEvent.clientCancelled);

      expect(pushes.sends.expand((s) => s.tokens).toSet(), {'tok-acc-owner'});
      expect(await feed.listForUser('acc-gone'), isEmpty);
    },
  );

  test(
    'push preference off → NO push, feed row still written (passive log)',
    () async {
      await seed(role: 'owner', accountId: 'acc-owner');
      await prefs.update('acc-owner', push: false);

      await notifier.notify(appointment(), SalonEvent.depositSubmitted);

      expect(pushes.sends, isEmpty);
      final rows = await feed.listForUser('acc-owner');
      expect(rows.single['type'], 'depositReceived');
      expect(rows.single['title'], 'Justificatif d’acompte reçu');
    },
  );

  test(
    'bodies render the SALON wall-clock (multi-pays §3), no client PII',
    () async {
      when(() => providers.byId('p1')).thenAnswer(
        (_) async => {
          'name': 'Institut Libreville',
          'timezone': 'Africa/Libreville', // UTC+1
        },
      );
      await seed(role: 'owner', accountId: 'acc-owner');

      await notifier.notify(appointment(), SalonEvent.clientCancelled);

      final body = pushes.sends.single.body;
      expect(body, contains('15:30')); // 14:30Z = 15:30 Libreville
      expect(body, contains('28/06/2026'));
      expect(body, isNot(contains('u1'))); // no client identifiers
      expect(pushes.sends.single.title, 'Réservation annulée');
    },
  );

  group('clientRescheduled (spec salon-client-reschedule-notify §3.1)', () {
    test('title N1; body N2 says which slot frees up and where it moved, '
        'in the SALON wall-clock; the reschedule feed type', () async {
      when(() => providers.byId('p1')).thenAnswer(
        (_) async => {
          'name': 'Institut Libreville',
          'timezone': 'Africa/Libreville', // UTC+1
        },
      );
      await seed(role: 'owner', accountId: 'acc-owner');

      await notifier.notify(
        appointment(), // moved TO 2026-06-28T14:30Z
        SalonEvent.clientRescheduled,
        previousAppointmentDate: '2026-06-27T09:00:00.000Z',
      );

      final s = pushes.sends.single;
      expect(s.title, 'Réservation reportée');
      expect(
        s.body,
        'Le client a reporté le rendez-vous du 27/06/2026 à 10:00 '
        'au 28/06/2026 à 15:30.',
      );
      expect(s.body, isNot(contains('u1'))); // no client identifiers (T58)
      expect(s.data['event'], 'client_rescheduled');
      expect(s.data['route'], '/pro/appointment/a1?salon=p1');

      final row = (await feed.listForUser('acc-owner')).single;
      expect(row['type'], 'reschedule');
      expect(row['title'], 'Réservation reportée');
      expect(row['body'], s.body);
    });

    test('no readable old date → the new one alone; no new date → the '
        'event alone', () async {
      await seed(role: 'owner', accountId: 'acc-owner');

      await notifier.notify(appointment(), SalonEvent.clientRescheduled);
      await notifier.notify(
        appointment(),
        SalonEvent.clientRescheduled,
        previousAppointmentDate: 'not a date',
      );
      await notifier.notify(
        {'id': 'a2', 'providerId': 'p1', 'userId': 'u1'},
        SalonEvent.clientRescheduled,
        previousAppointmentDate: '2026-06-27T09:00:00.000Z',
      );

      expect(pushes.sends.map((s) => s.body), [
        'Le client a reporté le rendez-vous au 28/06/2026 à 14:30.',
        'Le client a reporté le rendez-vous au 28/06/2026 à 14:30.',
        'Le client a reporté un rendez-vous.',
      ]);
    });

    test('the recipient rule is the one rule: the artist’s own Collaborateur '
        'yes, another chair’s no', () async {
      await seed(role: 'owner', accountId: 'acc-owner');
      await seed(role: 'staff', accountId: 'acc-ar1', artistId: 'ar1');
      await seed(role: 'staff', accountId: 'acc-ar2', artistId: 'ar2');

      await notifier.notify(
        appointment(artistId: 'ar1'),
        SalonEvent.clientRescheduled,
        previousAppointmentDate: '2026-06-27T09:00:00.000Z',
      );

      expect(pushes.sends.expand((s) => s.tokens).toSet(), {
        'tok-acc-owner',
        'tok-acc-ar1',
      });
    });
  });

  test(
    'null appointment / missing providerId / repo failure → silent no-op',
    () async {
      await seed(role: 'owner', accountId: 'acc-owner');

      await notifier.notify(null, SalonEvent.newBooking);
      await notifier.notify({'id': 'a9'}, SalonEvent.newBooking);
      expect(pushes.sends, isEmpty);

      when(() => providers.byId(any())).thenThrow(StateError('db down'));
      // Must not throw into the caller.
      await notifier.notify(appointment(), SalonEvent.newBooking);
    },
  );
}
