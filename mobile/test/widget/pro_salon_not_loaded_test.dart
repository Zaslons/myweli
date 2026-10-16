import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/journal_day.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/screens/provider/journal/pro_journal_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:myweli/widgets/provider/pro_salon_gate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/settle.dart';

/// The Pro app waits for its salon (docs/design/pro-app-salon-not-loaded.md).
///
/// `provider1` (the owner jean@'s salon) is moved to Libreville, UTC+1, for
/// every test: in Abidjan, UTC+0, a fallback to the default zone is invisible.
const _owner = 'jean@salon-excellence.test';

/// The appointment the journal shows: 09:00Z, 10:00 at a Libreville salon.
final _at = DateTime.utc(2030, 1, 15, 9);

class _Pro extends MockProService {
  bool meFails = false;

  /// Holds the next GET /me/provider until the test completes it.
  Completer<void>? holdNext;
  DateTime? sent;

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId}) async {
    final hold = holdNext;
    if (hold != null) {
      holdNext = null;
      await hold.future;
    }
    if (meFails) {
      return ApiResponse.error('Erreur serveur.', code: 'server_error');
    }
    return super.getMyProvider(salonId: salonId);
  }

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  ) async => ApiResponse.success(
    JournalDay(
      date: '2030-01-15',
      artists: const [],
      appointments: [
        Appointment(
          id: 'a1',
          userId: 'u1',
          providerId: 'provider1',
          serviceIds: const ['s1'],
          appointmentDate: _at,
          status: AppointmentStatus.confirmed,
          totalPrice: 10000,
          durationMinutes: 60,
          clientName: 'Koffi',
          createdAt: DateTime.utc(2030, 1, 1),
        ),
      ],
    ),
  );

  @override
  Future<ApiResponse<bool>> rescheduleAppointment(
    String appointmentId,
    DateTime newDateTime,
  ) async {
    sent = newDateTime;
    return ApiResponse.success(true);
  }
}

/// A Pro page that reads the salon's clock the way every Pro screen does —
/// and says which clock it found when it was first built.
class _ClockPage extends StatefulWidget {
  const _ClockPage();

  static final mounts = <String?>[];

