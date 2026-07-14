import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
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
    return (sent: tokens.length, invalidTokens: const <String>[]);
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
    var m = await members.invite(
      providerId: 'p1',
      email: email,
      role: role,
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
      artistId: artistId,
    );
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
    expect(s.data['route'], '/pro/appointment/a1');

    final rows = await feed.listForUser('acc-owner');
    expect(rows.single['type'], 'general');
    expect(rows.single['route'], '/pro/appointment/a1');
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
