import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/models/salon_market.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

import '../support/rejoin.dart';

/// The Pro app never guesses its salon (docs/design/pro-app-salon-not-loaded.md).
///
/// A cold start restores the account and the membership from the session, then
/// asks GET /me/provider. The salon — the carrier of its timezone, currency,
/// country and area — used to live only in that answer: when it failed, every
/// salon-time call fell back to Africa/Abidjan, and the journal's
/// « Reprogrammer » wrote an instant an hour off for a salon in Libreville.
///
/// Runs on the MOCK world (owner jean@ of `provider1` + `provider2`), with
/// `provider1` moved to Gabon for the file so a wrong fallback is visible.
const _owner = 'jean@salon-excellence.test';
const _libreville = 'Africa/Libreville';

/// GET /me/provider, steerable: [script] answers the next calls in order, then
/// the mock world answers again.
class _Pro extends MockProService {
  final List<ApiResponse<MyProviderInfo>> script = [];
  bool meFails = false;

  /// The salon answers with no `timezone` — a loaded salon on the server's
  /// own default.
  bool noTimezone = false;
  int calls = 0;

  static ApiResponse<MyProviderInfo> serverError() =>
      ApiResponse.error('Erreur serveur.', code: 'server_error');

  static ApiResponse<MyProviderInfo> forbidden() => ApiResponse.error(
    'Action réservée aux membres du salon.',
    code: 'forbidden',
  );

  void reset() {
    script.clear();
    meFails = false;
    noTimezone = false;
    calls = 0;
  }

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId}) async {
    calls++;
    if (script.isNotEmpty) return script.removeAt(0);
    if (meFails) return serverError();
    final res = await super.getMyProvider(salonId: salonId);
    final info = res.data;
    if (!noTimezone || info == null) return res;
    return ApiResponse.success(
      MyProviderInfo(
        salon: Provider.fromJson({...info.salon.toJson(), 'timezone': null}),
        membership: info.membership,
      ),
    );
  }
}

/// The session store, with a window on the moment the R6 selection is
/// written — where a half-taken shape would show.
class _Auth extends MockAuthService {
  void Function()? onSelect;

