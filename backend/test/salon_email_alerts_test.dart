import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:myweli_backend/src/messaging/salon_notifier.dart';
import 'package:myweli_backend/src/notifications/notification_prefs_repository.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/push/push_provider.dart';
import 'package:myweli_backend/src/push/push_service.dart';
import 'package:myweli_backend/src/salon_time.dart';
import 'package:test/test.dart';

class _MockProviders extends Mock implements ProvidersRepository {}

/// FCM as the notifier sees it: every token accepted, unless [reject].
class _Push implements PushProvider {
  bool reject = false;
  final sentTo = <String>[];

  @override
  Future<PushSendResult> send({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    if (reject) {
      return (sent: 0, invalidTokens: const <String>[], error: 'unavailable');
    }
    sentTo.addAll(tokens);
    return (sent: tokens.length, invalidTokens: const <String>[], error: null);
  }
}

typedef _Mail = ({
  String to,
  String subject,
  String text,
  String? html,
  EmailClass classification,
});

class _Email implements EmailProvider {
  final sent = <_Mail>[];

  /// Addresses whose send fails (`ok: false`), and ones that THROW.
  final failFor = <String>{};
  final throwFor = <String>{};

  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    required EmailClass classification,
    String? html,
  }) async {
    if (throwFor.contains(to)) throw StateError('smtp down');
    if (failFor.contains(to)) {
      return (ok: false, providerMessageId: null, error: 'rejected');
    }
    sent.add((
      to: to,
      subject: subject,
      text: text,
      html: html,
      classification: classification,
    ));
    return (ok: true, providerMessageId: 'm${sent.length}', error: null);
  }
}

