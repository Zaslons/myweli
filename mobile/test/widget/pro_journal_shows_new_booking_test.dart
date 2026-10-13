import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/router/pro_router.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/journal_day.dart';
import 'package:myweli/providers/pro_appointment_provider.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/providers/pro_service_provider.dart';
import 'package:myweli/screens/provider/appointments/pro_manual_booking_screen.dart';
import 'package:myweli/screens/provider/journal/pro_journal_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

/// « Ma journée » shows a booking the salon just created
/// (docs/design/pro-journal-shows-new-booking.md).
///
/// **What is real here**: the journal screen, the manual-booking screen, the
/// app's own routes (`ProRouter`'s `GoRoute`s, so the « Libre » prefill travels
/// through the real `extra`), the three providers, wired as `main_pro.dart`
/// wires them. **What is stubbed**: the service — one fake salon whose journal
/// and whose `POST` answer from the same list, the way a server does.
///
/// **Three shapes this file refuses**, each of which passes on the broken app:
///
///  * a test that pulls the list down, or calls `refresh()` — no test here
///    drags anything or calls a provider method; the only gestures are taps
///    and typing (the scroll case moves the list with `ensureVisible`, which
///    is not a gesture and cannot trigger a refresh);
///  * a stub that already holds the booking — every test asserts the server
///    list has no salon-entered booking before the form is opened;
///  * `find.text('Yao K.')` — the name is also in the form's own text field,
///    and the form is still in the tree while it slides away. Every assertion
///    about the day is scoped to the card keyed by the booking's id.
class _Salon extends MockProService {
  /// What the SERVER holds.
  final List<Appointment> bookings = [];
  List<JournalArtist> artists = const [];

  int journalCalls = 0;
  int createCalls = 0;

  /// While set, every journal answer waits for it: « the reload is in flight ».
  Completer<void>? journalGate;

  /// How the journal answers: null = the list, 'error' = a refusal,
  /// 'throw' = the request never got an answer.
  String? journalFailure;

  /// When set, the creation is refused with this sentence.
  String? createRefusal;

  /// While set, the creation waits for it: « the request is in flight ».
  Completer<void>? createGate;

