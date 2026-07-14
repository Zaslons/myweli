import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/push/push_message_handler.dart';

/// The push routing brain (docs/design/push-notifications-app.md): what a
/// tapped notification does — including the two hard cases, a cold-start tap
/// before the session is restored and a pro tap for a salon that isn't the
/// active one (R6).
void main() {
  group('kPushChannelId', () {
    test(
        'equals the backend constant — a drift here silently drops every '
        'background notification into the unnamed default channel', () {
      // backend/lib/src/push/fcm_v1_push_provider.dart:
      //   static const androidChannelId = 'myweli_default';
      expect(kPushChannelId, 'myweli_default');
    });
  });

  group('routeFromPushData', () {
    test('takes an allowlisted route', () {
      expect(
        routeFromPushData(
          {'route': '/appointment/a1'},
          allowedPrefixes: kConsumerRoutePrefixes,
        ),
        '/appointment/a1',
      );
      expect(
        routeFromPushData(
          {'route': '/pro/appointment/a1?salon=p1'},
          allowedPrefixes: kProRoutePrefixes,
        ),
        '/pro/appointment/a1?salon=p1',
      );
    });

    test('drops a route this surface does not own (the allowlist)', () {
      // A pro route offered to the CONSUMER app, and vice-versa.
      expect(
        routeFromPushData(
          {'route': '/pro/appointment/a1'},
          allowedPrefixes: kConsumerRoutePrefixes,
        ),
        isNull,
      );
      expect(
        routeFromPushData(
          {'route': '/appointment/a1'},
          allowedPrefixes: kProRoutePrefixes,
        ),
        isNull,
      );
      // And anything that isn't an in-app path at all.
      expect(
        routeFromPushData(
          {'route': 'https://evil.example/steal'},
          allowedPrefixes: kConsumerRoutePrefixes,
        ),
        isNull,
      );
    });

    test('missing / junk / empty → null', () {
      expect(
        routeFromPushData({}, allowedPrefixes: kConsumerRoutePrefixes),
        isNull,
      );
      expect(
        routeFromPushData(
          {'route': 42},
          allowedPrefixes: kConsumerRoutePrefixes,
        ),
        isNull,
      );
      expect(
        routeFromPushData(
          {'route': '  '},
          allowedPrefixes: kConsumerRoutePrefixes,
        ),
        isNull,
      );
    });
  });

  group('providerIdFromPushData', () {
    test('reads the data key (push) OR the route’s ?salon= (feed row)', () {
      expect(providerIdFromPushData({'providerId': 'p1'}), 'p1');
      expect(
        providerIdFromPushData({'route': '/pro/appointment/a1?salon=p2'}),
        'p2',
      );
      // The explicit key wins.
      expect(
        providerIdFromPushData({
          'providerId': 'p1',
          'route': '/pro/appointment/a1?salon=p2',
        }),
        'p1',
      );
    });

    test('absent / junk → null (a consumer push carries no salon)', () {
      expect(providerIdFromPushData({'route': '/appointment/a1'}), isNull);
      expect(providerIdFromPushData({}), isNull);
      expect(providerIdFromPushData({'providerId': 7}), isNull);
    });
  });

  group('PushMessageHandler.handleData', () {
    late List<String> routes;

    setUp(() => routes = []);

    PushMessageHandler consumer({bool authed = true}) => PushMessageHandler(
          navigate: (r) async => routes.add(r),
          allowedRoutePrefixes: kConsumerRoutePrefixes,
          isAuthenticated: () => authed,
        );

    PushMessageHandler pro({
      required String activeSalon,
      bool switchSucceeds = true,
      List<String>? switched,
      bool authed = true,
    }) =>
        PushMessageHandler(
          navigate: (r) async => routes.add(r),
          allowedRoutePrefixes: kProRoutePrefixes,
          isAuthenticated: () => authed,
          salonSwitchFallbackRoute: '/pro/dashboard',
          ensureSalon: (id) async {
            if (id == activeSalon) return true; // already there
            switched?.add(id);
            return switchSucceeds;
          },
        );

    test('consumer: navigates to the booking', () async {
      await consumer().handleData({
        'template': 'bookingAccepted',
        'appointmentId': 'a1',
        'route': '/appointment/a1',
      });
      expect(routes, ['/appointment/a1']);
    });

    test('pro on the SAME salon: no switch, straight to the booking', () async {
      final switched = <String>[];
      await pro(activeSalon: 'p1', switched: switched).handleData({
        'event': 'new_booking',
        'providerId': 'p1',
        'route': '/pro/appointment/a1?salon=p1',
      });
      expect(switched, isEmpty);
      expect(routes, ['/pro/appointment/a1?salon=p1']);
    });

    test('pro on ANOTHER salon: switches FIRST, then opens the booking (R6)',
        () async {
      final switched = <String>[];
      await pro(activeSalon: 'p1', switched: switched).handleData({
        'event': 'new_booking',
        'providerId': 'p2',
        'route': '/pro/appointment/a9?salon=p2',
      });
      expect(switched, ['p2']); // switched before navigating
      expect(routes, ['/pro/appointment/a9?salon=p2']);
    });

    test(
        'a feed row (no providerId key) still switches — the salon rides in '
        'the route', () async {
      final switched = <String>[];
      await pro(activeSalon: 'p1', switched: switched).handleData({
        'route': '/pro/appointment/a9?salon=p3',
      });
      expect(switched, ['p3']);
      expect(routes, ['/pro/appointment/a9?salon=p3']);
    });

    test(
        'a failed switch lands on the dashboard, never on a booking the '
        'active salon cannot resolve', () async {
      await pro(activeSalon: 'p1', switchSucceeds: false).handleData({
        'providerId': 'p2',
        'route': '/pro/appointment/a9?salon=p2',
      });
      expect(routes, ['/pro/dashboard']);
    });

    test(
        'COLD START: a tap before the session lands is buffered, then '
        'replayed by flushPending() when auth restores', () async {
      // The real shape: ONE handler whose auth predicate flips under it.
      var authed = false;
      final handler = PushMessageHandler(
        navigate: (r) async => routes.add(r),
        allowedRoutePrefixes: kConsumerRoutePrefixes,
        isAuthenticated: () => authed,
      );

      // The tap launched the app — no session yet.
      await handler.handleData({'route': '/appointment/a1'});
      expect(routes, isEmpty);
      expect(handler.hasPending, isTrue);

      // A flush that arrives while still signed out keeps the payload.
      await handler.flushPending();
      expect(routes, isEmpty);
      expect(handler.hasPending, isTrue);

      // The session lands → the auth listener flushes → the deep link opens.
      authed = true;
      await handler.flushPending();
      expect(routes, ['/appointment/a1']);
      expect(handler.hasPending, isFalse);
    });

    test('flushPending() with nothing buffered is a no-op', () async {
      final handler = consumer();
      await handler.flushPending();
      expect(routes, isEmpty);
      expect(handler.hasPending, isFalse);
    });

    test('an unusable payload navigates nowhere and buffers nothing', () async {
      final handler = consumer(authed: false);
      await handler.handleData({'template': 'reminder24h'}); // no route
      expect(routes, isEmpty);
      expect(handler.hasPending, isFalse);
    });
  });
}
