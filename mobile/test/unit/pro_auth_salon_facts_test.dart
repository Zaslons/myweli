import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_facts.dart';
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

const _owner = 'jean@salon-excellence.test';

/// GET /me/provider, with a switch to fail it — a cold start offline.
class _Pro extends MockProService {
  bool meFails = false;

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId}) async {
    if (meFails) {
      return ApiResponse.error('Pas de connexion.', code: 'network');
    }
    return super.getMyProvider(salonId: salonId);
  }
}

/// docs/design/product-questions-batch8.md §2.3 (B8.3, decision 29) — the
/// salon's « Profil » facts (name, category, address, phone) are kept in the
/// session next to the membership and the market, so an offline cold start
/// still shows them. They answer only for the salon the session acts in, a
/// live read replaces them, and a sign-out or the rejoin gate drops them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pro = _Pro();
  final auth = MockAuthService();

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

  setUp(() async {
    MockData.resetTeam();
    pro.meFails = false;
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
    await auth.logoutProvider();
    ProRouter.router.go('/pro/splash');
  });

  Future<ProAuthProvider> signIn([String email = _owner]) async {
    final p = ProAuthProvider();
    await p.ready;
    await p.requestEmailOtp(email);
    expect(await p.verifyEmailOtp(email, p.emailDevCode!), isTrue);
    return p;
  }

  /// The app starting again on the stored session.
  Future<ProAuthProvider> restart() async {
    final p = ProAuthProvider();
    await p.ready;
    return p;
  }

  final provider1 = MockData.providers.firstWhere((p) => p.id == 'provider1');

  test('a live read gives the salon\'s facts, and keeps them', () async {
    final p = await signIn();

    expect(p.salonFacts, SalonFacts.of(provider1));
    expect(await auth.getCachedProviderSalonFacts(), SalonFacts.of(provider1));
  });

  test('a cold start offline answers them from the session', () async {
    await signIn();
    pro.meFails = true;

    final restarted = await restart();

    expect(restarted.activeSalon, isNull, reason: 'no live payload');
    expect(restarted.salonFacts, SalonFacts.of(provider1));
  });

  test('a session kept before this change has none — offline, the card '
      'says so as before', () async {
    await signIn();
    await auth.cacheProviderSalonFacts(null); // the pre-change blob
    pro.meFails = true;

    final restarted = await restart();

    expect(restarted.salonFacts, isNull);
  });

  test('a live read replaces the kept copy', () async {
    await signIn();
    await auth.cacheProviderSalonFacts(
      const SalonFacts(salonId: 'provider1', name: 'Ancien nom'),
    );

    final restarted = await restart();

    expect(restarted.salonFacts?.name, provider1.name);
    expect((await auth.getCachedProviderSalonFacts())?.name, provider1.name);
  });

  test('a switch keeps the new salon\'s facts', () async {
    final p = await signIn();
    expect(await p.switchSalon('provider2'), isTrue);

    final provider2 = MockData.providers.firstWhere((s) => s.id == 'provider2');
    expect(p.salonFacts, SalonFacts.of(provider2));
    expect(await auth.getCachedProviderSalonFacts(), SalonFacts.of(provider2));
  });

  test('a copy kept for ANOTHER salon is never shown for this one', () async {
    final p = await signIn();
    expect(await p.switchSalon('provider2'), isTrue);
    // A copy that names provider1 while the session acts in provider2.
    await auth.cacheProviderSalonFacts(SalonFacts.of(provider1));
    pro.meFails = true;

    final restarted = await restart();

    expect(restarted.activeSalonId, 'provider2', reason: 'the scenario');
    expect(restarted.salonFacts, isNull);
  });

  test('a sign-out drops them', () async {
    final p = await signIn();
    await p.logout();

    expect(p.salonFacts, isNull);
    expect(await auth.getCachedProviderSalonFacts(), isNull);
  });

  test('the rejoin gate drops them with the lost salon', () async {
    final p = await signIn(kFatou);
    expect(p.salonFacts, isNotNull, reason: 'the scenario');

    revokeMember(kFatouRow);
    await reinvite(serviceLocator.proTeamService);
    await p.checkMembershipAlive();

    expect(p.rejoinPending, isTrue, reason: 'the scenario');
    expect(p.salonFacts, isNull);
    expect(await auth.getCachedProviderSalonFacts(), isNull);
  });
}
