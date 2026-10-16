import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/provider_session.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

import '../support/rejoin.dart';

/// The salon a service acts in is the salon the app acts in: every service
/// that picks its salon from the session resolves it by the SAME rule as
/// ProAuthProvider.activeSalonId — the switched-to salon, else the account's
/// own salon, else the membership's. Design:
/// docs/design/services-acting-salon.md.
void main() {
  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    ProSalonScope.clear();
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
    await serviceLocator.authService.logoutProvider();
  });

  Future<ProAuthProvider> signIn(String email) async {
    final auth = ProAuthProvider();
    await auth.ready;
    await auth.requestEmailOtp(email);
    final ok = await auth.verifyEmailOtp(email, auth.emailDevCode!);
    expect(ok, isTrue, reason: 'login as $email failed');
    // loadMySalons runs unawaited post-login — let it land.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return auth;
  }

  Future<Set<String>> rosterSalons() async {
    final res = await MockProTeamService().getMembers();
    expect(res.success, isTrue, reason: res.error);
    return res.data!.map((m) => m.providerId).toSet();
  }

  group('the one rule', () {
    test('selection → the account\'s own salon → the membership\'s; an '
        'empty id names no salon', () {
      String? r(String? s, String? l, String? m) =>
          resolveActingSalonId(selected: s, linked: l, membership: m);
      expect(r('p2', 'p1', 'p3'), 'p2', reason: 'a switch wins');
      expect(r(null, 'p1', 'p3'), 'p1', reason: 'an owner\'s default');
      expect(r(null, null, 'p3'), 'p3', reason: 'a bare member');
      expect(r(null, null, null), isNull, reason: 'no salon anywhere');
      // ProMembership.fromJson reads a missing salonId as '' — never a
      // path segment (`/providers//services/…`).
      expect(r('', '', 'p3'), 'p3');
      expect(r(null, null, ''), isNull);
    });

    test('ProAuthProvider.activeSalonId and the persisted session agree — '
        'owner, switched owner, bare member', () async {
      // The session the API services read is the one ProAuthProvider holds:
      // same account, same membership, same selection.
      void agree(ProAuthProvider auth, String expected) {
        final session = ProviderSession(
          token: 't',
          provider: auth.provider!,
          membership: auth.membership,
          selectedSalonId: auth.selectedSalonId,
        );
        expect(auth.activeSalonId, expected);
        expect(session.actingSalonId, expected);
        // …and through the wire format the session store keeps.
        expect(
          ProviderSession.fromJson(
            jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>,
          ).actingSalonId,
          expected,
        );
      }

      final owner = await signIn('jean@salon-excellence.test');
      agree(owner, 'provider1');
      expect(await owner.switchSalon('provider2'), isTrue);
      agree(owner, 'provider2');
      await owner.logout();

      activateMember('mem_ancien');
      agree(await signIn('ancien.membre@myweli.test'), 'provider2');
    });

    // The API services take a salon either as an argument (from
    // activeSalonId) or from ProviderSession.actingSalonId — never by
    // reading an account's `.providerId` themselves, which is how the artist
    // edits kept PATCHing the default salon after a switch.
    test('no API service reads `.providerId` to pick its own salon', () {
      final reads = <String>[];
      for (final f in Directory('lib/services/api').listSync()) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].replaceFirst(RegExp(r'//.*'), '');
          if (RegExp(r'\.providerId\b').hasMatch(code)) {
            reads.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        reads,
        isEmpty,
        reason:
            'Resolve the acting salon with ProviderSession.actingSalonId '
            '(the rule ProAuthProvider.activeSalonId uses). If this read is '
            'another model\'s salon id (a booking\'s), narrow this pin.',
      );
    });
  });

  group('the mock team service lists the acting salon\'s roster', () {
    test('a bare member of Beauté Divine sees Beauté Divine\'s roster, '
        'not the seeded salon\'s', () async {
      // Ancien's revived invitation, accepted from anywhere: an ACTIVE
      // Réception row in provider2 and no salon of her own.
      activateMember('mem_ancien');
      final auth = await signIn('ancien.membre@myweli.test');
      expect(auth.provider!.providerId, isNull, reason: 'a bare account');
      expect(auth.activeSalonId, 'provider2');

      expect(await rosterSalons(), {'provider2'});
    });

    // Already held before the shared rule (the selection came first);
    // kept so it cannot regress.
    test('an owner switched to their second salon sees that salon\'s '
        'roster', () async {
      final auth = await signIn('jean@salon-excellence.test');
      expect(await rosterSalons(), {'provider1'});
      expect(await auth.switchSalon('provider2'), isTrue);
      expect(await rosterSalons(), {'provider2'});
    });
  });
}
