import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_artist_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_subscription_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/team/team_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/drawn_email.dart';
import '../support/fonts.dart';
import '../support/settle.dart';
import '_a11y.dart';

/// The session's account: the owner of `provider1` (« Salon Excellence »).
class _OwnerSession extends MockAuthService {
  @override
  Future<ProviderUser?> getCurrentProvider() async =>
      MockData.providerUsers.first;
}

/// « Équipe » in the Pro app under SYSTEM.md §13.3's e-mail rule
/// (docs/design/app-team-email-seams.md): every place that draws a member's
/// address breaks it only before its « @ » or a « . » of its name part, and a
/// sentence that names one gives it a line of its own.
///
/// **What was broken, measured on `main` (2e148f89)**, 360 dp, real font:
/// - the roster cut EVERY address with « … », at 1× too (« aminata.kone… »);
///   at 2× a row showed « a… » — 28 dp beside « Collaborateur »;
/// - the actions sheet's heading cut it (« aminata.kone… » at 2×);
/// - « Révoquer l’accès ? » broke it mid-word: « aminata.kone@exe » /
///   « mple.ci perdra »;
/// - the role step broke it mid-word, « ? » drawn after it: « Quel rôle pour
///   adjoua.ko » / « uame@exemple.ci ? ».
///
/// The four snackbars lose the address (§5, the website's choice): their
/// words are pinned in `team_screen_test.dart` and
/// `invite_member_sheet_test.dart`.
void main() {
  setUpAll(() async {
    await loadRealFonts();
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = _OwnerSession();
    serviceLocator.proTeamService = MockProTeamService();
    serviceLocator.proArtistService = MockProArtistService();
    serviceLocator.imageUploadService = MockImageUploadService();
    serviceLocator.subscriptionService = MockSubscriptionService(
      initial: SalonSubscription(
        tier: SalonTier.business,
        status: SalonOfferStatus.trial,
        trialEndsAt: DateTime.now().add(const Duration(days: 60)),
        graceEndsAt: DateTime.now().add(const Duration(days: 67)),
        seats: const SalonSeats(cap: 15, used: 0),
      ),
    );
  });

  /// Wider than a line at 2× (≈ 18 characters on 360 dp): its name part and
  /// its domain each fit one. The manager.
  const long = 'aminata.kone@exemple.ci';

  /// Three pieces of name, and a domain of twelve characters — one piece,
  /// never broken at its « . » — the width of `@hotmail.com`, `@myweli.com`:
  /// 213 dp at 2×, wider than the 192 the initial avatar left the title
  /// (app-team-email-seams.md §3, found by the first Linux picture:
  /// « @myweli.tes » / « t »). The pending Collaborateur.
  const pending = 'awa.kone.nouvelle@outlook.com';

  /// Break points before EVERY « . » would orphan its « .com ». A réception.
  const seam = 'koffi.yao@gmail.com';

  /// Fits a line: never cut before, and still a line of its own now. The
  /// expired réception.
  const short = 'awa@exemple.ci';

  /// Beside « Collaborateur », the widest chip: the row's « a… » at 2×. Four
  /// pieces, each narrower than the roster's line at 2×, and too long for
  /// the sheet's heading beside its chip at 1× (« adjoua.kouame.konan@exe… »).
  const staff = 'adjoua.kouame.konan@exemple.ci';

  /// The owner's row is inert and has no chevron: 40 dp more than the others.
  const owner = 'mariam.toure@exemple.ci';

  const roster = [owner, long, pending, seam, short, staff];

  setUp(() {
    MockData.resetTeam();
    // `provider1`'s six rows, given the addresses above. The seed's own are
    // short and `.test`; the owner's has a hyphen in its domain, which the
    // engine may break at (§13.3) and `expectNoMidWordBreak` cannot measure.
    const addresses = {
      'mem_owner1': owner,
      'mem_manager1': long,
      'mem_staff1': pending,
      'mem_reception2': seam,
      'mem_reception1': short,
      'mem_staff2': staff,
    };
    for (var i = 0; i < MockData.teamMembers.length; i++) {
      final m = MockData.teamMembers[i];
      final address = addresses[m.id];
      if (address == null) continue;
      MockData.teamMembers[i] = TeamMember.fromJson({
        ...m.toJson(),
        'email': address,
      });
    }
  });

  Future<void> openTeam(WidgetTester tester, {required double scale}) async {
    await pumpAtWidth(
      tester,
      width: 360,
      scale: scale,
      height: 2400,
      home: const TeamScreen(),
      providers: [
        ChangeNotifierProvider(create: (_) => ProAuthProvider()),
        ChangeNotifierProvider(create: (_) => ProTeamProvider()),
        ChangeNotifierProvider(create: (_) => ProSubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => ProArtistProvider()),
      ],
    );
    expect(drawnEmail(long), findsOneWidget, reason: 'the roster is drawn');
  }

  Future<void> openSheet(WidgetTester tester, String address) async {
    await tester.tap(drawnEmail(address));
    await settleMocks(tester, rounds: 2);
    expect(find.text('Changer le rôle'), findsOneWidget);
  }

  /// The invite sheet, on its role step for [address].
  Future<void> openRoleStep(WidgetTester tester, String address) async {
    await tester.tap(find.text('Inviter un membre'));
    await settleMocks(tester, rounds: 2);
    await tester.enterText(find.byType(TextField), address);
    await tester.pump();
    await tester.tap(find.text('Continuer'));
    await settleMocks(tester, rounds: 2);
    expect(find.text('Manager'), findsWidgets, reason: 'the role step');
  }

  /// No node a screen reader can reach carries a break mark.
  void expectNoMarkHeard() => expect(
    find.bySemanticsLabel(RegExp('\u200B')),
    findsNothing,
    reason: 'the break marks are drawn, never heard (§13.3)',
  );

  for (final (scale, at) in [(2.0, '360 dp × 2×'), (1.0, '360 dp × 1×')]) {
    group('at $at', () {
      testWidgets('the roster draws every address whole, broken only at its '
          'seams', (tester) async {
        await openTeam(tester, scale: scale);
        for (final address in roster) {
          expectEmailAddressOnItsOwnLine(tester, address, 'the roster, $at');
        }
      });

      testWidgets('the actions sheet names its member whole, on a line of '
          'its own', (tester) async {
        final handle = tester.ensureSemantics();
        await openTeam(tester, scale: scale);
        for (final address in [long, staff]) {
          await openSheet(tester, address);
          // The sheet's own heading: the row it was opened from is drawn
          // behind it, and is the roster test's subject.
          expectEmailAddressOnItsOwnLine(
            tester,
            address,
            'the sheet, $at',
            within: find.byType(BottomSheet),
          );
          // A screen reader hears the heading's address without its marks.
          expectNoMarkHeard();
          Navigator.of(tester.element(find.text('Changer le rôle'))).pop();
          await settleMocks(tester);
        }
        handle.dispose();
      });

      testWidgets('« Révoquer l’accès ? » gives the address the first line', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await openTeam(tester, scale: scale);
        await openSheet(tester, long);
        await tester.tap(find.text('Révoquer l’accès'));
        await settleMocks(tester, rounds: 2);

        expectEmailAddressOnItsOwnLine(
          tester,
          long,
          'the dialog, $at',
          within: find.byType(AlertDialog),
        );
        // The rest of the sentence, under it.
        expect(
          find.text(
            'perdra immédiatement l’accès à Salon Excellence. '
            'Son compte MyWeli n’est pas supprimé.',
          ),
          findsOneWidget,
        );
        // A screen reader hears the sentence it always heard, in one node.
        expect(
          find.bySemanticsLabel(
            '$long perdra immédiatement l’accès à Salon Excellence. '
            'Son compte MyWeli n’est pas supprimé.',
          ),
          findsOneWidget,
        );
        expectNoMarkHeard();
        handle.dispose();
      });

      testWidgets('the role step: « Quel rôle pour », then the address', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await openTeam(tester, scale: scale);
        const invited = 'marie.claire.yao@exemple.ci';
        await openRoleStep(tester, invited);

        expectEmailAddressOnItsOwnLine(tester, invited, 'the role step, $at');
        expect(find.text('Quel rôle pour'), findsOneWidget);
        // Its « ? » is heard, not drawn.
        expect(
          find.bySemanticsLabel('Quel rôle pour $invited ?'),
          findsOneWidget,
        );
        expectNoMarkHeard();
        handle.dispose();
      });
    });
  }

  testWidgets('a screen reader hears each row\'s address first, without its '
      'marks, then its role', (tester) async {
    final handle = tester.ensureSemantics();
    await openTeam(tester, scale: 2);
    for (final address in roster) {
      expect(
        find.bySemanticsLabel(RegExp('^${RegExp.escape(address)}\\n')),
        findsOneWidget,
        // The initial avatar is gone (app-team-email-seams.md §5.3): a
        // screen reader heard its letter first — « A, aminata.kone@… ».
        reason: '« $address » begins its row\'s one node',
      );
    }
    expect(
      find.bySemanticsLabel(RegExp('^${RegExp.escape(long)}\\nManager')),
      findsOneWidget,
      reason: 'the role follows the address, as it did beside it',
    );
    expectNoMarkHeard();
    handle.dispose();
  });

  testWidgets('a short address on the role step: a line of its own, no « ? » '
      'after it', (tester) async {
    await openTeam(tester, scale: 1);
    const invited = 'ama@b.ci';
    await openRoleStep(tester, invited);
    expectEmailAddressOnItsOwnLine(tester, invited, 'the role step, 1×');
  });
}
