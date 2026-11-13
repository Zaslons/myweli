import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/salon_membership_info.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:myweli/widgets/common/timed_cached_image.dart';
import 'package:myweli/widgets/provider/salon_picker_sheet.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

/// How the switch probe (`getMyProvider(salonId:)`) fails, the way the real
/// service does (docs/design/web-pro-no-connection-copy.md §5).
enum _Fault {
  /// No answer: `api_pro_service` → `code: 'network'`.
  network,

  /// An answer that could not be read: the decode throws.
  unreadable,

  /// A per-salon denial (uniform 403).
  refused,
}

/// The mock, with a switch probe that fails on demand — `serviceLocator`'s
/// fields are set once per file, so the fault is a field, not a new service.
class _FaultyProService extends MockProService {
  _Fault? fault;

  /// « Mes salons » as a server from before B0.18 answers it: no
  /// `validation` key on any row.
  bool legacyServer = false;

  @override
  Future<ApiResponse<MySalonsResult>> getMySalons() async {
    final res = await super.getMySalons();
    final data = res.data;
    if (!legacyServer || data == null) return res;
    return ApiResponse.success(
      MySalonsResult(
        canAddSalon: data.canAddSalon,
        items: [
          for (final s in data.items)
            SalonMembershipInfo(
              salonId: s.salonId,
              salonName: s.salonName,
              role: s.role,
              salonStatus: s.salonStatus,
              verified: s.verified,
              imageUrl: s.imageUrl,
            ),
        ],
      ),
    );
  }

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({SalonId? salonId}) async {
    final f = fault;
    if (salonId == null || f == null) {
      return super.getMyProvider(salonId: salonId);
    }
    switch (f) {
      case _Fault.network:
        return ApiResponse.error(
          'Connexion au serveur impossible',
          code: 'network',
        );
      case _Fault.unreadable:
        throw const FormatException('Unexpected end of input');
      case _Fault.refused:
        return ApiResponse.error(
          'Votre accès à ce salon a été retiré.',
          code: 'not_a_member',
        );
    }
  }
}

