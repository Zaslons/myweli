import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/constants/salon_validation_copy.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/core/utils/team_error_messages.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/dashboard/dashboard_screen.dart';
import 'package:myweli/screens/provider/onboarding/pro_onboarding_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_notification_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_kyc_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:myweli/widgets/provider/salon_picker_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '_a11y.dart';

/// The mock with the seeded salon's third photo (≥3 is a publish gate), so
/// every button these subjects carry is ENABLED — a disabled button is no
/// tap target, and the 48dp guideline would measure nothing. [third] off
/// leaves a step to do: the button disabled, and its hint beside it.
/// [legacy]: a server from before B0.18 (no `validation` key).
class _ThreePhotos extends MockProService {
  bool third = true;
  bool legacy = false;

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({SalonId? salonId}) async {
    final res = await super.getMyProvider(salonId: salonId);
    final data = res.data;
    if (data == null) return res;
    final salon = third
        ? data.salon.copyWith(
            imageUrls: [...data.salon.imageUrls, 'asset:third.png'],
          )
        : data.salon;
    if (legacy) {
      return ApiResponse.success(
        MyProviderInfo(salon: salon, membership: data.membership),
      );
    }
    return ApiResponse.success(data.copyWith(salon: salon));
  }
}

const _p1 = SalonId('provider1');

/// A note an admin typed: long, with a word longer than a 360dp line at 2×.
const _longNote =
    'La photo de la devanture est floue et l’adresse indiquée ne correspond '
    'pas au quartier. Référence-du-dossier-MYWELI-2026-11-13-ABIDJAN-COCODY.';

