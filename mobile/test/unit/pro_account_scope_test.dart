import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/account_scope.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

/// The mock, with a sign-out the test can hold or break.
class _Auth extends MockAuthService {
  Completer<void>? holdLogout;
  bool breakLogout = false;

  @override
  Future<void> logoutProvider() async {
    final hold = holdLogout;
    if (hold != null) await hold.future;
    if (breakLogout) throw StateError('keychain');
    return super.logoutProvider();
  }
}

class _SalonStore extends ChangeNotifier implements SalonScoped {
  int resets = 0;
  @override
  void resetForSalonSwitch() {
    resets++;
    notifyListeners();
  }
}

class _Throwing implements SalonScoped {
  @override
  void resetForSalonSwitch() => throw StateError('boom');
}

class _AccountStore extends ChangeNotifier implements AccountScoped {
  int resets = 0;
  @override
  void resetForAccountChange() {
    resets++;
    notifyListeners();
  }
}

/// docs/design/pro-account-scope.md §2.1, §2.3 — every way into and out of a
/// Pro account resets what the previous one left, and a session the server
/// refused is a way out.
void main() {
  late _Auth auth;
  late _SalonStore salon;
  late _AccountStore account;

  setUpAll(() {
    auth = _Auth();
    serviceLocator
      ..authService = auth
      ..proService = MockProService()
      ..subscriptionService = MockSubscriptionService()
      ..proPushRegistration = PushRegistration(
        push: MockPushNotificationService(),
        devices: MockDeviceRegistrationService(),
      );
  });

  setUp(() async {
    MockData.resetTeam();
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
    auth
      ..holdLogout = null
      ..breakLogout = false;
    await auth.logoutProvider();
    ProSalonScope.clear();
    AccountScope.clear();
    salon = ProSalonScope.track(_SalonStore());
    account = AccountScope.track(_AccountStore());
    ProRouter.router.go('/pro/splash');
  });

  String location() => ProRouter.router.routeInformationProvider.value.uri.path;

  Future<ProAuthProvider> signedInAs(String email) async {
    final pro = ProAuthProvider();
    await pro.ready;
    await pro.requestEmailOtp(email);
    expect(
      await pro.verifyEmailOtp(email, MockAuthService.demoOtp),
      isTrue,
      reason: 'the scenario: $email signs in',
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return pro;
  }

  test('a sign-in resets the salon stores AND the account stores', () async {
    final pro = ProAuthProvider();
    await pro.ready;
    final before = (salon.resets, account.resets);

    await pro.requestEmailOtp('jean@salon-excellence.test');
    await pro.verifyEmailOtp(
      'jean@salon-excellence.test',
      MockAuthService.demoOtp,
    );

    expect(salon.resets, greaterThan(before.$1));
    expect(account.resets, before.$2 + 1);
  });

  test(
    'a salon store that throws stops neither the others nor the sign-out',
    () async {
      final pro = await signedInAs('jean@salon-excellence.test');
      ProSalonScope.track(_Throwing());
      final after = ProSalonScope.track(_SalonStore());
      final before = account.resets;

      await pro.logout();

      expect(pro.isAuthenticated, isFalse);
      expect(after.resets, 1);
      expect(account.resets, before + 1);
    },
  );

  // The other two ways in: a registration (`_login`) and an invitation
  // accepted from the sign-in's « Invitations » step.
  test('a registration resets both', () async {
    final pro = ProAuthProvider();
    await pro.ready;
    final before = (salon.resets, account.resets);
    const email = 'nouveau.salon@myweli.test';
    await pro.requestEmailOtp(email);

    expect(
      await pro.registerWithEmail(
        email: email,
        code: MockAuthService.demoOtp,
        phoneNumber: '+2250700000077',
        businessName: 'Salon Nouveau',
        businessType: BusinessType.salon,
      ),
      isTrue,
      reason: 'the scenario: registered',
    );

    expect(salon.resets, greaterThan(before.$1));
    expect(account.resets, before.$2 + 1);
  });

  test('an invitation accepted from the sign-in resets both', () async {
    final pro = ProAuthProvider();
    await pro.ready;
    await pro.requestEmailOtp('invitee@myweli.test');
    await pro.verifyEmailOtp('invitee@myweli.test', MockAuthService.demoOtp);
    expect(pro.hasPendingInvitations, isTrue, reason: 'the scenario');
    final before = (salon.resets, account.resets);

    expect(
      await pro.acceptPendingInvitation(pro.pendingInvitations.single.id),
      isTrue,
    );

    expect(salon.resets, greaterThan(before.$1));
    expect(account.resets, before.$2 + 1);
  });

  test('« Déconnexion » resets both', () async {
    final pro = await signedInAs('jean@salon-excellence.test');
    final before = (salon.resets, account.resets);

    await pro.logout();

    expect(pro.isAuthenticated, isFalse);
    expect(salon.resets, before.$1 + 1);
    expect(account.resets, before.$2 + 1);
  });

  test('a sign-out that failed keeps the account and its data', () async {
    final pro = await signedInAs('jean@salon-excellence.test');
    final before = (salon.resets, account.resets);
    auth.breakLogout = true;

    await pro.logout();

    expect(pro.isAuthenticated, isTrue);
    expect((salon.resets, account.resets), before);
  });

  // The bell is the ACCOUNT's (main_pro.dart): a multi-salon owner's switch
  // must not empty it — only another account does.
  test(
    'a salon switch resets the salon stores, not the account ones',
    () async {
      final pro = await signedInAs('jean@salon-excellence.test');
      final before = (salon.resets, account.resets);

      expect(
        await pro.switchSalon('provider2'),
        isTrue,
        reason: 'the scenario',
      );

      expect(salon.resets, greaterThan(before.$1));
      expect(account.resets, before.$2);
    },
  );

  test('the same account, its membership refreshed, resets nothing', () async {
    final pro = await signedInAs('jean@salon-excellence.test');
    final before = (salon.resets, account.resets);

    await pro.refreshMembership();

    expect((salon.resets, account.resets), before);
  });

  // §2.1: no frame sees the receptionist with the owner's figures.
  test('both are reset BEFORE the sign-out is announced', () async {
    final pro = await signedInAs('jean@salon-excellence.test');
    final before = (salon.resets, account.resets);
    final heard = <(bool, int, int)>[];
    pro.addListener(
      () => heard.add((pro.isAuthenticated, salon.resets, account.resets)),
    );

    await pro.logout();

    final out = heard.where((h) => !h.$1);
    expect(out, isNotEmpty);
    for (final h in out) {
      expect((h.$2, h.$3), (before.$1 + 1, before.$2 + 1));
    }
  });

  group('the Pro session refused by the server (§2.3, Q2 = a)', () {
    test(
      'ends the account: both resets, the sign-in, the sentence once',
      () async {
        final pro = await signedInAs('jean@salon-excellence.test');
        ProRouter.router.go('/pro/dashboard');
        final before = (salon.resets, account.resets);

        await auth.expireProviderSession();
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(pro.isAuthenticated, isFalse);
        expect(salon.resets, greaterThan(before.$1));
        expect(account.resets, greaterThan(before.$2));
        expect(location(), '/pro/login');
        expect(pro.consumeSessionEndedNotice(), isTrue);
        expect(pro.consumeSessionEndedNotice(), isFalse, reason: 'once');
      },
    );

    test('signed out already: nothing', () async {
      final pro = ProAuthProvider();
      await pro.ready;
      final before = (salon.resets, account.resets);

      await auth.expireProviderSession();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect((salon.resets, account.resets), before);
      expect(pro.consumeSessionEndedNotice(), isFalse);
    });

    test('heard during a « Déconnexion »: one way out, no sentence', () async {
      final pro = await signedInAs('jean@salon-excellence.test');
      final hold = Completer<void>();
      auth.holdLogout = hold;

      final out = pro.logout();
      await pumpEventQueue();
      await auth.expireProviderSession();
      await pumpEventQueue();
      hold.complete();
      await out;
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(pro.isAuthenticated, isFalse);
      expect(pro.consumeSessionEndedNotice(), isFalse);
    });

    test('heard during a sign-out that then fails: the account still ends, '
        'and says why', () async {
      final pro = await signedInAs('jean@salon-excellence.test');
      final hold = Completer<void>();
      auth
        ..holdLogout = hold
        ..breakLogout = true;

      final out = pro.logout();
      await pumpEventQueue();
      await auth.expireProviderSession();
      await pumpEventQueue();
      hold.complete();
      await out;
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(pro.isAuthenticated, isFalse);
      expect(location(), '/pro/login');
      expect(pro.consumeSessionEndedNotice(), isTrue);
    });
  });
}