  @override
  State<_ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<_ClockPage> {
  @override
  void initState() {
    super.initState();
    _ClockPage.mounts.add(context.read<ProAuthProvider>().salonTimezone);
  }

  @override
  Widget build(BuildContext context) {
    final tz = context.watch<ProAuthProvider>().salonTimezone;
    return Scaffold(
      body: Text('PAGE ${Formatters.formatTime(toSalonTime(_at, tz: tz))}'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pro = _Pro();
  final auth = MockAuthService();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.proService = pro;
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(() {
    freezeClock(DateTime.utc(2030, 1, 15, 6));
    pro
      ..meFails = false
      ..holdNext = null
      ..sent = null;
    _ClockPage.mounts.clear();
    final i = MockData.providers.indexWhere((p) => p.id == 'provider1');
    final original = MockData.providers[i];
    MockData.providers[i] = original.copyWith(
      countryCode: 'GA',
      timezone: 'Africa/Libreville',
      currency: 'XAF',
    );
    addTearDown(() => MockData.providers[i] = original);
  });

  /// A stored owner session — what the next [ProAuthProvider] cold-starts
  /// on. [withFacts] false = a session stored before the salon's facts were
  /// kept with it.
  Future<void> storedSession(WidgetTester tester, {bool withFacts = true}) =>
      tester.runAsync(() async {
        await auth.logoutProvider();
        final first = ProAuthProvider();
        await first.ready;
        await first.requestEmailOtp(_owner);
        final ok = await first.verifyEmailOtp(_owner, first.emailDevCode!);
        expect(ok, isTrue);
        if (!withFacts) await auth.cacheProviderSalonMarket(null);
      });

  group('the journal on a cold start whose /me fails (the reproduced '
      'defect)', () {
    Future<void> pumpJournal(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/pro/journal',
        routes: [
          GoRoute(
            path: '/pro/journal',
            builder: (_, _) => const ProJournalScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        wrapApp(
          providers: [
            ChangeNotifierProvider(create: (_) => ProAuthProvider()),
            ChangeNotifierProvider(create: (_) => ProJournalProvider()),
          ],
          routerConfig: router,
        ),
      );
      await settleMocks(tester, rounds: 4);
    }

    /// « Reprogrammer » → the 16th → 11:00 → Confirmer.
    Future<void> rescheduleTo11On16(WidgetTester tester) async {
      await tester.longPress(find.text('Koffi'));
      await settleMocks(tester);
      await tester.tap(find.text('Reprogrammer'));
      await settleMocks(tester);
      await tester.tap(find.text('16').last); // the picker's, not the strip's
      await settleMocks(tester);
      final eleven = find.descendant(
        of: find.byType(Scrollable).at(0), // Heures
        matching: find.text('11'),
      );
      await tester.ensureVisible(eleven);
      await tester.pump();
      await tester.tap(eleven);
      await settleMocks(tester);
      await tester.tap(find.text('Confirmer'));
      await settleMocks(tester, rounds: 2);
    }

    for (final meFails in [false, true]) {
      testWidgets(
        meFails
            ? '/me fails: the card and « Reprogrammer » keep the salon\'s '
                  'clock from the session'
            : 'control, /me answers: the salon\'s clock (proves the test sees '
                  'the timezone)',
        (tester) async {
          await storedSession(tester);
          pro.meFails = meFails;

          await pumpJournal(tester);

          // The card reads « start » and « end »: 10:00–11:00 at the salon,
          // 09:00–10:00 on the Abidjan fallback.
          expect(
            find.text('09:00'),
            findsNothing,
            reason: '09:00Z is 10:00 in Libreville — 09:00 is Abidjan',
          );
          expect(find.text('10:00'), findsOneWidget);
          expect(find.text('11:00'), findsOneWidget);
          await rescheduleTo11On16(tester);
          expect(
            pro.sent,
            DateTime.utc(2030, 1, 16, 10),
            reason:
                '11:00 at the salon is 10:00Z; 11:00Z is noon there — the '
                'hour-off write the Abidjan fallback made',
          );
        },
      );
    }
  });

  group('ProSalonGate', () {
    late GoRouter router;

    Future<void> pumpGated(
      WidgetTester tester, {
      String at = '/pro/dashboard',
    }) async {
      router = GoRouter(
        initialLocation: at,
        routes: [
          GoRoute(path: '/pro/splash', builder: (_, _) => const Text('SPLASH')),
          GoRoute(
            path: '/pro/login',
            builder: (_, _) => const Scaffold(body: Text('LOGIN')),
          ),
          GoRoute(
            path: '/pro/invitations',
            builder: (_, _) => const Scaffold(body: Text('INVITATIONS')),
          ),
          GoRoute(
            path: '/pro/dashboard',
            builder: (_, _) => const _ClockPage(),
          ),
        ],
      );
      await tester.pumpWidget(
        wrapApp(
          providers: [ChangeNotifierProvider(create: (_) => ProAuthProvider())],
          routerConfig: router,
          builder: (context, child) => ProSalonGate(
            router: router,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      );
    }

    ProAuthProvider authOf(WidgetTester tester) =>
        tester.element(find.byType(ProSalonGate)).read<ProAuthProvider>();

    testWidgets('a salon it cannot know replaces every Pro page — no page is '
        'built on a guessed clock', (tester) async {
      await storedSession(tester, withFacts: false);
      pro.meFails = true;

      await pumpGated(tester);
      await settleMocks(tester, rounds: 3);

      expect(authOf(tester).needsSalon, isTrue);
      expect(find.text('Impossible de charger votre salon'), findsOneWidget);
      expect(
        find.text(
          'Les heures de vos rendez-vous en dépendent. Vérifiez votre '
          'connexion, puis réessayez.',
        ),
        findsOneWidget,
      );
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.byTooltip('Déconnexion'), findsOneWidget);
      expect(find.textContaining('PAGE'), findsNothing);
      expect(_ClockPage.mounts, isEmpty, reason: 'not even built underneath');
    });

    testWidgets('« Réessayer » — the wait, then the page, built once on the '
        'salon\'s clock', (tester) async {
      await storedSession(tester, withFacts: false);
      pro.meFails = true;
      await pumpGated(tester);
      await settleMocks(tester, rounds: 3);

      pro
        ..meFails = false
        ..holdNext = Completer<void>();
      final hold = pro.holdNext!;
      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      expect(find.byType(LoadingIndicator), findsOneWidget);
      expect(find.text('Impossible de charger votre salon'), findsNothing);

      hold.complete();
      await settleMocks(tester, rounds: 2);

      expect(find.text('PAGE 10:00'), findsOneWidget);
      expect(find.text('Impossible de charger votre salon'), findsNothing);
      expect(_ClockPage.mounts, ['Africa/Libreville']);
    });

    testWidgets('« Réessayer » that fails again comes back to the message', (
      tester,
    ) async {
      await storedSession(tester, withFacts: false);
      pro.meFails = true;
      await pumpGated(tester);
      await settleMocks(tester, rounds: 3);

      await tester.tap(find.text('Réessayer'));
      await settleMocks(tester, rounds: 2);

      expect(find.text('Impossible de charger votre salon'), findsOneWidget);
      expect(find.byType(LoadingIndicator), findsNothing);
    });

    testWidgets('the first frame, before the session is read, is the wait', (
      tester,
    ) async {
      await storedSession(tester, withFacts: false);
      pro.meFails = true;

      await pumpGated(tester);
      await tester.pump(); // the mock's session read takes 50 ms

      expect(authOf(tester).sessionRestored, isFalse);
      expect(find.byType(LoadingIndicator), findsOneWidget);
      expect(find.text('Impossible de charger votre salon'), findsNothing);
      expect(_ClockPage.mounts, isEmpty);
      await settleMocks(tester, rounds: 3); // let the load end
    });

    testWidgets('a cold start still loading shows the wait, not the message', (
      tester,
    ) async {
      await storedSession(tester, withFacts: false);
      pro.holdNext = Completer<void>();
      final hold = pro.holdNext!;

      await pumpGated(tester);
      await settleMocks(tester);

      expect(find.byType(LoadingIndicator), findsOneWidget);
      expect(find.text('Impossible de charger votre salon'), findsNothing);
      expect(find.textContaining('PAGE'), findsNothing);

      hold.complete();
      await settleMocks(tester, rounds: 2);
      expect(find.text('PAGE 10:00'), findsOneWidget);
    });

    testWidgets('« Déconnexion » is the way out when retrying cannot help', (
      tester,
    ) async {
      await storedSession(tester, withFacts: false);
      pro.meFails = true;
      await pumpGated(tester);
      await settleMocks(tester, rounds: 3);

      await tester.tap(find.byTooltip('Déconnexion'));
      await settleMocks(tester, rounds: 2);

      expect(authOf(tester).isAuthenticated, isFalse);
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('the session\'s own salon facts open the page at once — '
        'before the refresh answers, and when it fails', (tester) async {
      await storedSession(tester);
      pro
        ..meFails = true
        ..holdNext = Completer<void>();
      final hold = pro.holdNext!;

      await pumpGated(tester);
      await settleMocks(tester, rounds: 3);

      expect(find.text('PAGE 10:00'), findsOneWidget, reason: '/me still out');
      expect(find.byType(LoadingIndicator), findsNothing);

      hold.complete();
      await settleMocks(tester, rounds: 2);
      expect(find.text('PAGE 10:00'), findsOneWidget, reason: '/me failed');
      expect(find.text('Impossible de charger votre salon'), findsNothing);
    });

    for (final exempt in ['/pro/splash', '/pro/login', '/pro/invitations']) {
      testWidgets('$exempt is not covered', (tester) async {
        await storedSession(tester, withFacts: false);
        pro.meFails = true;

        await pumpGated(tester, at: exempt);
        await settleMocks(tester, rounds: 3);

        expect(authOf(tester).needsSalon, isTrue);
        expect(find.text('Impossible de charger votre salon'), findsNothing);
        expect(find.byType(LoadingIndicator), findsNothing);
      });
    }

    testWidgets('the splash handing over to a Pro page brings the gate — '
        'the cold start past the splash deadline', (tester) async {
      await storedSession(tester, withFacts: false);
      pro.meFails = true;
      await pumpGated(tester, at: '/pro/splash');
      await settleMocks(tester, rounds: 3);
      expect(find.text('SPLASH'), findsOneWidget, reason: 'exempt');

      router.go('/pro/dashboard');
      await settleMocks(tester);

      expect(find.text('Impossible de charger votre salon'), findsOneWidget);
      expect(_ClockPage.mounts, isEmpty);
    });

    testWidgets('48px targets, and whole at 200 % text', (tester) async {
      await storedSession(tester, withFacts: false);
      pro.meFails = true;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();

      await pumpGated(tester);
      await settleMocks(tester, rounds: 3);

      expect(find.text('Impossible de charger votre salon'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester.takeException(), isNull, reason: 'no overflow at 200 %');
      semantics.dispose();
    });
  });

  test('main_pro.dart installs the gate above every route', () {
    final source = File('lib/main_pro.dart').readAsStringSync();
    final builder = RegExp(
      r'builder: \(context, child\) =>[\s\S]*?routerConfig: ProRouter\.router',
    ).firstMatch(source)?.group(0);
    expect(builder, isNotNull, reason: 'the MaterialApp.router builder moved');
    expect(builder, contains('ProSalonGate('));
    expect(builder, contains('router: ProRouter.router'));
  });
}
