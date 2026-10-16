import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/artist.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/service.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/providers/pro_service_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/onboarding/pro_onboarding_screen.dart';
import 'package:myweli/screens/provider/services/service_form_screen.dart';
import 'package:myweli/screens/provider/team/team_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_kyc_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// A session the mock never signed in: [signedInAs] answers
/// `getCurrentProvider` while it is set (the bare-member case below).
class _Auth extends MockAuthService {
  ProviderUser? signedInAs;

  @override
  Future<ProviderUser?> getCurrentProvider() async =>
      signedInAs ?? super.getCurrentProvider();
}

/// The mock world, recording which salon every salon-path read and write was
/// for, with one knob: [myProviderAnswer] replaces `GET /me/provider`.
class _RecordingProService extends MockProService {
  final servicesAsked = <String>[];
  final availabilityAsked = <String>[];
  final depositAsked = <String>[];
  final createdIn = <String>[];
  ApiResponse<MyProviderInfo>? myProviderAnswer;

  void reset() {
    servicesAsked.clear();
    availabilityAsked.clear();
    depositAsked.clear();
    createdIn.clear();
    myProviderAnswer = null;
  }

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId}) async =>
      myProviderAnswer ?? super.getMyProvider(salonId: salonId);

  @override
  Future<ApiResponse<List<Service>>> getProviderServices(String providerId) {
    servicesAsked.add(providerId);
    return super.getProviderServices(providerId);
  }

  @override
  Future<ApiResponse<Availability>> getProviderAvailability(String providerId) {
    availabilityAsked.add(providerId);
    return super.getProviderAvailability(providerId);
  }

  @override
  Future<ApiResponse<DepositPolicy>> getDepositPolicy(String providerId) {
    depositAsked.add(providerId);
    return super.getDepositPolicy(providerId);
  }

  @override
  Future<ApiResponse<Service>> createService(
    String providerId,
    Map<String, dynamic> serviceData,
  ) {
    createdIn.add(providerId);
    return super.createService(providerId, serviceData);
  }
}

class _RecordingArtistService extends MockProArtistService {
  final asked = <String>[];

  @override
  Future<ApiResponse<List<Artist>>> getArtists(String providerId) {
    asked.add(providerId);
    return super.getArtists(providerId);
  }
}

/// R6 salon-id reads (docs/design/r6-salon-id-pin.md): a pro screen scopes
/// its data to `ProAuthProvider.activeSalonId` — never to the account's
/// default salon (`ProviderUser.providerId`), never to the account's own
/// `id`. Each test below was red before its fix; the name-agnostic pin that
/// keeps new reads from coming back lives in
/// test/unit/multi_salon_test.dart (« the sweep pin »).
void main() {
  final auth = _Auth();
  final pro = _RecordingProService();
  final artists = _RecordingArtistService();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.proService = pro;
    serviceLocator.proArtistService = artists;
    serviceLocator.imageUploadService = MockImageUploadService();
    serviceLocator.proKycService = MockProKycService();
    serviceLocator.proTeamService = MockProTeamService();
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
    pro.reset();
    artists.asked.clear();
    auth.signedInAs = null;
    await auth.logoutProvider();
  });

  /// The demo owner (provider1 by default, owner of provider2 too), switched
  /// to [salonId] — the R6 « Mes salons » move.
  Future<ProAuthProvider> ownerSwitchedTo(
    WidgetTester tester,
    String salonId,
  ) async {
    final session = await signInPro(tester);
    await tester.runAsync(() async {
      expect(await session.switchSalon(salonId), isTrue);
    });
    expect(session.activeSalonId, salonId);
    expect(session.provider!.providerId, isNot(salonId), reason: 'the test');
    return session;
  }

  testWidgets('« Configuration » after a switch: every checklist read is for '
      'the switched-to salon, not the account\'s default', (tester) async {
    // The R6 add-salon flow lands exactly here: create → auto-switch →
    // this checklist. It counted the DEFAULT salon's services, team, hours
    // and deposit under the new salon's name.
    final session = await ownerSwitchedTo(tester, 'provider2');
    pro.reset();
    artists.asked.clear();

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: session),
          ChangeNotifierProvider(create: (_) => ProOnboardingProvider()),
        ],
        home: const ProOnboardingScreen(),
      ),
    );
    // services → staff → hours → deposit → listing → KYC: six mock calls.
    await settleMocks(tester, rounds: 7);

    expect(pro.servicesAsked, ['provider2']);
    expect(artists.asked, ['provider2']);
    expect(pro.availabilityAsked, ['provider2']);
    expect(pro.depositAsked, ['provider2']);
  });

  testWidgets('« Équipe » keys on the ACTING salon\'s rights: an owner '
      'switched to a salon where they are a manager gets the guard', (
    tester,
  ) async {
    // Jean owns provider1 (the account's default) and manages provider3.
    MockData.teamMembers.add(
      TeamMember(
        id: 'tm_jean_provider3',
        providerId: 'provider3',
        email: 'jean@salon-excellence.test',
        role: TeamRole.manager,
        status: TeamMemberStatus.active,
        invitedAt: DateTime(2026, 7, 1),
        accountId: 'provider_user1',
        acceptedAt: DateTime(2026, 7, 2),
      ),
    );
    final session = await ownerSwitchedTo(tester, 'provider3');
    expect(session.role, TeamRole.manager);

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: session),
          ChangeNotifierProvider(create: (_) => ProTeamProvider()),
          ChangeNotifierProvider(create: (_) => ProSubscriptionProvider()),
          ChangeNotifierProvider(create: (_) => ProArtistProvider()),
        ],
        home: const TeamScreen(),
      ),
    );
    await settleMocks(tester, rounds: 2);

    expect(find.text('Réservé au propriétaire'), findsOneWidget);
    expect(find.text('Inviter un membre'), findsNothing);
  });

  testWidgets('« Nouveau service » with no salon resolved: nothing is '
      'created, and never in the account\'s id', (tester) async {
    // A bare member (no salon of their own) whose membership read failed at
    // start, with nothing cached: the session knows no salon.
    auth.signedInAs = MockData.providerUsers.firstWhere(
      (u) => u.id == 'member_awa',
    );
    pro.myProviderAnswer = ApiResponse.error(
      'Connexion impossible.',
      code: 'network',
    );
    late ProAuthProvider session;
    await tester.runAsync(() async {
      session = ProAuthProvider();
      await session.ready;
    });
    expect(session.isAuthenticated, isTrue);
    expect(session.activeSalonId, isNull, reason: 'the scenario');

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: session),
          ChangeNotifierProvider(create: (_) => ProServiceProvider()),
          ChangeNotifierProvider(create: (_) => ProArtistProvider()),
        ],
        home: const ServiceFormScreen(),
      ),
    );
    await settleMocks(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom du service'),
      'Coupe homme',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prix — à partir de (FCFA)'),
      '5000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ou durée personnalisée (minutes)'),
      '45',
    );
    final save = find.text('Enregistrer');
    // Every field is a Scrollable too, so ensureVisible, not scrollUntilVisible.
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save);
    await settleMocks(tester, rounds: 2);

    expect(pro.createdIn, isEmpty);
    expect(
      find.text(
        'Votre salon n’a pas pu être chargé. Vérifiez votre connexion et '
        'réessayez.',
      ),
      findsOneWidget,
    );
    // The form keeps what was typed.
    expect(find.text('Coupe homme'), findsOneWidget);
  });
}
