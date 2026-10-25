import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/journal_day.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/providers/pro_service_provider.dart';
import 'package:myweli/screens/provider/journal/pro_journal_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

/// A status changed on the booking's detail reaches « Ma journée » and
/// « Accueil » without a pull (docs/design/app-pro-home-journal-fresh.md
/// §2.1, owner decision 8). Before: back on the journal the card still said
/// « En attente », and the home count too, until the list was pulled down.
///
/// **No test here pulls or calls a provider method after the journal opens**:
/// the only gestures are taps. The journal's reload is HELD when the detail
/// acts, so « at once » cannot be faked by the reload answering first.
class _Salon extends MockProService {
  final List<Appointment> bookings = [];
  int statsCalls = 0;

  /// While set, journal answers wait for it.
  Completer<void>? journalGate;

  void reset() {
    bookings.clear();
    statsCalls = 0;
    journalGate = null;
  }

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  ) async {
    final key = salonDayKey(date);
    final snapshot = [
      for (final a in bookings)
        if (salonDayKey(a.appointmentDate) == key) a,
    ]..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
    final gate = journalGate;
    if (gate != null) await gate.future;
    return ApiResponse.success(
      JournalDay(date: key, artists: const [], appointments: snapshot),
    );
  }

  @override
  Future<ApiResponse<List<Appointment>>> getProviderAppointments(
    String providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async => ApiResponse.success(List.of(bookings));

  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(
    String providerId,
  ) async {
    statsCalls++;
    final pending = bookings
        .where((a) => a.status == AppointmentStatus.pending)
        .length;
    return ApiResponse.success(
      DashboardStats(
        todayAppointments: bookings.length,
        pendingRequests: pending,
        totalAppointments: bookings.length,
      ),
    );
  }

  Future<ApiResponse<bool>> _set(String id, AppointmentStatus status) async {
    final i = bookings.indexWhere((a) => a.id == id);
    bookings[i] = bookings[i].copyWith(status: status);
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> acceptAppointment(String appointmentId) =>
      _set(appointmentId, AppointmentStatus.confirmed);

  @override
  Future<ApiResponse<bool>> rejectAppointment(
    String appointmentId,
    String? reason,
  ) => _set(appointmentId, AppointmentStatus.cancelled);

  @override
  Future<ApiResponse<bool>> markAppointmentComplete(String appointmentId) =>
      _set(appointmentId, AppointmentStatus.completed);

  @override
  Future<ApiResponse<bool>> markNoShow(String appointmentId) =>
      _set(appointmentId, AppointmentStatus.noShow);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final salon = _Salon();

  Appointment booked(String id, String time, String name, String status) =>
      Appointment(
        id: id,
        userId: 'u-$id',
        providerId: 'provider1',
        serviceIds: const ['service1'],
        appointmentDate: DateTime.parse('2026-03-11T$time:00.000Z'),
        status: AppointmentStatus.values.byName(status),
        totalPrice: 5000,
        durationMinutes: 60,
        clientDisplayName: name,
        createdAt: DateTime.utc(2026, 3, 1),
      );

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = salon; // late final — one fake for the file
  });

  setUp(() {
    salon.reset();
    ProSalonScope.clear();
    salon.bookings.addAll([
      booked('pend', '11:00', 'Koffi', 'pending'), // a request, later today
      booked('done', '08:00', 'Aminata', 'confirmed'), // started already
    ]);
  });

  List<RouteBase> realRoutes() {
    const wanted = {'/pro/journal', '/pro/appointment/:id'};
    final routes = ProRouter.router.configuration.routes
        .whereType<GoRoute>()
        .where((r) => wanted.contains(r.path))
        .toList();
    expect(routes.map((r) => r.path).toSet(), wanted);
    return routes;
  }

  late ProDashboardProvider home;

  Future<void> openJournal(WidgetTester tester) async {
    pinSurface(tester, size: const Size(400, 1600));
    // Wednesday 11 March 2026, 10:30 in Abidjan.
    freezeClock(DateTime.utc(2026, 3, 11, 10, 30));
    final auth = await signInPro(tester);
    home = ProSalonScope.track(ProDashboardProvider());
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProAppointmentProvider()),
          ),
          ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProServiceProvider()),
          ),
          ChangeNotifierProvider(
            create: (_) => ProSalonScope.track(ProJournalProvider()),
          ),
          ChangeNotifierProvider<ProDashboardProvider>.value(value: home),
        ],
        routerConfig: GoRouter(
          initialLocation: '/pro/journal',
          routes: realRoutes(),
        ),
      ),
    );
    // « Accueil » was visited before: its figures are in memory.
    await home.loadDashboardStats(SalonId('provider1'));
    await settleMocks(tester);
    expect(home.stats!.pendingRequests, 1);
  }

  Finder card(String id) => find.descendant(
    of: find.byType(ProJournalScreen),
    matching: find.byKey(ValueKey(id)),
  );

  Finder inCard(String id, String text) =>
      find.descendant(of: card(id), matching: find.text(text));

  /// Taps the card, acts on the detail, comes back — the journal's reload is
  /// held from the moment the detail is open.
  Future<void> actOnDetail(
    WidgetTester tester,
    String id,
    Future<void> Function() act,
  ) async {
    await tester.tap(card(id));
    await settleMocks(tester, rounds: 3);
    expect(find.text('Détails'), findsOneWidget);
    salon.journalGate = Completer<void>();
    await act();
    await settleMocks(tester, rounds: 3);
    expect(find.byType(ProJournalScreen), findsOneWidget);
  }

  testWidgets(
    '« Accepter » on the detail: back, the card says « Confirmé » at once, '
    'and « Accueil » has one request fewer',
    (tester) async {
      await openJournal(tester);
      expect(inCard('pend', 'En attente'), findsOneWidget);
      await actOnDetail(tester, 'pend', () async {
        await tester.tap(find.text('Accepter'));
      });
      // The journal's reload is still held: this is the announcement's doing.
      expect(inCard('pend', 'Confirmé'), findsOneWidget);
      expect(inCard('pend', 'En attente'), findsNothing);
      expect(home.stats!.pendingRequests, 0);
      salon.journalGate!.complete();
      await settleMocks(tester);
      expect(inCard('pend', 'Confirmé'), findsOneWidget);
    },
  );

  testWidgets(
    '« Rejeter »: back, the request has left the day (cancelled is hidden)',
    (tester) async {
      await openJournal(tester);
      await actOnDetail(tester, 'pend', () async {
        await tester.tap(find.text('Rejeter'));
      });
      expect(card('pend'), findsNothing);
      expect(home.stats!.pendingRequests, 0);
      salon.journalGate!.complete();
      await settleMocks(tester);
    },
  );

  testWidgets(
    '« Marquer comme terminé »: back, the card says « Terminé » at once',
    (tester) async {
      await openJournal(tester);
      await actOnDetail(tester, 'done', () async {
        await tester.tap(find.text('Marquer comme terminé'));
      });
      expect(inCard('done', 'Terminé'), findsOneWidget);
      salon.journalGate!.complete();
      await settleMocks(tester);
    },
  );

  testWidgets(
    '« Marquer comme absent » (confirmed): back, the card says « Absent » at once',
    (tester) async {
      await openJournal(tester);
      await actOnDetail(tester, 'done', () async {
        await tester.tap(find.text('Marquer comme absent'));
        await settleMocks(tester);
        await tester.tap(find.text('Marquer absent'));
      });
      expect(inCard('done', 'Absent'), findsOneWidget);
      salon.journalGate!.complete();
      await settleMocks(tester);
    },
  );
}