/// Team access R6b — the « Mes salons » switcher sheet: both memberships
/// render with role + state, the active salon carries the check, a tap
/// switches, and « Ajouter un salon » appears only when the gate is open.
void main() {
  final pro = _FaultyProService();
  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = pro;
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() async {
    pro.fault = null;
    pro.legacyServer = false;
    MockData.resetTeam();
    ProSalonScope.clear();
    (serviceLocator.subscriptionService as MockSubscriptionService)
        .resetForTests();
    await serviceLocator.authService.logoutProvider();
  });

  Future<ProAuthProvider> signInOwner(WidgetTester tester) async {
    late ProAuthProvider auth;
    await tester.runAsync(() async {
      auth = ProAuthProvider();
      await auth.requestEmailOtp('jean@salon-excellence.test');
      final ok = await auth.verifyEmailOtp(
        'jean@salon-excellence.test',
        auth.emailDevCode!,
      );
      expect(ok, isTrue, reason: 'owner login failed');
      // Poll (not a fixed sleep — the suite runs under load): the unawaited
      // post-login loadMySalons must land before the sheet opens.
      for (var i = 0; i < 100 && auth.salons.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(auth.salons, isNotEmpty, reason: 'salon list never loaded');
    });
    return auth;
  }

  /// Fire the mock-latency timers the sheet's refresh started (FakeAsync
  /// would otherwise flag them as pending at teardown — the R4b lesson).
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  Future<void> pumpPicker(WidgetTester tester, ProAuthProvider auth) async {
    await tester.pumpWidget(
      wrapApp(
        providers: [ChangeNotifierProvider<ProAuthProvider>.value(value: auth)],
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
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('lists both salons with roles; the active one is checked', (
    tester,
  ) async {
    final auth = await signInOwner(tester);
    await pumpPicker(tester, auth);

    expect(find.text('Mes salons'), findsOneWidget);
    expect(find.text('Salon Excellence'), findsOneWidget);
    expect(find.text('Beauté Divine'), findsOneWidget);

    // The rows render the salon's MARK when the wire carries one — the
    // `imageUrl` field was parsed and thrown away here since R6, an initial
    // rendering while the data sat in the model (salon-logo.md §"render").
    // Mock salons derive imageUrl from logoUrl ?? first gallery photo, the
    // server's own preference, so at least one row must show an image and
    // any row without one keeps its initial.
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(TimedCachedImage),
      ),
      findsWidgets,
      reason: 'a salon with a photo renders it, not its initial',
    );
    expect(find.text('Propriétaire'), findsNWidgets(2));
    expect(find.byIcon(Icons.check), findsOneWidget);
    // No live Réseau offer → no add row.
    expect(find.text('Ajouter un salon'), findsNothing);
    await drain(tester);
  });

  // hygiene-batch9.md §2.9 (B9.10) — a row is a title: « Salon », not an
  // empty line under an initial « ? ».
  testWidgets('a salon with no name reads « Salon » in the list', (
    tester,
  ) async {
    final i = MockData.providers.indexWhere((p) => p.id == 'provider2');
    final named = MockData.providers[i];
    MockData.providers[i] = named.copyWith(name: '');
    addTearDown(() => MockData.providers[i] = named);
    final auth = await signInOwner(tester);
    await pumpPicker(tester, auth);

    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('Salon')),
      findsOneWidget,
    );
    expect(find.text('?'), findsNothing);
    await drain(tester);
  });

  testWidgets('tapping the other salon switches and pops with its id', (
    tester,
  ) async {
    final auth = await signInOwner(tester);
    await pumpPicker(tester, auth);

    await tester.runAsync(() async {
      await tester.tap(find.text('Beauté Divine'));
      // Poll until the switch lands (two sequential mock calls inside).
      for (var i = 0; i < 100 && auth.activeSalonId != 'provider2'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(auth.activeSalonId, 'provider2');
    expect(auth.salonName, 'Beauté Divine');
    // The sheet closed.
    expect(find.text('Mes salons'), findsNothing);
    await drain(tester);
  });

  // docs/design/pro-app-login-only.md (B0.11, App Store 3.1.1): the app no
  // longer creates salons — a live Réseau owner adds one on the web.
  testWidgets('a live Réseau account sees no « Ajouter un salon » — salons '
      'are added on the web', (tester) async {
    final auth = await signInOwner(tester);
    await tester.runAsync(() async {
      // provider1 on a live Réseau offer (chosen on the web, in production —
      // the app never chooses one).
      expect(
        (serviceLocator.subscriptionService as MockSubscriptionService)
            .startTrialIfAbsent(SalonId('provider1'), tier: SalonTier.reseau),
        isTrue,
      );
      await auth.loadMySalons();
    });
    await pumpPicker(tester, auth);

    expect(find.text('Ajouter un salon'), findsNothing);
    expect(
      find.text('Offre Réseau — un salon de plus dans votre compte'),
      findsNothing,
    );
    await drain(tester);
  });

  // docs/design/web-pro-no-connection-copy.md §5 (owner decision A,
  // 2026-10-16): a switch that did not happen says why. Before, every failure
  // — a dropped connection included — read « … a peut-être été retiré. »,
  // suspecting a revoked access that had nothing to do with it.
  for (final (fault, sentence) in [
    (_Fault.network, 'Pas de connexion. Réessayez.'),
    (_Fault.unreadable, 'Pas de connexion. Réessayez.'),
    (
      _Fault.refused,
      'Changement impossible — votre accès à ce salon a peut-être été retiré.',
    ),
  ]) {
    testWidgets('a failed switch (${fault.name}) says « $sentence »; the '
        'sheet stays open on the current salon', (tester) async {
      final auth = await signInOwner(tester);
      await pumpPicker(tester, auth);
      pro.fault = fault;

      await tester.runAsync(() async {
        await tester.tap(find.text('Beauté Divine'));
        // The switch starts, then settles (the list refresh after it too).
        for (var i = 0; i < 20 && !auth.isLoading; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        for (var i = 0; i < 100 && auth.isLoading; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump();

      expect(find.text(sentence), findsOneWidget);
      expect(find.text('Mes salons'), findsOneWidget);
      expect(auth.activeSalonId, 'provider1');
      await drain(tester);
    });
  }

  // The other callers (the push's `ensureSalon`, the appointment detail,
  // « Ajouter un salon ») keep the bool: only a switch that happened is true.
  testWidgets('switchSalon stays false when there is no answer', (
    tester,
  ) async {
    final auth = await signInOwner(tester);
    pro.fault = _Fault.network;
    await tester.runAsync(() async {
      expect(await auth.switchSalon(SalonId('provider2')), isFalse);
      pro.fault = _Fault.unreadable;
      expect(await auth.switchSalon(SalonId('provider2')), isFalse);
    });
    expect(auth.activeSalonId, 'provider1');
  });

  // B0.18 (salon-go-live-approval §6.1 « Badge / row line », §6.2; decision
  // 136 item 8): the state on a line of its own, under the role, on EVERY
  // row — at 200% text a « role · state » line cut the state off
  // (test/a11y/salon_validation_layout_test.dart measures that).
  group('each row says where its salon stands', () {
    /// Jean manages Spa Relax too: a salon he does not own.
    void jeanManagesSpaRelax() => MockData.teamMembers.add(
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

    /// The row of [salonName] says [lines], in that order, each its own
    /// `Text`, and nothing else.
    void expectRow(WidgetTester tester, String salonName, List<String> lines) {
      final row = find.ancestor(
        of: find.text(salonName),
        matching: find.byType(ListTile),
      );
      final subtitle = tester.widget<ListTile>(row).subtitle!;
      final said = [
        for (final t
            in find
                .descendant(
                  of: find.byWidget(subtitle),
                  matching: find.byType(Text),
                )
                .evaluate())
          (t.widget as Text).data,
      ];
      expect(said, lines, reason: salonName);
    }

    testWidgets('owned or not: the role, then the state — « Plus en ligne » '
        'where the offer is not the account\'s to read', (tester) async {
      jeanManagesSpaRelax();
      MockData.seedPendingRequest(SalonId('provider1'));
      MockData.seedNeverAsked(SalonId('provider2'));
      MockData.seedOffline(SalonId('provider3'));
      final auth = await signInOwner(tester);
      await pumpPicker(tester, auth);

      expectRow(tester, 'Salon Excellence', [
        'Propriétaire',
        'En cours de validation',
      ]);
      expectRow(tester, 'Beauté Divine', [
        'Propriétaire',
        'Brouillon — pas encore en ligne',
      ]);
      expectRow(tester, 'Spa Relax', ['Manager', 'Plus en ligne']);
      await drain(tester);
    });

    testWidgets('live, refused, suspended', (tester) async {
      jeanManagesSpaRelax();
      MockData.seedRefused(SalonId('provider2'), code: 'outside_ci');
      MockData.seedSuspended(SalonId('provider3'));
      final auth = await signInOwner(tester);
      await pumpPicker(tester, auth);

      expectRow(tester, 'Salon Excellence', ['Propriétaire', 'En ligne']);
      expectRow(tester, 'Beauté Divine', [
        'Propriétaire',
        'Mise en ligne refusée',
      ]);
      expectRow(tester, 'Spa Relax', ['Manager', 'Suspendu']);
      await drain(tester);
    });

    testWidgets('a server from before B0.18: today\'s words — a draft says '
        'so, a live salon says nothing (decision 136 item 10)', (tester) async {
      MockData.seedNeverAsked(SalonId('provider2'));
      pro.legacyServer = true;
      final auth = await signInOwner(tester);
      await pumpPicker(tester, auth);

      expectRow(tester, 'Salon Excellence', ['Propriétaire']);
      expectRow(tester, 'Beauté Divine', [
        'Propriétaire',
        'Brouillon — pas encore en ligne',
      ]);
      await drain(tester);
    });
  });
}