/// docs/design/salon-email-alerts.md — when no push from the app reaches a
/// team member, the four salon events arrive by e-mail instead. A salon that
/// only uses the web used to learn nothing with its tab closed.
void main() {
  late InMemoryMembershipRepository members;
  late InMemoryDeviceTokenRepository tokens;
  late _Push push;
  late _Email email;
  late InMemoryNotificationsRepository feed;
  late InMemoryNotificationPrefsRepository prefs;
  late _MockProviders providers;
  late SalonNotifier notifier;

  setUpAll(initSalonTime);

  setUp(() {
    members = InMemoryMembershipRepository();
    tokens = InMemoryDeviceTokenRepository();
    push = _Push();
    email = _Email();
    feed = InMemoryNotificationsRepository();
    prefs = InMemoryNotificationPrefsRepository();
    providers = _MockProviders();
    when(() => providers.byId(any())).thenAnswer(
      (_) async => {'name': 'Beauté Divine', 'timezone': 'Africa/Abidjan'},
    );
    notifier = SalonNotifier(
      members,
      PushService(push, tokens),
      feed,
      prefs,
      providers,
      email: email,
    );
  });

  Future<void> device(String accountId) => tokens.upsert(
    token: 'tok-$accountId',
    userId: accountId,
    role: 'provider',
    platform: 'android',
  );

  Future<Member> owner({bool withApp = false}) async {
    final m = await members.ensureOwner(
      providerId: 'p1',
      accountId: 'acc-owner',
      email: 'owner@salon.test',
    );
    if (withApp) await device('acc-owner');
    return m;
  }

  Future<Member> member(
    String role,
    String accountId, {
    String? artistId,
    bool withApp = false,
  }) async {
    final m = (await members.invite(
      providerId: 'p1',
      email: '$accountId@salon.test',
      role: role,
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
      artistId: artistId,
    ))!;
    final active = (await members.activate(m.id, accountId))!;
    if (withApp) await device(accountId);
    return active;
  }

  // A client's booking — its name and phone must never reach an e-mail.
  Map<String, dynamic> appointment({String? artistId}) => {
    'id': 'a1',
    'providerId': 'p1',
    'userId': 'u1',
    'appointmentDate': '2026-10-21T10:00:00.000Z',
    'clientDisplayName': 'Aminata Koné',
    'clientPhone': '+2250707123456',
    if (artistId != null) 'artistId': artistId,
  };

  group('who gets an e-mail', () {
    test('a member the app reaches gets the push and NO e-mail', () async {
      await owner(withApp: true);
      await notifier.notify(appointment(), SalonEvent.newBooking);
      expect(push.sentTo, ['tok-acc-owner']);
      expect(email.sent, isEmpty);
    });

    test('a member with no device gets the e-mail, at the address of their '
        'membership', () async {
      await owner();
      await notifier.notify(appointment(), SalonEvent.newBooking);
      expect(email.sent.map((m) => m.to), ['owner@salon.test']);
      // A salon, about its own bookings: the budget class that is never
      // starved by anonymous traffic.
      expect(email.sent.single.classification, EmailClass.warm);
    });

    test('« Alertes par e-mail » off → nothing by e-mail', () async {
      await owner();
      await prefs.update('acc-owner', emailAlerts: false);
      await notifier.notify(appointment(), SalonEvent.newBooking);
      expect(email.sent, isEmpty);
    });

    test('push switched off on a device → the e-mail, since no push '
        'reached them', () async {
      await owner(withApp: true);
      await prefs.update('acc-owner', push: false);
      await notifier.notify(appointment(), SalonEvent.newBooking);
      expect(push.sentTo, isEmpty);
      expect(email.sent.map((m) => m.to), ['owner@salon.test']);
    });

    test('FCM accepts nothing → the e-mail', () async {
      await owner(withApp: true);
      push.reject = true;
      await notifier.notify(appointment(), SalonEvent.newBooking);
      expect(email.sent.map((m) => m.to), ['owner@salon.test']);
    });

    test('the recipient rule is the push rule: a Collaborateur only for '
        'THEIR artist', () async {
      await owner(withApp: true);
      await member('staff', 'acc-awa', artistId: 'ar-awa'); // Collaborateur
      await notifier.notify(
        appointment(artistId: 'ar-koffi'),
        SalonEvent.newBooking,
      );
      expect(email.sent, isEmpty);
      await notifier.notify(
        appointment(artistId: 'ar-awa'),
        SalonEvent.newBooking,
      );
      expect(email.sent.map((m) => m.to), ['acc-awa@salon.test']);
    });

    test('a failed or throwing send stops neither the feed nor the next '
        'member', () async {
      await owner();
      await member('manager', 'acc-mgr');
      await member('reception', 'acc-rec');
      email.throwFor.add('owner@salon.test');
      email.failFor.add('acc-mgr@salon.test');
      await notifier.notify(appointment(), SalonEvent.newBooking);
      expect(email.sent.map((m) => m.to), ['acc-rec@salon.test']);
      for (final a in ['acc-owner', 'acc-mgr', 'acc-rec']) {
        expect(await feed.listForUser(a, limit: 10), hasLength(1), reason: a);
      }
    });
  });

  group('what the e-mail says (owner Q1, approved as written)', () {
    const footer =
        'Vous recevez cet e-mail parce qu’aucune notification de l’app '
        'MyWeli Pro ne vous est parvenue. Pour ne plus le recevoir : '
        'Espace Pro → Notifications.';

    test('a new request', () async {
      await owner();
      await notifier.notify(appointment(), SalonEvent.newBooking);
      final m = email.sent.single;
      expect(m.subject, 'Nouvelle demande de réservation — Beauté Divine');
      expect(
        m.text,
        contains(
          'Nouvelle demande de réservation le 21/10/2026 à 10:00. '
          'Acceptez-la ou refusez-la depuis votre Espace Pro.',
        ),
      );
      expect(m.text, contains(footer));
      // The link opens the booking on the web, in ITS salon (`?salon=`).
      const link = 'https://myweli.com/pro/rendez-vous/a1?salon=p1';
      expect(m.text, contains(link));
      expect(m.html, contains('href="$link"'));
      expect(m.html, contains('Voir la demande'));
      expect(m.html, contains('https://myweli.com/pro/notifications'));
    });

    test('a reschedule — the slot it leaves and the one it takes', () async {
      await owner();
      await notifier.notify(
        appointment(),
        SalonEvent.clientRescheduled,
        previousAppointmentDate: '2026-10-20T15:00:00.000Z',
      );
      final m = email.sent.single;
      expect(m.subject, 'Réservation reportée — Beauté Divine');
      expect(
        m.text,
        contains(
          'Le client a reporté le rendez-vous du 20/10/2026 à 15:00 '
          'au 21/10/2026 à 10:00.',
        ),
      );
      expect(m.html, contains('Voir le rendez-vous'));
    });

    test('a cancellation', () async {
      await owner();
      await notifier.notify(appointment(), SalonEvent.clientCancelled);
      final m = email.sent.single;
      expect(m.subject, 'Réservation annulée — Beauté Divine');
      expect(
        m.text,
        contains('Le client a annulé le rendez-vous du 21/10/2026 à 10:00.'),
      );
      expect(m.html, contains('Voir le rendez-vous'));
    });

    test('a deposit screenshot', () async {
      await owner();
      await notifier.notify(appointment(), SalonEvent.depositSubmitted);
      final m = email.sent.single;
      expect(m.subject, 'Justificatif d’acompte reçu — Beauté Divine');
      expect(
        m.text,
        contains(
          'Un justificatif d’acompte a été envoyé pour le rendez-vous du '
          '21/10/2026 à 10:00. Vérifiez-le depuis votre Espace Pro.',
        ),
      );
      expect(m.html, contains('Voir le justificatif'));
    });

    test('the salon’s wall clock, not UTC', () async {
      when(() => providers.byId(any())).thenAnswer(
        (_) async => {'name': 'Salon Paris', 'timezone': 'Europe/Paris'},
      );
      await owner();
      await notifier.notify(appointment(), SalonEvent.newBooking);
      expect(email.sent.single.text, contains('le 21/10/2026 à 12:00.'));
    });

    test('no client name, no phone — anywhere (T25)', () async {
      await owner();
      for (final e in SalonEvent.values) {
        await notifier.notify(appointment(), e);
      }
      expect(email.sent, hasLength(SalonEvent.values.length));
      for (final m in email.sent) {
        for (final part in [m.subject, m.text, m.html ?? '']) {
          expect(part, isNot(contains('Aminata')));
          expect(part, isNot(contains('0707123456')));
        }
      }
    });

    test(
      'the salon’s name is the salon’s to write — escaped in the HTML',
      () async {
        when(() => providers.byId(any())).thenAnswer(
          (_) async => {
            'name': 'Chez <b>Awa</b> & Co',
            'timezone': 'Africa/Abidjan',
          },
        );
        await owner();
        await notifier.notify(appointment(), SalonEvent.newBooking);
        final m = email.sent.single;
        expect(
          m.subject,
          'Nouvelle demande de réservation — Chez <b>Awa</b> & Co',
        );
        expect(m.html, contains('Chez &lt;b&gt;Awa&lt;/b&gt; &amp; Co'));
        expect(m.html, isNot(contains('<b>Awa</b>')));
      },
    );
  });
}