  @override
  Future<void> setSelectedProviderSalon(String? salonId) async {
    onSelect?.call();
    return super.setSelectedProviderSalon(salonId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pro = _Pro();
  final auth = _Auth();

  setUpAll(() {
    serviceLocator.authService = auth;
    serviceLocator.proService = pro;
    serviceLocator.proTeamService = MockProTeamService();
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  late int gabon;
  setUp(() async {
    MockData.resetTeam();
    pro.reset();
    auth.onSelect = null;
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
    await auth.logoutProvider();
    ProRouter.router.go('/pro/splash');
    gabon = MockData.providers.indexWhere((p) => p.id == 'provider1');
    final original = MockData.providers[gabon];
    MockData.providers[gabon] = original.copyWith(
      countryCode: 'GA',
      timezone: _libreville,
      currency: 'XAF',
      areaId: 'ga-libreville',
    );
    addTearDown(() => MockData.providers[gabon] = original);
  });

  Future<ProAuthProvider> signIn([String email = _owner]) async {
    final p = ProAuthProvider();
    await p.ready; // the constructor's (signed-out) load, out of the way
    await p.requestEmailOtp(email);
    final ok = await p.verifyEmailOtp(email, p.emailDevCode!);
    expect(ok, isTrue, reason: 'login as $email failed');
    return p;
  }

  /// The app starting again on the stored session.
  Future<ProAuthProvider> restart() async {
    final p = ProAuthProvider();
    await p.ready;
    return p;
  }

  group('cold start whose /me fails', () {
    test('answers the salon\'s market facts from the session — the '
        'reproduced defect: they used to fall back to Abidjan', () async {
      final first = await signIn();
      expect(first.salonTimezone, _libreville, reason: 'the live answer');

      pro.meFails = true;
      final restarted = await restart();

      expect(pro.calls, greaterThan(1), reason: 'the refresh did run');
      expect(restarted.isAuthenticated, isTrue);
      expect(restarted.activeSalon, isNull, reason: 'no live payload');
      expect(restarted.salonTimezone, _libreville);
      expect(restarted.salonCurrency, 'XAF');
      expect(restarted.salonCountryCode, 'GA');
      expect(restarted.salonAreaId, 'ga-libreville');
      expect(restarted.salonKnown, isTrue);
      expect(restarted.needsSalon, isFalse, reason: 'nothing to block');
    });

    test('a session stored before this change (no facts) knows no salon — '
        'it is never guessed', () async {
      await signIn();
      await auth.cacheProviderSalonMarket(null); // the pre-change blob

      pro.meFails = true;
      final restarted = await restart();

      expect(restarted.membership?.salonId, 'provider1');
      expect(restarted.salonTimezone, isNull);
      expect(restarted.salonCurrency, isNull);
      expect(restarted.salonKnown, isFalse);
      expect(restarted.needsSalon, isTrue);
    });

    test('a refresh that lands replaces the cached facts', () async {
      await signIn();
      await auth.cacheProviderSalonMarket(
        const SalonMarket(salonId: 'provider1', timezone: 'Africa/Lagos'),
      );

      final restarted = await restart();

      expect(restarted.salonTimezone, _libreville);
      expect(
        (await auth.getCachedProviderSalonMarket())?.timezone,
        _libreville,
      );
    });
  });

  group('the facts count only for the salon the session acts in', () {
    test('every /me answer writes them — sign-in, then a switch', () async {
      final p = await signIn();
      expect(
        await auth.getCachedProviderSalonMarket(),
        const SalonMarket(
          salonId: 'provider1',
          timezone: _libreville,
          currency: 'XAF',
          countryCode: 'GA',
          areaId: 'ga-libreville',
        ),
      );

      expect(await p.switchSalon('provider2'), isTrue);
      final cached = await auth.getCachedProviderSalonMarket();
      expect(cached?.salonId, 'provider2');
      expect(cached?.timezone, isNot(_libreville));
      expect(p.salonTimezone, cached?.timezone);
    });

    test('a switch takes the new salon\'s facts with its selection — never '
        'one without the other', () async {
      final p = await signIn();
      bool? knownWhileSelecting;
      auth.onSelect = () => knownWhileSelecting = p.salonKnown;

      expect(await p.switchSalon('provider2'), isTrue);

      expect(knownWhileSelecting, isTrue);
    });

    test('R6 fallback mid-session whose refetch fails: the lost selection\'s '
        'facts do not answer for the default salon', () async {
      // provider2 in Gabon, provider1 back to its CI seed, for this test.
      final p2 = MockData.providers.indexWhere((s) => s.id == 'provider2');
      final p2Original = MockData.providers[p2];
      MockData.providers[p2] = p2Original.copyWith(
        countryCode: 'GA',
        timezone: _libreville,
        currency: 'XAF',
      );
      addTearDown(() => MockData.providers[p2] = p2Original);
      MockData.providers[gabon] = MockData.providers[gabon].copyWith(
        timezone: 'Africa/Abidjan',
        currency: 'XOF',
        countryCode: 'CI',
      );

      final p = await signIn();
      expect(await p.switchSalon('provider2'), isTrue);
      expect(p.salonTimezone, _libreville);
      var notified = 0;
      p.addListener(() => notified++);

      // Revoked from provider2, and the default salon's /me then fails.
      pro.script.addAll([_Pro.forbidden(), _Pro.serverError()]);
      await p.checkMembershipAlive();

      expect(p.activeSalonId, 'provider1', reason: 'the selection fell back');
      expect(
        p.salonTimezone,
        isNull,
        reason: 'provider2\'s Libreville is not provider1\'s clock',
      );
      expect(p.needsSalon, isTrue);
      expect(notified, greaterThan(0), reason: 'the screen must learn it');
    });

    test('R6 fallback at cold start whose refetch fails: the cached facts '
        'are the lost selection\'s, so they do not answer', () async {
      final p = await signIn();
      expect(await p.switchSalon('provider2'), isTrue);
      expect((await auth.getCachedProviderSalonMarket())?.salonId, 'provider2');

      pro.script.addAll([_Pro.forbidden(), _Pro.serverError()]);
      final restarted = await restart();

      expect(restarted.activeSalonId, 'provider1');
      expect(restarted.salonTimezone, isNull);
      expect(restarted.needsSalon, isTrue);
    });
  });

  group('needsSalon', () {
    test('a sign-in whose /me fails is signed in with no salon', () async {
      final p = ProAuthProvider();
      await p.ready;
      await p.requestEmailOtp(_owner);
      pro.meFails = true;
      final ok = await p.verifyEmailOtp(_owner, p.emailDevCode!);

      expect(ok, isTrue, reason: 'the sign-in itself succeeded');
      expect(p.isAuthenticated, isTrue);
      expect(p.salonTimezone, isNull);
      expect(p.needsSalon, isTrue);
    });

    test('a LOADED salon with no timezone is known — Abidjan is then the '
        'server\'s own default, not a guess', () async {
      pro.noTimezone = true;
      final p = await signIn();

      expect(p.salonTimezone, isNull);
      expect(p.salonKnown, isTrue);
      expect(p.needsSalon, isFalse);
    });

    test('signed out: nothing to wait for', () async {
      final p = await restart();
      expect(p.isAuthenticated, isFalse);
      expect(p.needsSalon, isFalse);
    });

    test('the rejoin gate holds a session with no salon on purpose', () async {
      final p = await signIn(kFatou);
      expect(p.salonKnown, isTrue);

      revokeMember(kFatouRow);
      await reinvite(serviceLocator.proTeamService);
      await p.checkMembershipAlive();

      expect(p.rejoinPending, isTrue);
      expect(p.salonKnown, isFalse);
      expect(p.needsSalon, isFalse, reason: '« Invitations » shows no hour');
      expect(
        await auth.getCachedProviderSalonMarket(),
        isNull,
        reason: 'the lost salon\'s facts go with its membership',
      );
    });

    test('a sign-out drops the facts and their cache — the next sign-in '
        'does not inherit them', () async {
      final p = await signIn();
      await p.logout();

      expect(p.salonTimezone, isNull);
      expect(await auth.getCachedProviderSalonMarket(), isNull);

      await p.requestEmailOtp(_owner);
      pro.meFails = true;
      expect(await p.verifyEmailOtp(_owner, p.emailDevCode!), isTrue);
      expect(p.needsSalon, isTrue, reason: 'this session never loaded it');
    });
  });

  group('retrySalon (« Réessayer »)', () {
    test('a /me that answers again gives the salon back', () async {
      final p = ProAuthProvider();
      await p.ready;
      await p.requestEmailOtp(_owner);
      pro.meFails = true;
      await p.verifyEmailOtp(_owner, p.emailDevCode!);
      expect(p.needsSalon, isTrue);

      pro.meFails = false;
      final loading = <bool>[];
      p.addListener(() => loading.add(p.salonLoading));
      await p.retrySalon();

      expect(p.needsSalon, isFalse);
      expect(p.salonTimezone, _libreville);
      expect(loading.first, isTrue, reason: 'the screen shows the wait');
      expect(loading.last, isFalse);
    });

    test('a /me that fails again says so — the wait ends', () async {
      final p = ProAuthProvider();
      await p.ready;
      await p.requestEmailOtp(_owner);
      pro.meFails = true;
      await p.verifyEmailOtp(_owner, p.emailDevCode!);

      final loading = <bool>[];
      p.addListener(() => loading.add(p.salonLoading));
      await p.retrySalon();

      expect(p.needsSalon, isTrue);
      expect(loading, [true, false]);
    });
  });
}
