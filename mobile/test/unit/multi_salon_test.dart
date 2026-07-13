import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_access_guard.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/provider_session.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/salon_membership_info.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

/// Team access R6b — multi-salons in the app: the models, the mock world
/// (« Mes salons », selection, « Ajouter un salon » gates), the
/// ProAuthProvider switch/fallback/persistence plumbing, and the
/// ProSalonScope reset sweep. Design:
/// docs/design/team-access-r6-multi-salons.md §6.
class _ResetSpy implements SalonScoped {
  int resets = 0;
  @override
  void resetForSalonSwitch() => resets++;
}

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
    // Fresh per-salon offer state each test (SETUP everywhere).
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
    await serviceLocator.authService.logoutProvider();
  });

  Future<ProAuthProvider> signInOwner() async {
    final auth = ProAuthProvider();
    await auth.requestEmailOtp('jean@salon-excellence.test');
    final ok = await auth.verifyEmailOtp(
      'jean@salon-excellence.test',
      auth.emailDevCode!,
    );
    expect(ok, isTrue, reason: 'owner login failed');
    // loadMySalons runs unawaited post-login — let it land.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return auth;
  }

  group('models', () {
    test('SalonMembershipInfo + MySalonsResult round-trip', () {
      final info = SalonMembershipInfo.fromJson(const {
        'salonId': 'p2',
        'salonName': 'Beauté Divine',
        'role': 'owner',
        'salonStatus': 'draft',
        'verified': true,
        'imageUrl': 'https://cdn/x.jpg',
      });
      expect(info.role, TeamRole.owner);
      expect(info.isDraft, isTrue);
      expect(SalonMembershipInfo.fromJson(info.toJson()), info);

      final result = MySalonsResult.fromJson({
        'items': [info.toJson()],
        'canAddSalon': true,
      });
      expect(result.items.single, info);
      expect(result.canAddSalon, isTrue);
    });

    test('unknown role falls back to the MINIMAL staff shape', () {
      expect(teamRoleFrom('superuser'), TeamRole.staff);
      expect(teamRoleFrom(null), TeamRole.staff);
    });

    test('ProviderSession round-trips the R6 selection; legacy JSON parses',
        () {
      final user = ProviderUser(
        id: 'acc1',
        phoneNumber: '',
        businessName: '',
        businessType: BusinessType.other,
        email: 'x@y.test',
        createdAt: DateTime(2026),
      );
      final session = ProviderSession(
        token: 't',
        refreshToken: 'r',
        provider: user,
        selectedSalonId: 'p2',
      );
      final back = ProviderSession.fromJson(session.toJson());
      expect(back.selectedSalonId, 'p2');
      // copyWith keeps, replaces and clears.
      expect(back.copyWith().selectedSalonId, 'p2');
      expect(back.copyWith(selectedSalonId: 'p9').selectedSalonId, 'p9');
      expect(
        back.copyWith(clearSelectedSalon: true).selectedSalonId,
        isNull,
      );
      // Legacy (pre-R6) sessions simply have no selection.
      final legacy = ProviderSession.fromJson({
        'token': 't',
        'provider': user.toJson(),
      });
      expect(legacy.selectedSalonId, isNull);
    });
  });

  group('« Mes salons » (mock world)', () {
    test('the seeded owner sees BOTH salons, owned first, no add gate yet',
        () async {
      final auth = await signInOwner();
      expect(auth.salons.map((s) => s.salonId), ['provider2', 'provider1']);
      expect(auth.salons.every((s) => s.isOwner), isTrue);
      expect(auth.hasMultipleSalons, isTrue);
      // No offer anywhere → the server-computed gate stays closed.
      expect(auth.canAddSalon, isFalse);
    });

    test('switchSalon: reshapes, persists, resets the per-salon fleet',
        () async {
      final auth = await signInOwner();
      expect(auth.activeSalonId, 'provider1');
      final spy = ProSalonScope.track(_ResetSpy());

      final ok = await auth.switchSalon('provider2');
      expect(ok, isTrue);
      expect(auth.activeSalonId, 'provider2');
      expect(auth.salonName, 'Beauté Divine');
      expect(auth.membership!.role, TeamRole.owner);
      expect(spy.resets, 1);
      expect(
        await serviceLocator.authService.getSelectedProviderSalon(),
        'provider2',
      );
    });

    test(
        'switchSalon refetches the salon MARKET facts — timezone + currency '
        '(multi-pays MP2)', () async {
      // Move provider2 to Gabon for this test only (the committed seeds stay
      // CI — demo realism); restore after.
      final i = MockData.providers.indexWhere((p) => p.id == 'provider2');
      final original = MockData.providers[i];
      MockData.providers[i] = original.copyWith(
        countryCode: 'GA',
        timezone: 'Africa/Libreville',
        currency: 'XAF',
      );
      addTearDown(() => MockData.providers[i] = original);

      final auth = await signInOwner();
      expect(auth.salonTimezone, kSalonTz);
      expect(auth.salonCurrency, 'XOF');

      expect(await auth.switchSalon('provider2'), isTrue);
      expect(auth.salonTimezone, 'Africa/Libreville');
      expect(auth.salonCurrency, 'XAF');
      expect(auth.salonCountryCode, 'GA');

      expect(await auth.switchSalon('provider1'), isTrue);
      expect(auth.salonTimezone, kSalonTz);
      expect(auth.salonCurrency, 'XOF');
    });

    test('cold start restores the switched-to salon', () async {
      final auth = await signInOwner();
      await auth.switchSalon('provider2');

      // A new provider instance = the app restarting on the same session.
      final restarted = ProAuthProvider();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(restarted.activeSalonId, 'provider2');
      expect(restarted.salonName, 'Beauté Divine');
    });

    test(
        'a salon the account does NOT belong to is refused; the session '
        'stays put', () async {
      final auth = await signInOwner();
      final ok = await auth.switchSalon('provider3');
      expect(ok, isFalse);
      expect(auth.activeSalonId, 'provider1');
      expect(auth.isAuthenticated, isTrue);
    });

    test(
        'revoked from the SELECTED salon → silent fallback to the default '
        '(never a sign-out)', () async {
      final auth = await signInOwner();
      await auth.switchSalon('provider2');
      expect(auth.activeSalonId, 'provider2');

      // The provider2 ownership disappears mid-session.
      MockData.teamMembers.removeWhere((m) => m.id == 'mem_owner2');

      ProAccessGuard.report('forbidden');
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(auth.isAuthenticated, isTrue);
      expect(auth.activeSalonId, 'provider1');
      expect(auth.consumeRevokedNotice(), isNull);
    });

    test('logout clears the selection', () async {
      final auth = await signInOwner();
      await auth.switchSalon('provider2');
      await auth.logout();
      expect(auth.selectedSalonId, isNull);
      expect(auth.salons, isEmpty);
      expect(
        await serviceLocator.authService.getSelectedProviderSalon(),
        isNull,
      );
    });
  });

  group('« Ajouter un salon » (mock world)', () {
    test('gated on a live Réseau offer → reseau_required first', () async {
      final auth = await signInOwner();
      final created = await auth.addSalon(
        businessName: 'Salon Trois',
        businessType: BusinessType.salon,
      );
      expect(created, isNull);
      expect(auth.errorCode, 'reseau_required');
    });

    test('with Réseau live: creates the draft, switches to it, lists it',
        () async {
      final auth = await signInOwner();
      final chosen = await serviceLocator.subscriptionService
          .chooseOffer('provider1', SalonTier.reseau);
      expect(chosen.success, isTrue);

      final created = await auth.addSalon(
        businessName: 'Salon Trois',
        businessType: BusinessType.spa,
      );
      expect(created, isNotNull);
      expect(created!.salonStatus, 'draft');
      expect(created.role, TeamRole.owner);
      // Switched to the new salon; the list carries all three.
      expect(auth.activeSalonId, created.salonId);
      expect(auth.salons.length, 3);
      // Its own SETUP state: no offer on the new salon yet.
      final offer = await serviceLocator.subscriptionService
          .getSalonSubscription(created.salonId);
      expect(offer.code, 'no_offer');
    });

    test('per-salon trials: salon 2 gets a FRESH trial after salon 1 chose',
        () async {
      final subs = serviceLocator.subscriptionService;
      await subs.chooseOffer('provider1', SalonTier.pro);
      final second = await subs.chooseOffer('provider2', SalonTier.business);
      expect(second.success, isTrue);
      expect(second.data!.status, SalonOfferStatus.trial);
    });
  });

  group('the sweep pin', () {
    test('no screen reads provider?.providerId anymore (activeSalonId only)',
        () {
      final offenders = <String>[];
      for (final entity in Directory('lib/screens').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (content.contains('provider?.providerId') ||
            content.contains('provider!.providerId')) {
          offenders.add(entity.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'screens must resolve the salon via activeSalonId (R6): '
            '$offenders',
      );
    });
  });
}
