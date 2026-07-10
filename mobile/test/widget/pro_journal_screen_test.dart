import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/journal_day.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/screens/provider/journal/pro_journal_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Module `journal` J1b (docs/design/journal-j1b-app.md §4): « Ma journée » —
/// timeline cards, badges, gap slots, empty state.
class _StubProService extends MockProService {
  JournalDay? day;
  bool empty = false;

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  ) async {
    if (empty) {
      return ApiResponse.success(
        const JournalDay(date: '2026-07-13', artists: [], appointments: []),
      );
    }
    return ApiResponse.success(day!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final stub = _StubProService();

  Appointment appt({
    required String id,
    String status = 'confirmed',
    required String time,
    int minutes = 60,
    int noShow = 0,
    String? name,
  }) =>
      Appointment(
        id: id,
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDate: DateTime.parse('2026-07-13T$time:00.000Z'),
        status: AppointmentStatus.values.byName(status),
        totalPrice: 10000,
        durationMinutes: minutes,
        clientNoShowCount: noShow,
        clientName: name,
        createdAt: DateTime.parse('2026-07-13T08:00:00.000Z'),
      );

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = stub;
  });

  setUp(() {
    stub.empty = false;
    stub.day = JournalDay(
      date: '2026-07-13',
      artists: const [JournalArtist(id: 'ar1', name: 'Awa')],
      appointments: [
        appt(id: 'a1', time: '09:00', name: 'Koffi', noShow: 2),
        // a big gap → a « Libre » row between 10:00 and 14:00.
        appt(id: 'a2', time: '14:00', name: 'Aminata'),
      ],
    );
  });

  Widget app() {
    final router = GoRouter(
      initialLocation: '/pro/journal',
      routes: [
        GoRoute(
          path: '/pro/journal',
          builder: (_, __) => const ProJournalScreen(),
        ),
        GoRoute(
          path: '/pro/appointment/new',
          builder: (_, __) => const Scaffold(body: Text('MANUEL')),
        ),
        GoRoute(
          path: '/pro/appointment/:id',
          builder: (_, __) => const Scaffold(body: Text('DETAIL')),
        ),
        GoRoute(
          path: '/pro/appointments',
          builder: (_, __) => const Scaffold(body: Text('AGENDA')),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProAuthProvider()),
        ChangeNotifierProvider(create: (_) => ProJournalProvider()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('renders timeline cards with the no-show badge + a gap slot',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Ma journée'), findsOneWidget);
    expect(find.text('Koffi'), findsOneWidget);
    expect(find.text('Aminata'), findsOneWidget);
    expect(find.text('2 absences'), findsOneWidget);
    // The 10:00→14:00 gap renders a tappable « Libre » row.
    expect(find.textContaining('Libre'), findsOneWidget);
  });

  testWidgets('empty day shows the empty state', (tester) async {
    stub.empty = true;
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('Aucun rendez-vous ce jour'), findsOneWidget);
  });

  testWidgets('tapping a card opens the detail', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.text('Koffi'));
    await settle(tester);
    expect(find.text('DETAIL'), findsOneWidget);
  });

  testWidgets('tapping a « Libre » gap opens prefilled manual booking',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.textContaining('Libre'));
    await settle(tester);
    expect(find.text('MANUEL'), findsOneWidget);
  });

  testWidgets('long-press surfaces the action sheet (Client arrivé)',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.longPress(find.text('Koffi'));
    await settle(tester);
    expect(find.text('Client arrivé'), findsOneWidget);
    expect(find.text('Terminé'), findsWidgets);
  });
}
