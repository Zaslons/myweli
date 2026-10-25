import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/profile/pro_profile_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

const _ownerSentence =
    'Cette action est définitive. Votre salon sera retiré de MyWeli. Pensez à '
    'exporter vos données avant.';
const _memberSentence =
    'Cette action est définitive. Votre compte MyWeli Pro sera supprimé.';

/// docs/design/pro-app-batch7.md §2.3 (B7.3, Q5) — the deletion dialog says
/// what the SERVER will do: it removes every salon the account OWNS
/// (`provider_account_service.dart` deleteAccount), and nothing of a salon
/// where the account is only a member. So the salon sentence is for an
/// account that owns a salon — whatever the salon on screen — and a member
/// reads that their account goes.
void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
    serviceLocator.proTeamService = MockProTeamService();
    // « Mes salons » reads the offers too (the « Ajouter un salon » gate).
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(MockData.resetTeam);

  Future<void> openDialog(WidgetTester tester, ProAuthProvider auth) async {
    final router = GoRouter(
      initialLocation: '/pro/profile',
      routes: [
        GoRoute(
          path: '/pro/profile',
          builder: (_, _) => const ProProfileScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProTeamProvider()),
        ],
        routerConfig: router,
      ),
    );
    await settleMocks(tester, rounds: 2);
    final entry = find.text('Supprimer mon compte');
    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await settleMocks(tester);
    expect(find.text('Supprimer votre compte ?'), findsOneWidget);
  }

  testWidgets('the owner reads that the salon goes', (tester) async {
    await openDialog(tester, await signInPro(tester));
    expect(find.text(_ownerSentence), findsOneWidget);
    expect(find.text(_memberSentence), findsNothing);
  });

  testWidgets('a member (Gérant) reads that their ACCOUNT goes — no salon '
      'of theirs is removed', (tester) async {
    await openDialog(
      tester,
      await signInPro(tester, email: 'awa.manager@myweli.test'),
    );
    expect(find.text(_memberSentence), findsOneWidget);
    expect(find.text(_ownerSentence), findsNothing);
  });

  testWidgets('an owner looking at a salon they only MANAGE still reads that '
      'their salon goes — the server removes what they own', (tester) async {
    // Jean owns provider1; on provider2 he is made a Gérant.
    final i = MockData.teamMembers.indexWhere((m) => m.id == 'mem_owner2');
    final row = MockData.teamMembers[i];
    MockData.teamMembers[i] = TeamMember(
      id: row.id,
      providerId: row.providerId,
      email: row.email,
      role: TeamRole.manager,
      status: TeamMemberStatus.active,
      invitedAt: row.invitedAt,
      accountId: row.accountId,
      acceptedAt: row.acceptedAt,
    );
    final auth = await signInPro(tester);
    await tester.runAsync(() async {
      expect(await auth.switchSalon(SalonId('provider2')), isTrue);
    });
    expect(auth.role, TeamRole.manager, reason: 'the salon on screen');

    await openDialog(tester, auth);
    expect(find.text(_ownerSentence), findsOneWidget);
    expect(find.text(_memberSentence), findsNothing);
  });

  testWidgets('an account with no linked salon that OWNS one in « Mes '
      'salons » reads that its salon goes', (tester) async {
    // Awa is a Gérant of provider1 with no salon of her own linked — and the
    // Propriétaire of provider2 through an owner membership, which the server
    // removes with her account.
    MockData.teamMembers.add(
      TeamMember(
        id: 'mem_awa_owner2',
        providerId: SalonId('provider2'),
        email: 'awa.manager@myweli.test',
        role: TeamRole.owner,
        status: TeamMemberStatus.active,
        invitedAt: DateTime(2026, 6, 1),
        accountId: 'member_awa',
        acceptedAt: DateTime(2026, 6, 2),
      ),
    );
    final auth = await signInPro(tester, email: 'awa.manager@myweli.test');
    // Sign-in starts its own « Mes salons » load (a second call returns
    // early while it runs), and it advances only in real async: poll, as
    // `signInPro` does for the membership.
    await tester.runAsync(() async {
      for (var i = 0; i < 60 && !auth.salons.any((s) => s.isOwner); i++) {
        await auth.loadMySalons();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    expect(auth.provider?.providerId, isNull, reason: 'no linked salon');
    expect(auth.salons.any((s) => s.isOwner), isTrue);

    await openDialog(tester, auth);
    expect(find.text(_ownerSentence), findsOneWidget);
    expect(find.text(_memberSentence), findsNothing);
  });
}
