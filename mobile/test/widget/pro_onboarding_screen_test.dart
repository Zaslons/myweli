import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/constants/salon_validation_copy.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_message_handler.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/core/utils/team_error_messages.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart' as model;
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/salon_validation.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_onboarding_provider.dart';
import 'package:myweli/screens/provider/onboarding/pro_onboarding_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_locality_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_kyc_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:myweli/widgets/common/status_banner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

/// How the switch probe (`getMyProvider(salonId:)`) answers a notice tap.
enum _SwitchFault {
  /// No answer: `code: 'network'`.
  network,

  /// A per-salon denial (revoked there).
  refused,

  /// An answer about ANOTHER salon — a server that kept the old one
  /// (web-salon-validation.md §4.5 met it on the web).
  keepsOld,
}

/// The mock world, with the knobs this screen needs: a THIRD photo (the
/// seeded salon has two, and ≥3 is a publish gate — without it the button
/// stays disabled), a scripted publish answer (`publishAnswer == null` runs
/// the real mock publish), a server from before B0.18 (no `validation` key),
/// and the notice tap's switch probe — counted, and failing on demand.
class _ScenarioProService extends MockProService {
  ApiResponse<PublishOutcome>? publishAnswer;
  bool thirdPhoto = true;
  bool legacyServer = false;
  _SwitchFault? switchFault;

  /// Every salon a switch probed (`getMyProvider(salonId:)`).
  final List<SalonId> switchProbes = [];

  void reset() {
    publishAnswer = null;
    thirdPhoto = true;
    legacyServer = false;
    switchFault = null;
    switchProbes.clear();
  }

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({SalonId? salonId}) async {
    if (salonId != null) {
      switchProbes.add(salonId);
      switch (switchFault) {
        case _SwitchFault.network:
          return ApiResponse.error(
            'Connexion au serveur impossible',
            code: 'network',
          );
        case _SwitchFault.refused:
          return ApiResponse.error(
            'Votre accès à ce salon a été retiré.',
            code: 'not_a_member',
          );
        case _SwitchFault.keepsOld:
          return super.getMyProvider(); // the selection as it stands
        case null:
          break;
      }
    }
    final res = await super.getMyProvider(salonId: salonId);
    final data = res.data;
    if (data == null) return res;
    final salon = thirdPhoto
        ? data.salon.copyWith(
            imageUrls: [...data.salon.imageUrls, 'asset:third.png'],
          )
        : data.salon;
    // A server before B0.18 sends no `validation` key at all.
    if (legacyServer) {
      return ApiResponse.success(
        MyProviderInfo(salon: salon, membership: data.membership),
      );
    }
    // `copyWith` keeps the read's validation as it came (B0.18).
    return ApiResponse.success(data.copyWith(salon: salon));
  }

  @override
  Future<ApiResponse<PublishOutcome>> publishSalon(SalonId providerId) async =>
      publishAnswer ?? super.publishSalon(providerId);
}

const _p1 = SalonId('provider1');
const _p2 = SalonId('provider2');
const _note = 'Ajoutez une photo de la façade, de jour.';

/// The four buttons a state can carry, and none of them where the state has
/// none.
const _allButtons = [
  SalonValidationCopy.legacyButton,
  SalonValidationCopy.requestButton,
  SalonValidationCopy.resubmitButton,
  SalonValidationCopy.republishButton,
  SalonValidationCopy.billingPointer,
];

