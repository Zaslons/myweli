import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/provider_user.dart';
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
import 'package:myweli/widgets/team/team_role_chip.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/drawn_email.dart';
import '../support/fonts.dart';
import '_a11y.dart';

/// The Pro « Profil »'s member header under SYSTEM.md §13.3's e-mail rule
/// (docs/design/app-pro-profile-email-seams.md): the account's address breaks
/// only before its « @ » or a « . » of its name part, is drawn once, and the
/// role chip sits under the person.
///
/// **What was broken, measured on #905's head**, 360 dp, real font:
/// - a member invited by e-mail has NO name (the server's
///   `createMemberAccount` stores none), so the title beside the chip was the
///   address — cut at 1× past ≈ 25 characters, cut at 2× always
///   (« awa@exe… », 173 dp beside « Manager ») — and the address was drawn
///   AGAIN under it, and heard twice;
/// - that second line broke mid-word at 2×: « aminata.kone@exe » / « mple.ci »,
///   « retard@myweli.co » / « m ».
///
/// The domains are twelve characters where it matters: `@hotmail.com` is
/// 214 dp at 2× (app-team-email-seams.md §3), and the card has 280.
void main() {
  final auth = MockAuthService();

  setUpAll(() async {
    await loadRealFonts();
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.proService = MockProService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
    serviceLocator.proTeamService = MockProTeamService();
  });

  setUp(MockData.resetTeam);

  /// Cut at 1× beside the chip (« adjoua.kouame.konan@hot… »), three lines at
  /// 2× and a twelve-character domain. First in every list: it fails today
  /// at both sizes.
  const hotmail = 'adjoua.kouame.konan@hotmail.com';

  /// Three name pieces that fill a line at 2×, then `@outlook.com`.
  const outlook = 'awa.kone.nouvelle@outlook.com';

  /// Wider than a line at 2× (« aminata.kone@exe » / « mple.ci »).
  const long = 'aminata.kone@exemple.ci';

  /// Our own domain, 205 dp at 2×: « retard@myweli.co » / « m ».
  const ours = 'retard@myweli.com';

  /// Break points before EVERY « . » would orphan its « .com ».
  const seam = 'koffi.yao@gmail.com';

  /// Fits a line at both sizes.
  const short = 'awa@exemple.ci';

  const nameless = [hotmail, outlook, long, ours, seam, short];

  /// The seeds' manager: her account, and her row on the roster, given
  /// [address] — and [name], which a real member never has (§2.1).
  Future<void> openProfile(
    WidgetTester tester, {
    required String address,
    required double scale,
    String? name,
  }) async {
    final i = MockData.providerUsers.indexWhere((p) => p.id == 'member_awa');
    final seeded = MockData.providerUsers[i];
    addTearDown(() => MockData.providerUsers[i] = seeded);
    MockData.providerUsers[i] = ProviderUser(
      id: seeded.id,
      phoneNumber: '',
      name: name,
      businessName: '',
      businessType: BusinessType.other,
      email: address,
      createdAt: seeded.createdAt,
    );
    final j = MockData.teamMembers.indexWhere((m) => m.id == 'mem_manager1');
    MockData.teamMembers[j] = TeamMember.fromJson({
      ...MockData.teamMembers[j].toJson(),
      'email': address,
    });

    late ProAuthProvider session;
    await tester.runAsync(() async {
      await auth.logoutProvider();
      await auth.requestProviderEmailOtp(address);
      final res = await auth.verifyProviderEmailOtp(
        address,
        MockAuthService.demoOtp,
      );
      expect(res.signedIn, isTrue, reason: '« $address » signs in');
      session = ProAuthProvider();
      for (
        var k = 0;
        k < 60 &&
            (session.isLoading ||
                (session.isAuthenticated && session.membership == null));
        k++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    expect(
      session.role,
      TeamRole.manager,
      reason: 'the member header, not the owner\'s salon card',
    );

    await pumpAtWidth(
      tester,
      width: 360,
      scale: scale,
      height: 2400,
      home: const ProProfileScreen(),
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider(create: (_) => ProTeamProvider()),
      ],
    );
    expect(find.text('Mes salons'), findsOneWidget, reason: 'Profil is drawn');
  }

  /// The role chip is on a line of its own, under the address.
  void expectChipUnder(WidgetTester tester, String address, String at) {
    final chip = tester.getRect(find.byType(TeamRoleChip));
    final drawn = tester.getRect(drawnEmail(address));
    expect(
      chip.top,
      greaterThanOrEqualTo(drawn.bottom - 0.5),
      reason:
          'the role chip starts at ${chip.top.toStringAsFixed(1)} and '
          '« $address » ends at ${drawn.bottom.toStringAsFixed(1)}, at $at: '
          'the chip goes under the person — beside it, at 2× it leaves 173 dp, '
          'and no domain fits (app-pro-profile-email-seams.md §2.4)',
    );
  }

  for (final (scale, at) in [(2.0, '360 dp × 2×'), (1.0, '360 dp × 1×')]) {
    group('at $at', () {
      testWidgets('no name: the address is the title, whole, broken only at '
          'its seams', (tester) async {
        for (final address in nameless) {
          await openProfile(tester, address: address, scale: scale);
          expectEmailAddressOnItsOwnLine(tester, address, 'no name, $at');
        }
      });

      testWidgets('no name: the address is drawn once, the role chip under '
          'it', (tester) async {
        for (final address in [short, hotmail]) {
          await openProfile(tester, address: address, scale: scale);
          expect(
            drawnEmail(address),
            findsOneWidget,
            reason:
                'the title IS the address when there is no name: drawing it '
                'again under itself said it twice, at $at',
          );
          expectChipUnder(tester, address, 'no name, $at');
        }
      });

      testWidgets('a name: the address under it, broken only at its seams, '
          'the chip under both', (tester) async {
        for (final address in [hotmail, long]) {
          await openProfile(
            tester,
            address: address,
            scale: scale,
            name: 'Awa Traoré',
          );
          expect(find.text('Awa Traoré'), findsOneWidget);
          expectChipUnder(tester, address, 'a name, $at');
          expectEmailAddressOnItsOwnLine(tester, address, 'a name, $at');
          expect(drawnEmail(address), findsOneWidget);
        }
      });
    });
  }

  testWidgets('a screen reader hears the person once, the address without '
      'its marks, then the role', (tester) async {
    final handle = tester.ensureSemantics();
    String card(String address) => RegExp.escape(address);

    await openProfile(tester, address: long, scale: 2);
    expect(
      find.bySemanticsLabel(
        RegExp('^${card(long)}\\nManager\\nSalon\\nSalon Excellence'),
      ),
      findsOneWidget,
      reason:
          'no name: the card\'s one node says the address once, then the '
          'role — it said « {adresse}, Manager, {adresse}, Salon… »',
    );

    await openProfile(tester, address: long, scale: 2, name: 'Awa Traoré');
    expect(
      find.bySemanticsLabel(
        RegExp('^Awa Traoré\\n${card(long)}\\nManager\\nSalon\\n'),
      ),
      findsOneWidget,
      reason: 'a name: the name, the address, then the role, as drawn',
    );

    expect(
      find.bySemanticsLabel(RegExp('​')),
      findsNothing,
      reason: 'the break marks are drawn, never heard (§13.3)',
    );
    handle.dispose();
  });
}