/// MyWeli's validation on the Pro app at the contract point — 360dp, 200%
/// text (B0.18 — salon-go-live-approval §8.3; SYSTEM.md §10, §13.2, §13.3):
/// « Configuration »'s banner in each state with its action (the three
/// publish labels and the billing pointer, each a 48dp target), and the
/// salon picker's row, whose state now has a line of its own.
///
/// Per configuration, the repo's own gate:
///  **A** nothing overflowed — `takeException()`;
///  **B** no text cut off without saying so — [expectNoUndeclaredTruncation];
///  **D** no text clipped by a fixed height — [expectNoVerticalClip];
///  **C** the subject actually rendered — its own words. Without C, a subject
///  that landed on another state would measure its padding green.
void main() {
  final subs = MockSubscriptionService();
  final pro = _ThreePhotos();
  // §8.3: both platforms — no platform branch may exist.
  final bothPlatforms = TargetPlatformVariant(const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  setUpAll(() async {
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = pro;
    serviceLocator.proArtistService = MockProArtistService();
    serviceLocator.proKycService = MockProKycService();
    serviceLocator.subscriptionService = subs;
    serviceLocator.localityService = MockLocalityService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    MockData.resetTeam();
    ProSalonScope.clear();
    subs.resetForTests();
    pro
      ..third = true
      ..legacy = false;
    await serviceLocator.authService.logoutProvider();
  });

  // Each configuration is its own `testWidgets`: the overflow report latches
  // once per render object (layout_test.dart, « Why the loops are outside
  // `testWidgets` »).
  for (final (name, seed, words, action)
      in <(String, void Function(), List<String>, String?)>[
        (
          'never asked',
          () => MockData.seedNeverAsked(_p1),
          ['Profil de l’entreprise'],
          SalonValidationCopy.requestButton,
        ),
        ('live', () {}, ['Profil de l’entreprise', 'Aperçu de ma page'], null),
        (
          'pending',
          () => MockData.seedPendingRequest(
            _p1,
            submittedAt: DateTime.utc(2026, 11, 13, 9),
          ),
          [
            SalonValidationCopy.pendingTitle,
            SalonValidationCopy.pendingText,
            'Demande envoyée le 13 novembre 2026',
          ],
          null,
        ),
        (
          'refused, a long note',
          () => MockData.seedRefused(_p1, code: 'unconfirmed', note: _longNote),
          [
            SalonValidationCopy.refusedTitle,
            SalonValidationCopy.refusalSentences['unconfirmed']!,
            _longNote,
            SalonValidationCopy.resubmit,
          ],
          SalonValidationCopy.resubmitButton,
        ),
        (
          'refused for good, the longest reason',
          () => MockData.seedRefused(_p1, code: 'outside_ci', note: _longNote),
          [
            SalonValidationCopy.refusedTitle,
            SalonValidationCopy.refusalSentences['outside_ci']!,
            _longNote,
          ],
          null,
        ),
        (
          'no longer online, offer lapsed',
          () => MockData.seedOffline(_p1),
          [SalonValidationCopy.offlineTitle, salonUnpublishedForBillingMessage],
          SalonValidationCopy.billingPointer,
        ),
        (
          'no longer online, offer live',
          () {
            MockData.seedOffline(_p1);
            subs.startTrialIfAbsent(_p1, tier: SalonTier.pro);
          },
          [
            SalonValidationCopy.offlineTitle,
            SalonValidationCopy.offlineRepublishText,
          ],
          SalonValidationCopy.republishButton,
        ),
        (
          'suspended',
          () => MockData.seedSuspended(_p1),
          [
            SalonValidationCopy.suspendedTitle,
            SalonValidationCopy.suspendedText,
            'Aperçu de ma page',
          ],
          null,
        ),
      ]) {
    testWidgets('« Configuration », $name, at 360dp × 200%: whole, and its '
        'action a 48dp target', (tester) async {
      seed();
      final auth = await signInPro(tester);
      await tester.runAsync(auth.rereadMySalons);
      final handle = tester.ensureSemantics();
      try {
        await pumpAtWidth(
          tester,
          width: 360,
          scale: 2,
          height: 3600,
          home: const ProOnboardingScreen(),
          providers: [
            ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => ProOnboardingProvider()),
          ],
          rounds: 9,
        );

        expect(tester.takeException(), isNull, reason: 'A — $name');
        for (final w in words) {
          expect(find.text(w), findsOneWidget, reason: 'C — « $w »');
        }
        expectNoUndeclaredTruncation(tester, context: 'B — $name');
        expectNoVerticalClip(tester, context: 'D — $name');

        if (action != null) {
          final label = find.text(action);
          await tester.scrollUntilVisible(label, 300);
          final button = find.ancestor(
            of: label,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          );
          expect(
            tester.widget<ButtonStyleButton>(button).onPressed,
            isNotNull,
            reason: '« $action » enabled — measured as a target',
          );
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          expectNoUndeclaredTruncation(
            tester,
            ellipsisIsFine: false,
            within: label,
            context: '« $action »',
          );
        }
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      } finally {
        handle.dispose();
      }
    }, variant: bothPlatforms);
  }

  // The hint beside a DISABLED button (§6.1 « Button »): the subjects above
  // keep every button enabled on purpose, so none of them measures it.
  for (final (name, legacy, button, hint) in <(String, bool, String, String)>[
    (
      'never asked, a step still to do',
      false,
      SalonValidationCopy.requestButton,
      SalonValidationCopy.requestHint,
    ),
    (
      'a server from before B0.18, a step still to do',
      true,
      SalonValidationCopy.legacyButton,
      SalonValidationCopy.legacyHint,
    ),
  ]) {
    testWidgets('« Configuration », $name, at 360dp × 200%: the hint '
        'whole beside the disabled button', (tester) async {
      MockData.seedNeverAsked(_p1);
      pro
        ..third = false
        ..legacy = legacy;
      final auth = await signInPro(tester);
      await tester.runAsync(auth.rereadMySalons);
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 2,
        height: 3600,
        home: const ProOnboardingScreen(),
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProOnboardingProvider()),
        ],
        rounds: 9,
      );

      expect(tester.takeException(), isNull, reason: 'A — $name');
      final label = find.text(hint);
      await tester.scrollUntilVisible(label, 300);
      expect(label, findsOneWidget, reason: 'C — « $hint »');
      final b = find.ancestor(
        of: find.text(button),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(
        tester.widget<ButtonStyleButton>(b).onPressed,
        isNull,
        reason: 'C — « $button » disabled',
      );
      expectNoUndeclaredTruncation(
        tester,
        ellipsisIsFine: false,
        within: label,
        context: 'B — « $hint »',
      );
      expectNoUndeclaredTruncation(tester, context: 'B — $name');
      expectNoVerticalClip(tester, context: 'D — $name');
    }, variant: bothPlatforms);
  }

  // « Accueil »'s « Configurer mon profil » card, its two longest new
  // subtitles (decision 136 item 1) — the w360_x2 golden shows only « Votre
  // salon est en ligne ».
  for (final (seed, words) in <(void Function(), String)>[
    (
      () => MockData.seedRefused(_p1, code: 'photos'),
      SalonValidationCopy.lineRefused,
    ),
    (() => MockData.seedPendingRequest(_p1), SalonValidationCopy.linePending),
  ]) {
    testWidgets('« Accueil »\'s card at 360dp × 200%: « $words » whole', (
      tester,
    ) async {
      seed();
      final auth = await signInPro(tester);
      await tester.runAsync(auth.rereadMySalons);
      await pumpAtWidth(
        tester,
        width: 360,
        scale: 2,
        height: 3600,
        home: const DashboardScreen(),
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProDashboardProvider()),
          ChangeNotifierProvider(
            create: (_) =>
                NotificationsProvider(service: MockNotificationService()),
          ),
          ChangeNotifierProvider(create: (_) => ProTeamProvider()),
        ],
        rounds: 5,
      );

      expect(tester.takeException(), isNull, reason: 'A — « $words »');
      final subtitle = find.descendant(
        of: find.ancestor(
          of: find.text('Configurer mon profil'),
          matching: find.byType(ListTile),
        ),
        matching: find.text(words),
      );
      await tester.scrollUntilVisible(subtitle, 300);
      expect(subtitle, findsOneWidget, reason: 'C — « $words »');
      expectNoUndeclaredTruncation(
        tester,
        ellipsisIsFine: false,
        within: subtitle,
        context: 'B — « $words »',
      );
      expectNoVerticalClip(tester, context: 'D — « $words »');
      await tester.pump(const Duration(seconds: 2));
    }, variant: bothPlatforms);
  }

  // §6.2: « the state on its own line, because at 200% text a « role ·
  // state » line cuts the state off ». The default sweep would not see that
  // line cut: it was a DECLARED ellipsis (maxLines 1) — so the audit runs
  // with `ellipsisIsFine: false`, scoped to the state's text, and the row's
  // other declared ellipsis (the salon's name) stays out of it.
  testWidgets('« Mes salons » at 360dp × 200%: every row\'s state whole, on '
      'its own line', (tester) async {
    MockData.teamMembers.add(
      TeamMember(
        id: 'tm_jean_provider3',
        providerId: SalonId('provider3'),
        email: 'jean@salon-excellence.test',
        role: TeamRole.manager,
        status: TeamMemberStatus.active,
        invitedAt: DateTime(2026, 7, 1),
        accountId: 'provider_user1',
        acceptedAt: DateTime(2026, 7, 2),
      ),
    );
    MockData.seedPendingRequest(_p1);
    MockData.seedNeverAsked(SalonId('provider2'));
    MockData.seedOffline(SalonId('provider3'));
    final auth = await signInPro(tester);
    await tester.runAsync(auth.rereadMySalons);

    await pumpAtWidth(
      tester,
      width: 360,
      scale: 2,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSalonPicker(context),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
      providers: [ChangeNotifierProvider<ProAuthProvider>.value(value: auth)],
      rounds: 1,
    );
    await tester.tap(find.text('ouvrir'));
    await settleMocks(tester, rounds: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('Mes salons'), findsOneWidget);
    for (final line in [
      SalonValidationCopy.linePending,
      SalonValidationCopy.lineNeverAsked,
      SalonValidationCopy.lineOffline,
    ]) {
      final state = find.descendant(
        of: find.byType(ListTile),
        matching: find.textContaining(line),
      );
      expectNoUndeclaredTruncation(
        tester,
        ellipsisIsFine: false,
        within: state,
        context: 'the row saying « $line »',
      );
      expect(find.text(line), findsOneWidget, reason: 'its own line');
    }
    expectNoUndeclaredTruncation(tester, context: 'the sheet');
    await tester.pump(const Duration(seconds: 2));
  }, variant: bothPlatforms);
}