  void reset() {
    bookings.clear();
    artists = const [];
    journalCalls = 0;
    createCalls = 0;
    journalGate = null;
    journalFailure = null;
    createRefusal = null;
    createGate = null;
  }

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  ) async {
    journalCalls++;
    final gate = journalGate;
    if (gate != null) await gate.future;
    if (journalFailure == 'throw') throw Exception('SocketException');
    if (journalFailure == 'error') {
      return ApiResponse.error('Erreur réseau. Réessayez.');
    }
    final key = salonDayKey(date);
    final day =
        bookings.where((a) => salonDayKey(a.appointmentDate) == key).toList()
          ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
    return ApiResponse.success(
      JournalDay(date: key, artists: artists, appointments: day),
    );
  }

  @override
  Future<ApiResponse<Appointment>> createManualBooking({
    required String providerId,
    required List<String> serviceIds,
    required DateTime appointmentDateTime,
    String? clientName,
    String? clientPhone,
    String? notes,
    String? artistId,
    bool sendSmsInvite = false,
  }) async {
    createCalls++;
    final gate = createGate;
    if (gate != null) await gate.future;
    final refusal = createRefusal;
    if (refusal != null) {
      return ApiResponse.error(refusal, code: 'slot_unavailable');
    }
    // The server's own answer (`BookingService.bookManual`): priced and timed
    // from the salon's services, confirmed, no artist unless one was sent.
    final services = MockData.getServicesForProvider(
      providerId,
    ).where((s) => serviceIds.contains(s.id));
    final created = Appointment(
      id: 'm$createCalls',
      userId: 'manual',
      providerId: providerId,
      serviceIds: serviceIds,
      artistId: artistId,
      appointmentDate: appointmentDateTime,
      status: AppointmentStatus.confirmed,
      totalPrice: services.fold(0, (sum, s) => sum + s.price),
      durationMinutes: services.fold<int>(
        0,
        (sum, s) => sum + s.durationMinutes,
      ),
      clientName: clientName,
      clientPhone: clientPhone,
      notes: notes,
      createdAt: AppClock.now(),
    );
    bookings.add(created);
    return ApiResponse.success(created);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final salon = _Salon();

  Appointment booked({
    required String id,
    required String time,
    required String name,
    int minutes = 60,
    String? artistId,
    String status = 'confirmed',
    int day = 11,
  }) => Appointment(
    id: id,
    userId: 'u-$id',
    providerId: 'provider1',
    serviceIds: const ['service1'],
    artistId: artistId,
    appointmentDate: DateTime.parse(
      '2026-03-${day.toString().padLeft(2, '0')}T$time:00.000Z',
    ),
    status: AppointmentStatus.values.byName(status),
    totalPrice: 5000,
    durationMinutes: minutes,
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
    // 11:00–12:00 and 15:00–16:00, so the day has ONE gap: « Libre — 12:00 ».
    salon.bookings.addAll([
      booked(id: 'a1', time: '11:00', name: 'Koffi'),
      booked(id: 'a2', time: '15:00', name: 'Aminata'),
    ]);
  });

  /// The app's own routes, taken from `ProRouter` rather than rewritten: the
  /// « Libre » row's `extra` is read by the same builder the app ships.
  List<RouteBase> realRoutes() {
    const wanted = {'/pro/journal', '/pro/appointment/new'};
    final routes = ProRouter.router.configuration.routes
        .whereType<GoRoute>()
        .where((r) => wanted.contains(r.path))
        .toList();
    expect(routes.map((r) => r.path).toSet(), wanted);
    return routes;
  }

  /// The providers, registered the way `main_pro.dart` registers them.
  Future<void> openJournal(
    WidgetTester tester, {
    Size size = const Size(400, 1600),
  }) async {
    // Tall enough for the whole form: no test in this file scrolls anything.
    pinSurface(tester, size: size);
    // Wednesday 11 March 2026, 10:30 in Abidjan: the week strip is 9–15 March.
    freezeClock(DateTime.utc(2026, 3, 11, 10, 30));
    final auth = await signInPro(tester);
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
        ],
        routerConfig: GoRouter(
          initialLocation: '/pro/journal',
          routes: realRoutes(),
        ),
      ),
    );
    await settleMocks(tester);
    expect(find.text('Ma journée'), findsOneWidget);
    expect(find.text('Aujourd’hui'), findsOneWidget);
    // The vacuity guard: nothing salon-entered exists before the form opens.
    expect(salon.bookings.where((b) => b.userId == 'manual'), isEmpty);
    expect(salon.createCalls, 0);
  }

  Finder inJournal(Finder f) =>
      find.descendant(of: find.byType(ProJournalScreen), matching: f);

  /// The day's card for a booking — `Slidable(key: ValueKey(id))`.
  Finder card(String id) => inJournal(find.byKey(ValueKey(id)));

  Finder inCard(String id, String text) =>
      find.descendant(of: card(id), matching: find.text(text));

  Finder gap(String time) => inJournal(find.text('Libre — $time'));

  /// The week strip's load dot under a day number (0 wide = no dot).
  double dotWidth(WidgetTester tester, String dayNumber) {
    final pill = find
        .ancestor(
          of: inJournal(find.text(dayNumber)),
          matching: find.byType(Column),
        )
        .first;
    final dot = find.descendant(of: pill, matching: find.byType(Container));
    return tester.getSize(dot.last).width;
  }

  /// The vertical list of a screen (text fields and the chip strip carry
  /// scrollables of their own).
  Finder listOf(Type screen) => find
      .descendant(
        of: find.byType(screen),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first;

  /// Brings a form control on screen WITHOUT a drag. On the tall surface this
  /// does nothing; on the short one the form's list culls what is below it.
  Future<void> reveal(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      final position = tester
          .state<ScrollableState>(listOf(ProManualBookingScreen))
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }
    await tester.ensureVisible(f);
    await tester.pump();
  }

  Future<void> formIsOpen(WidgetTester tester) async {
    await settleMocks(tester, rounds: 3); // the push + the services load
    expect(find.byType(ProManualBookingScreen), findsOneWidget);
    expect(find.text('Coupe Homme'), findsOneWidget);
  }

  /// A walk-in named [name], one service — the film's own gesture.
  Future<void> fillForm(WidgetTester tester, {String name = 'Yao K.'}) async {
    await tester.tap(find.text('Coupe Homme'));
    await tester.pump();
    await reveal(tester, find.text('Client sans numéro'));
    await tester.tap(find.text('Client sans numéro'));
    await tester.pump();
    final nameField = find.descendant(
      of: find.widgetWithText(TextField, 'Nom du client (optionnel)'),
      matching: find.byType(EditableText),
    );
    await reveal(tester, nameField);
    await tester.enterText(nameField, name);
    await tester.pump();
    await reveal(tester, find.text('Créer le rendez-vous'));
  }

  /// « Créer le rendez-vous », then ONE frame: the answer has landed and the
  /// form has only just started to leave.
  Future<void> create(WidgetTester tester) async {
    await tester.tap(find.text('Créer le rendez-vous'));
    await tester.pump();
  }

  /// Lets the pop transition and the snackbar's entrance finish.
  Future<void> formHasLeft(WidgetTester tester) async {
    await settleMocks(tester, rounds: 2);
    expect(find.byType(ProManualBookingScreen), findsNothing);
  }

  /// No date and no hour yet (« Nouveau »): today, at the first time offered.
  Future<void> pickTodayAtTheFirstTime(WidgetTester tester) async {
    await tester.tap(find.text('Date'));
    await settleMocks(tester, rounds: 2);
    await tester.tap(find.text('11'));
    await settleMocks(tester, rounds: 2);
    await tester.tap(find.text('Heure'));
    await settleMocks(tester, rounds: 2);
    await tester.tap(find.text('Confirmer'));
    await settleMocks(tester, rounds: 2);
    expect(find.text('11/03/2026'), findsOneWidget);
    expect(find.text('10:30'), findsOneWidget);
  }

  testWidgets('a « Libre » row becomes the booking, with no gesture — while '
      'the reload is still in flight', (tester) async {
    await openJournal(tester);
    expect(gap('12:00'), findsOneWidget);
    expect(card('m1'), findsNothing);
    final callsBefore = salon.journalCalls;

    // From here every journal answer is held: whatever the day shows next
    // cannot have come from the server.
    salon.journalGate = Completer<void>();

    await tester.tap(gap('12:00'));
    await formIsOpen(tester);
    expect(find.text('11/03/2026'), findsOneWidget, reason: 'the prefill');
    expect(find.text('12:00'), findsOneWidget, reason: 'the prefill');
    await fillForm(tester);
    await create(tester);

    expect(salon.createCalls, 1);
    // The form is still on screen, sliding away — and the day already has it.
    expect(find.byType(ProManualBookingScreen), findsOneWidget);
    expect(card('m1'), findsOneWidget);
    expect(inCard('m1', 'Yao K.'), findsOneWidget);
    expect(inCard('m1', '12:00'), findsOneWidget);
    expect(inCard('m1', '12:30'), findsOneWidget, reason: '30 min — its end');
    expect(inCard('m1', 'Confirmé'), findsOneWidget);
    // In its time order: after Koffi (11:00), before Aminata (15:00).
    final y = tester.getTopLeft(card('m1')).dy;
    expect(y, greaterThan(tester.getTopLeft(card('a1')).dy));
    expect(y, lessThan(tester.getTopLeft(card('a2')).dy));
    // The slot it filled is gone; what is left of the gap starts at its end.
    expect(gap('12:00'), findsNothing);
    expect(gap('12:30'), findsOneWidget);
    // The rows that were on screen stayed on screen; nothing spins.
    expect(card('a1'), findsOneWidget);
    expect(card('a2'), findsOneWidget);
    expect(inJournal(find.byType(LoadingIndicator)), findsNothing);
    // The day was asked for again, exactly once, and has not answered.
    expect(salon.journalCalls, callsBefore + 1);

    await formHasLeft(tester);
    expect(find.text('Rendez-vous créé'), findsOneWidget);
    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(card('m1'), findsOneWidget);

    // The server answers, and what it says wins: its own name for the client,
    // and a booking another device took in the meantime.
    final i = salon.bookings.indexWhere((b) => b.id == 'm1');
    salon.bookings[i] = salon.bookings[i].copyWith(
      clientDisplayName: 'Yao Kouamé',
    );
    salon.bookings.add(booked(id: 'a3', time: '17:00', name: 'Fatou'));
    salon.journalGate!.complete();
    salon.journalGate = null;
    await settleMocks(tester);

    expect(inCard('m1', 'Yao Kouamé'), findsOneWidget);
    expect(inCard('m1', 'Yao K.'), findsNothing);
    expect(card('a3'), findsOneWidget);
    expect(inJournal(find.text('Une erreur est survenue')), findsNothing);
  });

  testWidgets('« Nouveau »: the booking is in the day on return, in its time '
      'order', (tester) async {
    await openJournal(tester);
    final callsBefore = salon.journalCalls;
    salon.journalGate = Completer<void>();

    await tester.tap(find.text('Nouveau'));
    await formIsOpen(tester);
    await pickTodayAtTheFirstTime(tester);
    await fillForm(tester);
    await create(tester);

    expect(salon.createCalls, 1);
    expect(card('m1'), findsOneWidget);
    expect(inCard('m1', 'Yao K.'), findsOneWidget);
    expect(inCard('m1', '10:30'), findsOneWidget);
    expect(inCard('m1', 'Confirmé'), findsOneWidget);
    // 10:30 is before everything else that day: it is the first card.
    expect(
      tester.getTopLeft(card('m1')).dy,
      lessThan(tester.getTopLeft(card('a1')).dy),
    );
    expect(salon.journalCalls, callsBefore + 1);

    await formHasLeft(tester);
    expect(find.text('Rendez-vous créé'), findsOneWidget);
    salon.journalGate!.complete();
    await settleMocks(tester);
    expect(card('m1'), findsOneWidget);
  });

  testWidgets('created for another day: « Ma journée » stays on its day, and '
      'that day gets its dot', (tester) async {
    await openJournal(tester);
    expect(dotWidth(tester, '13'), 0, reason: 'nothing is booked on the 13th');
    expect(dotWidth(tester, '11'), greaterThan(0));
    salon.journalGate = Completer<void>();

    await tester.tap(gap('12:00'));
    await formIsOpen(tester);
    // The date is changed in the form: Friday the 13th, same week.
    await tester.tap(find.text('11/03/2026'));
    await settleMocks(tester, rounds: 2);
    await tester.tap(find.text('13'));
    await settleMocks(tester, rounds: 2);
    expect(find.text('13/03/2026'), findsOneWidget);
    await fillForm(tester);
    await create(tester);

    expect(salon.createCalls, 1);
    expect(
      salonDayKey(salon.bookings.last.appointmentDate),
      '2026-03-13',
      reason: 'the booking really is on the other day',
    );
    await formHasLeft(tester);

    expect(find.text('Rendez-vous créé'), findsOneWidget);
    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(card('m1'), findsNothing);
    expect(gap('12:00'), findsOneWidget);
    expect(card('a1'), findsOneWidget);
    expect(card('a2'), findsOneWidget);
    // The reload is still held: this dot is not the server's.
    expect(dotWidth(tester, '13'), greaterThan(0));

    salon.journalGate!.complete();
    salon.journalGate = null;
    await settleMocks(tester);
    expect(dotWidth(tester, '13'), greaterThan(0));
    expect(card('m1'), findsNothing);
  });

  testWidgets('the artist filter is respected: a booking with no artist is '
      'not shown under « Awa », and « Voir les annulés » stays off', (
    tester,
  ) async {
    salon.artists = const [JournalArtist(id: 'ar1', name: 'Awa')];
    salon.bookings
      ..clear()
      ..addAll([
        booked(id: 'a1', time: '11:00', name: 'Koffi', artistId: 'ar1'),
        booked(
          id: 'c1',
          time: '13:00',
          name: 'Mariam',
          artistId: 'ar1',
          status: 'cancelled',
        ),
        booked(id: 'a2', time: '15:00', name: 'Aminata', artistId: 'ar1'),
      ]);
    await openJournal(tester);
    await tester.tap(find.text('Awa'));
    await tester.pump();
    expect(find.text('Sans artiste'), findsNothing);
    expect(card('c1'), findsNothing, reason: 'cancelled rows are hidden');
    salon.journalGate = Completer<void>();

    // « Nouveau » carries no artist: the booking belongs to nobody yet.
    await tester.tap(find.text('Nouveau'));
    await formIsOpen(tester);
    await pickTodayAtTheFirstTime(tester);
    await fillForm(tester);
    await create(tester);
    expect(salon.createCalls, 1);
    expect(salon.bookings.last.artistId, isNull);
    await formHasLeft(tester);

    expect(find.text('Rendez-vous créé'), findsOneWidget);
    expect(card('m1'), findsNothing, reason: 'the filter is « Awa »');
    expect(card('a1'), findsOneWidget);
    expect(card('c1'), findsNothing, reason: '« Voir les annulés » is off');
    // …and it is not lost: the day now has an unassigned booking, and says so.
    expect(find.text('Sans artiste'), findsOneWidget);
    await tester.tap(find.text('Sans artiste'));
    await tester.pump();
    expect(card('m1'), findsOneWidget);
    expect(card('a1'), findsNothing);

    salon.journalGate!.complete();
    await settleMocks(tester);
  });

  testWidgets('the artist filter is carried by a « Libre » row: that booking '
      'IS shown under « Awa »', (tester) async {
    salon.artists = const [JournalArtist(id: 'ar1', name: 'Awa')];
    salon.bookings
      ..clear()
      ..addAll([
        booked(id: 'a1', time: '11:00', name: 'Koffi', artistId: 'ar1'),
        booked(id: 'a2', time: '15:00', name: 'Aminata', artistId: 'ar1'),
      ]);
    await openJournal(tester);
    await tester.tap(find.text('Awa'));
    await tester.pump();
    salon.journalGate = Completer<void>();

    await tester.tap(gap('12:00'));
    await formIsOpen(tester);
    await fillForm(tester);
    await create(tester);

    expect(salon.bookings.last.artistId, 'ar1');
    expect(card('m1'), findsOneWidget);
    await formHasLeft(tester);
    salon.journalGate!.complete();
    await settleMocks(tester);
  });

  for (final failure in ['error', 'throw']) {
    testWidgets('the quiet reload fails ($failure): the booking stays, and '
        'nothing shouts', (tester) async {
      await openJournal(tester);
      // Every journal request from now on fails — offline, or a 5xx.
      salon.journalFailure = failure;
      final callsBefore = salon.journalCalls;

      await tester.tap(gap('12:00'));
      await formIsOpen(tester);
      await fillForm(tester);
      await create(tester);
      await formHasLeft(tester);

      expect(salon.createCalls, 1);
      expect(salon.journalCalls, callsBefore + 1, reason: 'it did try');
      expect(card('m1'), findsOneWidget);
      expect(inCard('m1', 'Yao K.'), findsOneWidget);
      expect(card('a1'), findsOneWidget);
      expect(card('a2'), findsOneWidget);
      expect(find.text('Rendez-vous créé'), findsOneWidget);
      expect(find.text('Une erreur est survenue'), findsNothing);
      expect(find.text('Réessayer'), findsNothing);
      expect(find.textContaining('Erreur réseau'), findsNothing);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(inJournal(find.byType(LoadingIndicator)), findsNothing);
    });
  }

  testWidgets('control — a refused creation changes nothing: the form keeps '
      'its error, the day is not touched', (tester) async {
    await openJournal(tester);
    salon.createRefusal = 'Ce créneau n’est plus disponible.';
    final callsBefore = salon.journalCalls;

    await tester.tap(gap('12:00'));
    await formIsOpen(tester);
    await fillForm(tester);
    await create(tester);
    await settleMocks(tester, rounds: 2);

    expect(salon.createCalls, 1);
    // Still on the form, with the refusal under it — not a snackbar.
    expect(find.byType(ProManualBookingScreen), findsOneWidget);
    expect(find.text('Ce créneau n’est plus disponible.'), findsOneWidget);
    expect(find.text('Rendez-vous créé'), findsNothing);
    expect(salon.journalCalls, callsBefore, reason: 'nothing to reload');

    await tester.tap(find.byType(BackButton));
    await settleMocks(tester, rounds: 2);
    expect(find.byType(ProManualBookingScreen), findsNothing);
    expect(card('m1'), findsNothing);
    expect(gap('12:00'), findsOneWidget);
    expect(card('a1'), findsOneWidget);
    expect(card('a2'), findsOneWidget);
    expect(salon.journalCalls, callsBefore);
  });

  testWidgets('a scrolled day keeps its place: same offset, no loader, the '
      'booking where the free slot was', (tester) async {
    // Ten bookings on a phone-high screen: the day scrolls. One gap, low in
    // the list — « Libre — 17:00 », between 16:00–17:00 and 18:00.
    salon.bookings
      ..clear()
      ..addAll([
        for (final h in [11, 12, 13, 14, 15, 16, 18, 19, 20, 21])
          booked(id: 'b$h', time: '$h:00', name: 'Cliente $h'),
      ]);
    await openJournal(tester, size: const Size(400, 700));
    ScrollPosition day() =>
        tester.state<ScrollableState>(listOf(ProJournalScreen)).position;

    // Moved by the scroll position itself — not a drag, so nothing here can
    // be mistaken for a pull.
    while (gap('17:00').evaluate().isEmpty) {
      expect(day().pixels, lessThan(day().maxScrollExtent));
      day().jumpTo(day().pixels + 150);
      await tester.pump();
    }
    await tester.ensureVisible(gap('17:00'));
    await tester.pump();
    final offset = day().pixels;
    expect(offset, greaterThan(0), reason: 'the day really is scrolled');
    final slotTop = tester.getTopLeft(gap('17:00')).dy;
    salon.journalGate = Completer<void>();

    await tester.tap(gap('17:00'));
    await formIsOpen(tester);
    await fillForm(tester);
    await create(tester);

    expect(card('m1'), findsOneWidget);
    expect(inJournal(find.byType(LoadingIndicator)), findsNothing);
    await formHasLeft(tester);
    expect(day().pixels, offset);
    // The card sits where the « Libre » row was — nothing above it moved.
    expect(tester.getTopLeft(card('m1')).dy, closeTo(slotTop, 8));

    salon.journalGate!.complete();
    await settleMocks(tester);
    expect(day().pixels, offset, reason: 'the reload does not move the list');
    expect(card('m1'), findsOneWidget);
  });

  testWidgets('two taps in one frame: one request, one booking, one pop', (
    tester,
  ) async {
    await openJournal(tester);
    await tester.tap(gap('12:00'));
    await formIsOpen(tester);
    await fillForm(tester);

    // The request is held, and no frame is pumped between the taps: the
    // button has not been rebuilt disabled yet.
    salon.createGate = Completer<void>();
    final button = find.text('Créer le rendez-vous');
    await tester.tap(button);
    await tester.tap(button, warnIfMissed: false);
    expect(salon.createCalls, 1);

    salon.createGate!.complete();
    await tester.pump();
    await formHasLeft(tester);
    expect(salon.bookings.where((b) => b.userId == 'manual'), hasLength(1));
    // One pop: « Ma journée » is still there, with the one booking.
    expect(find.text('Ma journée'), findsOneWidget);
    expect(card('m1'), findsOneWidget);
    expect(card('m2'), findsNothing);
  });
}