/// « Configuration » — the go-live checklist (pro-salon-lifecycle B3) under
/// MyWeli's validation (B0.18 — docs/design/salon-go-live-approval.md §6.1,
/// §6.2, §6.6; decision 136, « as the website »): a banner per state above
/// the steps, the state's own button, « Demande envoyée le … » while a
/// request waits, the publish's answer said for what it is (200 live, 202 a
/// request), and the notice tap that lands here for another salon. Run on
/// BOTH platforms where it matters — no platform branch may exist, and
/// `TargetPlatformVariant` is what proves it.
void main() {
  final pro = _ScenarioProService();
  final subs = MockSubscriptionService();
  final bothPlatforms = TargetPlatformVariant(const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  setUpAll(() {
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
    subs.resetForTests(); // SETUP: no offer row
    pro.reset();
    await serviceLocator.authService.logoutProvider();
  });

  /// The app's own `/pro/onboarding` route (its `?salon=` read included),
  /// among stubs for where the screen sends the salon.
  GoRouter routerAt(String location, {String? notice}) {
    final real = ProRouter.router.configuration.routes
        .whereType<GoRoute>()
        .firstWhere((r) => r.path == '/pro/onboarding');
    Widget stub(String name) => Scaffold(body: Center(child: Text(name)));
    return GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: '/pro/dashboard', builder: (_, _) => stub('stub home')),
        GoRoute(path: '/pro/staff', builder: (_, _) => stub('stub staff')),
        GoRoute(
          path: '/pro/subscription',
          builder: (_, _) => stub('stub subscription'),
        ),
        GoRoute(path: '/pro/apercu', builder: (_, _) => stub('stub apercu')),
        // The feed row's own move: `NotificationsList._open` pushes the
        // notice's route as it came (notifications_list.dart).
        GoRoute(
          path: '/pro/notifications',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push(notice!),
                child: const Text('the notice row'),
              ),
            ),
          ),
        ),
        GoRoute(path: '/pro/onboarding', builder: real.builder),
      ],
    );
  }

  /// [withAreas]: MyWeli's area tree in the widget tree, as the app has it
  /// (`main_pro.dart`) — R8's lookup. Without it the profile step keeps the
  /// three-field rule.
  Future<({ProAuthProvider auth, GoRouter router})> pumpScreen(
    WidgetTester tester, {
    bool withAreas = false,
    String at = '/pro/onboarding',
    String? notice,
    int rounds = 9,
  }) async {
    final auth = await signInPro(tester);
    // The sign-in's « Mes salons » load, landed in real time: a publish's
    // re-read waits for a load already out (B0.18 §6.2), and that one's
    // timer is not the test clock's.
    await tester.runAsync(auth.rereadMySalons);
    pro.switchProbes.clear();
    final router = routerAt(at, notice: notice);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          // Tracked, as the app tracks it (main_pro.dart): a switch resets it.
          ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProOnboardingProvider()),
          ),
          if (withAreas)
            ChangeNotifierProvider(create: (_) => LocalityProvider()),
        ],
        routerConfig: router,
      ),
    );
    // services → staff → hours → deposit → listing → KYC: six mock calls
    // (« Mes salons » and the tree, when there is one, beside them; one
    // more for a validated salon's offer read).
    await settleMocks(tester, rounds: rounds);
    return (auth: auth, router: router);
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.scrollUntilVisible(button, 200);
    await tester.tap(button);
    // The publish and its offer read; then, on a success, the session's two
    // re-reads (B0.18 §6.2: /me/provider and /me/salons, side by side) and,
    // where the answer does not carry the state, the screen's own.
    await settleMocks(tester, rounds: 5);
  }

  ElevatedButton? buttonOf(WidgetTester tester, String label) {
    final f = find.ancestor(
      of: find.text(label),
      matching: find.byType(ElevatedButton),
    );
    return f.evaluate().isEmpty ? null : tester.widget<ElevatedButton>(f);
  }

  /// The list's end on screen. The action area is the list's last item, and
  /// a child built in the cache but not on screen is « offstage » to a
  /// default finder — an absence asserted without this would be vacuous.
  Future<void> scrollToEnd(WidgetTester tester) async {
    final list = find.byType(ListView);
    if (list.evaluate().isEmpty) return;
    await tester.drag(list.first, const Offset(0, -4000));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// [label] is the one action on screen — at the list's end, where it
  /// sits — and the other four are nowhere in the tree.
  Future<void> expectOnlyButton(WidgetTester tester, String? label) async {
    await scrollToEnd(tester);
    for (final l in _allButtons) {
      expect(
        find.text(l, skipOffstage: false),
        l == label ? findsOneWidget : findsNothing,
        reason: '« $l »',
      );
    }
  }

  /// The banner's tone — as the website (web-salon-validation.md §4.1): a
  /// request waiting neutral, a refusal and a suspension errors, offline a
  /// warning; each with its glyph (SYSTEM.md §13.6).
  void expectBannerTone(WidgetTester tester, Color color, IconData icon) {
    final banner = tester.widget<StatusBanner>(find.byType(StatusBanner));
    expect(banner.color, color);
    expect(banner.icon, icon);
  }

  /// What the checklist and its feedback may never say or offer (§2.1).
  void expectNoOfferChoice() {
    for (final f in [
      find.textContaining('Choisissez votre offre'),
      find.textContaining('mois offerts'),
      find.text('Choisir'),
      find.byType(SnackBarAction),
    ]) {
      expect(f, findsNothing, reason: '$f');
    }
  }

  String where(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  group('a state each (§6.1)', () {
    testWidgets('never asked: no banner, the checklist, and « Demander la '
        'mise en ligne » enabled with every server gate met — no offer '
        'chosen', (tester) async {
      MockData.seedNeverAsked(_p1);
      await pumpScreen(tester);

      expect(find.text('Profil de l’entreprise'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.requestButton),
        200,
      );
      await expectOnlyButton(tester, SalonValidationCopy.requestButton);
      expect(
        buttonOf(tester, SalonValidationCopy.requestButton)?.onPressed,
        isNotNull,
      );
      expect(
        find.text(SalonValidationCopy.requestHint, skipOffstage: false),
        findsNothing,
      );
      for (final title in [
        SalonValidationCopy.pendingTitle,
        SalonValidationCopy.refusedTitle,
        SalonValidationCopy.offlineTitle,
        SalonValidationCopy.suspendedTitle,
      ]) {
        expect(find.text(title), findsNothing, reason: title);
      }
      expectNoOfferChoice();
    }, variant: bothPlatforms);

    testWidgets('never asked, a step still to do: the button off, and the '
        'hint names the request', (tester) async {
      MockData.seedNeverAsked(_p1);
      pro.thirdPhoto = false;
      await pumpScreen(tester);

      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.requestHint),
        200,
      );
      expect(
        buttonOf(tester, SalonValidationCopy.requestButton)?.onPressed,
        isNull,
      );
      expect(
        find.text(SalonValidationCopy.legacyHint, skipOffstage: false),
        findsNothing,
      );
    }, variant: bothPlatforms);

    testWidgets('pending: the banner above the steps, « Demande envoyée le '
        '13 novembre 2026 » — the day in the SALON\'s clock — in place of '
        'the button, every step still open', (tester) async {
      // A salon in Lagos (UTC+1): 23:30 UTC on the 12th is already the 13th
      // there — and still the 12th in Abidjan, the fallback clock.
      final i = MockData.providers.indexWhere((p) => p.id == 'provider1');
      final original = MockData.providers[i];
      MockData.providers[i] = original.copyWith(timezone: 'Africa/Lagos');
      addTearDown(() => MockData.providers[i] = original);
      MockData.seedPendingRequest(
        _p1,
        submittedAt: DateTime.utc(2026, 11, 12, 23, 30),
      );
      await pumpScreen(tester);

      expect(find.text(SalonValidationCopy.pendingTitle), findsOneWidget);
      expect(find.text(SalonValidationCopy.pendingText), findsOneWidget);
      expectBannerTone(tester, AppColors.textSecondary, Icons.schedule);
      expect(
        tester.getTopLeft(find.text(SalonValidationCopy.pendingTitle)).dy,
        lessThan(tester.getTopLeft(find.text('Profil de l’entreprise')).dy),
        reason: 'the banner sits above the steps (§6.2)',
      );
      // The steps stay editable while the request waits (§6.2).
      final profileRow = find.ancestor(
        of: find.text('Profil de l’entreprise'),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(profileRow).onTap, isNotNull);

      const sent = 'Demande envoyée le 13 novembre 2026';
      await tester.scrollUntilVisible(find.text(sent), 200);
      expect(find.text(sent), findsOneWidget);
      await expectOnlyButton(tester, null);
      expect(find.text('Aperçu de ma page'), findsOneWidget);
    }, variant: bothPlatforms);

    testWidgets('approved, not yet live (the admin\'s validation finishing): '
        'read as a request waiting', (tester) async {
      MockData.seedFinishing(_p1);
      await pumpScreen(tester);

      expect(find.text(SalonValidationCopy.pendingTitle), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Aperçu de ma page'), 200);
      expect(
        find.textContaining(SalonValidationCopy.requestSentOnPrefix),
        findsOneWidget,
      );
      await expectOnlyButton(tester, null);
    }, variant: bothPlatforms);

    // §4.3's reasons: each code's sentence, the admin's note on its own
    // line, what to do next, and the button to ask again.
    for (final code in ['incomplete_info', 'photos', 'unconfirmed', 'other']) {
      testWidgets('refused ($code): the reason, the note on its own line, '
          '« Modifiez votre salon… » and « Renvoyer pour validation »', (
        tester,
      ) async {
        MockData.seedRefused(_p1, code: code, note: _note);
        await pumpScreen(tester);

        expect(find.text(SalonValidationCopy.refusedTitle), findsOneWidget);
        expectBannerTone(tester, AppColors.error, Icons.error_outline);
        final sentence = SalonValidationCopy.refusalSentences[code];
        if (sentence != null) {
          expect(find.text(sentence), findsOneWidget);
        } else {
          // `other`: the note alone is the reason.
          for (final s in SalonValidationCopy.refusalSentences.values) {
            if (s != null) expect(find.text(s), findsNothing);
          }
        }
        // Its own `Text` — its own line, never joined to the sentence.
        expect(find.text(_note), findsOneWidget);
        expect(find.text(SalonValidationCopy.resubmit), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text(SalonValidationCopy.resubmitButton),
          200,
        );
        await expectOnlyButton(tester, SalonValidationCopy.resubmitButton);
        expect(
          buttonOf(tester, SalonValidationCopy.resubmitButton)?.onPressed,
          isNotNull,
        );
      }, variant: bothPlatforms);
    }

    for (final code in ['outside_ci', 'test_salon']) {
      testWidgets('refused for good ($code): the reason and the note, no '
          '« Modifiez… », no button at all', (tester) async {
        MockData.seedRefused(_p1, code: code, note: _note);
        await pumpScreen(tester);

        expect(find.text(SalonValidationCopy.refusedTitle), findsOneWidget);
        expect(
          find.text(SalonValidationCopy.refusalSentences[code]!),
          findsOneWidget,
        );
        expect(find.text(_note), findsOneWidget);
        expect(find.text(SalonValidationCopy.resubmit), findsNothing);
        await tester.scrollUntilVisible(find.text('Aperçu de ma page'), 200);
        await expectOnlyButton(tester, null);
        expect(
          find.text(SalonValidationCopy.requestHint, skipOffstage: false),
          findsNothing,
        );
      }, variant: bothPlatforms);
    }

    testWidgets('live: no banner, no button — the checklist as today', (
      tester,
    ) async {
      await pumpScreen(tester); // provider1: live, validated (0044 mirror)

      expect(find.text('Profil de l’entreprise'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Aperçu de ma page'), 200);
      await expectOnlyButton(tester, null);
      expect(find.text(SalonValidationCopy.offlineTitle), findsNothing);
      expect(find.text(SalonValidationCopy.refusedTitle), findsNothing);
    }, variant: bothPlatforms);

    testWidgets('no longer online, its offer lapsed: « Mon abonnement »\'s '
        'sentence, and « Mon abonnement » opens that screen — a pointer, '
        'never a choice', (tester) async {
      MockData.seedOffline(_p1); // no offer row: `offerLive` false
      final (:auth, router: _) = await pumpScreen(tester);

      expect(find.text(SalonValidationCopy.offlineTitle), findsOneWidget);
      expect(find.text(salonUnpublishedForBillingMessage), findsOneWidget);
      expectBannerTone(tester, AppColors.warning, Icons.warning_amber);
      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.billingPointer),
        200,
      );
      await expectOnlyButton(tester, SalonValidationCopy.billingPointer);
      expectNoOfferChoice();

      await tester.tap(find.text(SalonValidationCopy.billingPointer));
      await tester.pumpAndSettle();
      expect(find.text('stub subscription'), findsOneWidget);
      expect(auth.activeSalonId, _p1);
    }, variant: bothPlatforms);

    testWidgets('no longer online, its offer live: « Remettre en ligne » '
        'answers 200 — « 🎉 », and the salon reads live', (tester) async {
      MockData.seedOffline(_p1);
      expect(subs.startTrialIfAbsent(_p1, tier: SalonTier.pro), isTrue);
      await pumpScreen(tester);

      expect(find.text(SalonValidationCopy.offlineTitle), findsOneWidget);
      expect(
        find.text(SalonValidationCopy.offlineRepublishText),
        findsOneWidget,
      );
      await tapButton(tester, SalonValidationCopy.republishButton);

      expect(find.text(SalonValidationCopy.wentLive), findsOneWidget);
      expect(find.text(SalonValidationCopy.requestSent), findsNothing);
      expect(find.text(SalonValidationCopy.offlineTitle), findsNothing);
      await expectOnlyButton(tester, null);
    }, variant: bothPlatforms);

    testWidgets('suspended: the banner alone — no checklist, no preview, no '
        'button (decision 136 item 9)', (tester) async {
      MockData.seedSuspended(_p1);
      await pumpScreen(tester);

      expect(find.text(SalonValidationCopy.suspendedTitle), findsOneWidget);
      expect(find.text(SalonValidationCopy.suspendedText), findsOneWidget);
      expectBannerTone(tester, AppColors.error, Icons.error_outline);
      expect(find.text('Profil de l’entreprise'), findsNothing);
      expect(find.textContaining('étape'), findsNothing);
      expect(find.text('Aperçu de ma page'), findsNothing);
      await expectOnlyButton(tester, null);
    }, variant: bothPlatforms);

    testWidgets('a server from before B0.18 (no validation key): today\'s '
        'screen, today\'s words (decision 136 item 10)', (tester) async {
      MockData.seedNeverAsked(_p1);
      pro.legacyServer = true;
      pro.thirdPhoto = false;
      await pumpScreen(tester);

      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.legacyHint),
        200,
      );
      await expectOnlyButton(tester, SalonValidationCopy.legacyButton);
      expect(
        find.text(SalonValidationCopy.requestHint, skipOffstage: false),
        findsNothing,
      );
      expect(find.text(SalonValidationCopy.pendingTitle), findsNothing);
    }, variant: bothPlatforms);
  });

  group('the publish\'s answer (§6.1 « After a request »)', () {
    // B0.18 (salon-go-live-approval §3.1, §3.6, §6.5): the publish is a
    // request — it starts no trial; MyWeli's validation starts the salon's
    // one trial. Replaces « the first publish goes live and the mock starts
    // the trial », watched red on the new mock first (the trial read null).
    testWidgets('a salon that never asked: « Demande envoyée. Nous vous '
        'préviendrons de la décision. », never « 🎉 »; the request waits and '
        'starts no trial; MyWeli\'s validation starts the trial on Pro and '
        'takes the salon live (§3.1, §3.6)', (tester) async {
      freezeClock(DateTime.utc(2026, 11, 13, 9, 30));
      MockData.seedNeverAsked(_p1);
      await pumpScreen(tester);
      await tapButton(tester, SalonValidationCopy.requestButton);

      expect(find.text(SalonValidationCopy.requestSent), findsOneWidget);
      expect(find.text(SalonValidationCopy.wentLive), findsNothing);
      // The screen took the 202's state at once: the date where the button
      // was (the banner above pushed it down), the banner above the steps.
      const sent = 'Demande envoyée le 13 novembre 2026';
      await tester.scrollUntilVisible(find.text(sent), 200);
      expect(find.text(sent), findsOneWidget);
      await expectOnlyButton(tester, null);
      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.pendingTitle),
        -200,
      );

      expect(
        MockData.salonValidations[_p1]?.state,
        SalonValidationState.pending,
      );
      expect(MockData.salonStatuses[_p1], 'draft');
      late ApiResponse<SalonSubscription> offer;
      await tester.runAsync(() async {
        offer = await subs.getSalonSubscription(_p1);
      });
      expect(offer.code, 'no_offer', reason: 'a request starts no trial');

      // The admin validates.
      await tester.runAsync(() async {
        expect((await pro.validateSalonForTests(_p1)).success, isTrue);
        offer = await subs.getSalonSubscription(_p1);
      });
      expect(offer.data?.status, SalonOfferStatus.trial);
      expect(offer.data?.tier, SalonTier.pro);
      expect(MockData.salonStatuses[_p1], isNull);
      expect(MockData.salonValidations[_p1]?.wentLive, isTrue);
    }, variant: bothPlatforms);

    testWidgets('a 200 (live at once): « 🎉 Votre profil est en ligne ! », '
        'never « Demande envoyée »', (tester) async {
      MockData.seedNeverAsked(_p1);
      pro.publishAnswer = ApiResponse.success(const PublishOutcome.live());
      await pumpScreen(tester);
      await tapButton(tester, SalonValidationCopy.requestButton);

      expect(find.text(SalonValidationCopy.wentLive), findsOneWidget);
      expect(find.text(SalonValidationCopy.requestSent), findsNothing);
      await expectOnlyButton(tester, null);
    }, variant: bothPlatforms);

    testWidgets('a 202 MyWeli refused at that very moment: no « Demande '
        'envoyée », the refusal shown (decision 136 item 7)', (tester) async {
      MockData.seedNeverAsked(_p1);
      pro.publishAnswer = ApiResponse.success(
        PublishOutcome.requested(
          SalonValidation(
            state: SalonValidationState.refused,
            wentLive: false,
            submittedAt: DateTime.utc(2026, 11, 13, 9),
            decidedAt: DateTime.utc(2026, 11, 13, 9, 1),
            refusal: const SalonRefusal(code: 'photos', isFinal: false),
          ),
        ),
      );
      await pumpScreen(tester);
      await tapButton(tester, SalonValidationCopy.requestButton);

      expect(find.byType(SnackBar), findsNothing);
      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.refusedTitle),
        -200,
      );
      expect(
        find.text(SalonValidationCopy.refusalSentences['photos']!),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.resubmitButton),
        200,
      );
      await expectOnlyButton(tester, SalonValidationCopy.resubmitButton);
    }, variant: bothPlatforms);

    testWidgets('a 202 whose request vanished (`validation: null`): nothing '
        'said, the state shown (decision 136 item 7)', (tester) async {
      MockData.seedNeverAsked(_p1);
      pro.publishAnswer = ApiResponse.success(
        const PublishOutcome.requested(null),
      );
      await pumpScreen(tester);
      await tapButton(tester, SalonValidationCopy.requestButton);

      expect(find.byType(SnackBar), findsNothing);
      await expectOnlyButton(tester, SalonValidationCopy.requestButton);
    }, variant: bothPlatforms);

    testWidgets('a stale button hit by a 409 validation_refused_final: '
        '« Mise en ligne refusée », then the screen re-reads and shows the '
        'refusal, with no button (decision 136 item 2)', (tester) async {
      MockData.seedNeverAsked(_p1);
      await pumpScreen(tester);
      // MyWeli refused for good while the screen was open.
      MockData.seedRefused(_p1, code: 'outside_ci', note: _note);
      await tapButton(tester, SalonValidationCopy.requestButton);

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(SalonValidationCopy.refusedFinalMessage),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.refusalSentences['outside_ci']!),
        -200,
      );
      expect(find.text(_note), findsOneWidget);
      await expectOnlyButton(tester, null);
    }, variant: bothPlatforms);

    testWidgets('a publish refused by the offer gate (EXPIRED offer): the '
        'neutral sentence and NO action', (tester) async {
      MockData.seedNeverAsked(_p1);
      // A stale sentence from the service: the screen must not echo it.
      pro.publishAnswer = ApiResponse.error(
        'Ancienne phrase du serveur.',
        code: 'offer_required',
      );
      await pumpScreen(tester);
      await tapButton(tester, SalonValidationCopy.requestButton);

      expect(find.text(publishOfferInactiveMessage), findsOneWidget);
      expect(find.text('Ancienne phrase du serveur.'), findsNothing);
      expectNoOfferChoice();
    }, variant: bothPlatforms);

    testWidgets('the demo account\'s lock reads as itself, not « Une erreur '
        'est survenue »', (tester) async {
      MockData.seedNeverAsked(_p1);
      pro.publishAnswer = ApiResponse.error(
        demoAccountLockedMessage,
        code: 'demo_account_locked',
      );
      await pumpScreen(tester);
      await tapButton(tester, SalonValidationCopy.requestButton);

      expect(find.text(demoAccountLockedMessage), findsOneWidget);
      expectNoOfferChoice();
    }, variant: bothPlatforms);
  });

  // « Configuration » loading is a refresh point (§6.2): a state MyWeli
  // moved since the session last read it reaches the home card's copy.
  testWidgets('a decision taken since the sign-in reaches the home card\'s '
      'copy when « Configuration » loads — and only then is /me/provider '
      'read twice', (tester) async {
    MockData.seedPendingRequest(_p1);
    final auth = await signInPro(tester);
    await tester.runAsync(auth.rereadMySalons);
    expect(auth.salonGoLiveState?.name, 'pending');
    MockData.seedRefused(_p1, code: 'photos');

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProOnboardingProvider()),
        ],
        routerConfig: routerAt('/pro/onboarding'),
      ),
    );
    await settleMocks(tester, rounds: 10);

    expect(find.text(SalonValidationCopy.refusedTitle), findsOneWidget);
    expect(auth.salonGoLiveState?.name, 'refused', reason: 'the card');
    final row = auth.salons.firstWhere((s) => s.salonId == _p1);
    expect(row.validation?.state, SalonValidationState.refused);
  });

  // The notice (salon-go-live-approval §5.2) carries
  // `/pro/onboarding?salon={id}`. Two paths reach it, tested apart (§8.3):
  // the feed row pushes the route as it came; a tapped push switches FIRST
  // (`ensureSalon`, main_pro.dart) and falls back on its own.
  group('the notice tap (?salon=)', () {
    testWidgets('the feed row, for the salon the owner is NOT on: it '
        'switches once, shows nothing of the other salon meanwhile, then '
        'shows MyWeli\'s decision', (tester) async {
      MockData.seedPendingRequest(_p1);
      MockData.seedRefused(_p2, code: 'photos', note: _note);
      final (:auth, router: _) = await pumpScreen(
        tester,
        at: '/pro/notifications',
        notice: '/pro/onboarding?salon=provider2',
        rounds: 1,
      );
      expect(auth.activeSalonId, _p1);
      // « Configuration » was opened on provider1 earlier: the app-wide
      // store holds ITS state when the notice about provider2 is tapped.
      final store = Provider.of<ProOnboardingProvider>(
        tester.element(find.text('the notice row')),
        listen: false,
      );
      await tester.runAsync(() => store.load(auth.provider!, salonId: _p1));
      expect(store.salonGoLiveState?.name, 'pending');

      await tester.tap(find.text('the notice row'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ProOnboardingScreen), findsOneWidget);
      expect(
        find.text(SalonValidationCopy.pendingTitle),
        findsNothing,
        reason: 'provider1\'s state, under the notice about provider2',
      );
      expect(find.text('Profil de l’entreprise'), findsNothing);
      await settleMocks(tester, rounds: 10);

      expect(auth.activeSalonId, _p2);
      expect(pro.switchProbes, [_p2]);
      expect(
        tester
            .widget<ProOnboardingScreen>(find.byType(ProOnboardingScreen))
            .salonId,
        _p2,
        reason: 'the route handed the screen its `?salon=`',
      );
      expect(find.text(SalonValidationCopy.refusedTitle), findsOneWidget);
      expect(
        find.text(SalonValidationCopy.refusalSentences['photos']!),
        findsOneWidget,
      );
      expect(find.text(_note), findsOneWidget);

      // A rebuild later, still the one switch.
      auth.notifyListeners();
      await settleMocks(tester, rounds: 3);
      expect(pro.switchProbes, [_p2]);
    }, variant: bothPlatforms);

    testWidgets('the feed row, for the salon the owner is on: nothing to '
        'switch', (tester) async {
      MockData.seedPendingRequest(_p1);
      await pumpScreen(tester, at: '/pro/onboarding?salon=provider1');

      expect(pro.switchProbes, isEmpty);
      expect(find.text(SalonValidationCopy.pendingTitle), findsOneWidget);
    });

    for (final (fault, sentence) in [
      (_SwitchFault.refused, salonSwitchRefusedMessage),
      (_SwitchFault.network, kNoConnectionMessage),
      (_SwitchFault.keepsOld, salonSwitchRefusedMessage),
    ]) {
      testWidgets('the feed row, a switch that does not happen '
          '(${fault.name}): « Accueil », with « $sentence », once', (
        tester,
      ) async {
        pro.switchFault = fault;
        final (:auth, :router) = await pumpScreen(
          tester,
          at: '/pro/notifications',
          notice: '/pro/onboarding?salon=provider2',
          rounds: 1,
        );

        await tester.tap(find.text('the notice row'));
        await settleMocks(tester, rounds: 10);

        expect(where(router), '/pro/dashboard');
        expect(find.text('stub home'), findsOneWidget);
        expect(find.text(sentence), findsOneWidget);
        expect(find.byType(ProOnboardingScreen), findsNothing);
        expect(pro.switchProbes, [_p2], reason: 'never a loop');
        if (fault != _SwitchFault.keepsOld) {
          expect(auth.activeSalonId, _p1);
        }
        await settleMocks(tester, rounds: 3);
        expect(pro.switchProbes, [_p2]);
      }, variant: bothPlatforms);
    }

    testWidgets('a tapped push: `ensureSalon` switches before the route '
        'opens, and the screen does not switch again', (tester) async {
      MockData.seedRefused(_p2, code: 'unconfirmed');
      final (:auth, :router) = await pumpScreen(
        tester,
        at: '/pro/dashboard',
        rounds: 1,
      );
      final handler = PushMessageHandler(
        // main_pro.dart's wiring (`landedPushHandler`).
        navigate: (route) async => unawaited(router.push<void>(route)),
        allowedRoutePrefixes: kProRoutePrefixes,
        ensureSalon: auth.switchSalon,
        salonSwitchFallbackRoute: '/pro/dashboard',
      );

      final handled = handler.handleData({
        'event': 'salon.validation.refused',
        'providerId': 'provider2',
        'route': '/pro/onboarding?salon=provider2',
      });
      await settleMocks(tester, rounds: 3);
      await handled;
      await settleMocks(tester, rounds: 10);

      expect(auth.activeSalonId, _p2);
      expect(pro.switchProbes, [_p2], reason: 'the push switched; not twice');
      expect(find.text(SalonValidationCopy.refusedTitle), findsOneWidget);
      expect(
        find.text(SalonValidationCopy.refusalSentences['unconfirmed']!),
        findsOneWidget,
      );
    }, variant: bothPlatforms);

    testWidgets('a tapped push whose switch is refused: its own fallback, '
        '« Accueil » — « Configuration » never opens', (tester) async {
      pro.switchFault = _SwitchFault.refused;
      final (:auth, :router) = await pumpScreen(
        tester,
        at: '/pro/staff',
        rounds: 1,
      );
      final handler = PushMessageHandler(
        navigate: (route) async => unawaited(router.push<void>(route)),
        allowedRoutePrefixes: kProRoutePrefixes,
        ensureSalon: auth.switchSalon,
        salonSwitchFallbackRoute: '/pro/dashboard',
      );

      final handled = handler.handleData({
        'event': 'salon.validation.approved',
        'providerId': 'provider2',
        'route': '/pro/onboarding?salon=provider2',
      });
      await settleMocks(tester, rounds: 3);
      await handled;
      await settleMocks(tester, rounds: 3);

      expect(find.text('stub home'), findsOneWidget);
      expect(find.byType(ProOnboardingScreen), findsNothing);
      expect(pro.switchProbes, [_p2]);
      expect(auth.activeSalonId, _p1);
    });
  });

  testWidgets('a salon that never chose its deposit reads « Facultatif » on '
      '« Acompte & annulation » (B7.7, decision 24)', (tester) async {
    // The server's defaults for a salon that never saved: off, 0 %.
    final i = MockData.providers.indexWhere((p) => p.id == 'provider1');
    final original = MockData.providers[i];
    MockData.providers[i] = original.copyWith(depositPercentage: 0);
    addTearDown(() => MockData.providers[i] = original);
    await pumpScreen(tester);

    final step = find.text('Acompte & annulation');
    await tester.scrollUntilVisible(step, 200);
    expect(find.text('Facultatif'), findsOneWidget);
  });

  testWidgets('CONTROL — a saved choice (off, at the form\'s 30 %) reads no '
      '« Facultatif »', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Acompte & annulation'), 200);
    expect(find.text('Facultatif'), findsNothing);
  });

  // R8 (salon-go-live-approval §6.3, decision 136 item 4): the server takes
  // a commune typed by hand only when it names one of MyWeli's areas.
  group('R8 — « Profil de l’entreprise » and a commune typed by hand', () {
    const fromList = 'Choisissez la commune dans la liste';

    /// provider1 as a legacy row that never asked: no area, a commune of no
    /// area.
    void handTypedCommune(String commune) {
      MockData.seedNeverAsked(_p1);
      final i = MockData.providers.indexWhere((p) => p.id == 'provider1');
      final original = MockData.providers[i];
      MockData.providers[i] = model.Provider.fromJson({
        ...original.toJson(),
        'areaId': null,
        'commune': commune,
      });
      addTearDown(() => MockData.providers[i] = original);
    }

    testWidgets('a commune of no area: the sub-line under the step, the step '
        'to do, the button off', (tester) async {
      handTypedCommune('Quartier des Artistes');
      await pumpScreen(tester, withAreas: true);

      final row = find.ancestor(
        of: find.text('Profil de l’entreprise'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: row, matching: find.text(fromList)),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.requestButton),
        200,
      );
      expect(
        buttonOf(tester, SalonValidationCopy.requestButton)?.onPressed,
        isNull,
      );
    }, variant: bothPlatforms);

    testWidgets('CONTROL — a legacy commune that names an area (« cocody »): '
        'done, no sub-line', (tester) async {
      handTypedCommune('cocody');
      await pumpScreen(tester, withAreas: true);

      expect(find.text(fromList), findsNothing);
      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.requestButton),
        200,
      );
      expect(
        buttonOf(tester, SalonValidationCopy.requestButton)?.onPressed,
        isNotNull,
      );
    });

    testWidgets('CONTROL — no tree in the widget tree: today\'s three-field '
        'rule, the server decides', (tester) async {
      handTypedCommune('Quartier des Artistes');
      await pumpScreen(tester);

      expect(find.text(fromList), findsNothing);
      await tester.scrollUntilVisible(
        find.text(SalonValidationCopy.requestButton),
        200,
      );
      expect(
        buttonOf(tester, SalonValidationCopy.requestButton)?.onPressed,
        isNotNull,
      );
    });
  });
}
