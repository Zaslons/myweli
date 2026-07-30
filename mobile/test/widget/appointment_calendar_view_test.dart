import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/appointments/appointment_calendar_view.dart';
import 'package:provider/provider.dart';

import '../support/fonts.dart';
import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

/// The pro calendar's behaviour (A14c §18).
///
/// **This screen had no test of any kind** — no widget test, no golden, and no
/// a11y subject, because both instruments aimed at it tapped away to the
/// « Liste » tab in their second statement. Row 75 recorded that as "nothing
/// has ever measured it"; this file and `layout_test.dart`'s 16th subject are
/// the two halves of fixing it.
void main() {
  setUpAll(() async {
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    await loadRealFonts();
    stubSecureStorage();
    setupDependencyInjection();
  });

  tearDownAll(AppClock.restore);
  setUp(() => freezeClock(kFixedNow));

  Future<void> pumpCalendar(
    WidgetTester tester,
    List<Appointment> appointments,
  ) async {
    final auth = await signInPro(tester);
    await tester.pumpWidget(
      wrapApp(
        providers: [ChangeNotifierProvider<ProAuthProvider>.value(value: auth)],
        home: Scaffold(
          body: AppointmentCalendarView(appointments: appointments),
        ),
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  testWidgets('a salon with NOTHING booked still gets a calendar', (
    tester,
  ) async {
    await pumpCalendar(tester, const []);

    // **The lockout this closes.** `appointment_list_screen` used to replace
    // the whole calendar with a centred « Aucun rendez-vous » whenever the
    // salon had no appointments — so a brand-new salon, or any pro on a quiet
    // week, could not open its calendar at all and could not browse forward to
    // plan. A calendar with nothing in it is not an error state; it is a
    // calendar.
    expect(
      find.text('mars 2026'),
      findsOneWidget,
      reason: 'the month bar must render with zero appointments',
    );
    expect(
      find.text('11'),
      findsOneWidget,
      reason: 'and so must the days — this is a month, not a message',
    );

    // The day list says it per DAY, naming the day, which is the more useful
    // sentence than a screen-wide one. This branch was unreachable before.
    expect(find.textContaining('mercredi 11 mars 2026'), findsWidgets);
  });

  // **A REAL phone, because the matrix does not use one.** `pumpAtWidth`
  // defaults to `height: 1600` so a screen's full content can be measured
  // without scroll clipping — deliberate, and it means nothing in
  // `layout_test.dart` exercises the actual vertical budget. The calendar is
  // the one screen where that matters: it grows with the text scale, and the
  // day list sits under it in the same scroll view.
  for (final scale in [1.0, 2.0]) {
    testWidgets('an empty day fits a real 360×780 phone at $scale×', (
      tester,
    ) async {
      pinSurface(tester, size: kFloorPhone, scale: scale);
      await pumpCalendar(tester, const []);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the month plus the per-day empty state must fit, or scroll — this '
            'view overflowed by 40dp before it became one CustomScrollView',
      );
    });
  }

  testWidgets('a day with appointments announces how many, and shows one dot', (
    tester,
  ) async {
    // Two on the salon's today (the frozen clock), one on another day.
    final today = kFixedNow;
    await pumpCalendar(tester, [
      _appt('a1', today),
      _appt('a2', today.add(const Duration(hours: 2))),
      _appt('a3', today.add(const Duration(days: 3))),
    ]);

    final handle = tester.ensureSemantics();

    // **The count lives in speech, not in pixels** (§17.2). `_WeekStrip` had
    // already tried encoding it in the marker's width and — because
    // `BoxShape.circle` paints `drawCircle(center, rect.shortestSide / 2)` —
    // one appointment and five painted the identical 4dp dot. Here the eye gets
    // "something is on this day" and a screen-reader user gets the number.
    expect(
      tester
          .getSemantics(
            find
                .ancestor(of: find.text('11'), matching: find.byType(Semantics))
                .first,
          )
          .label,
      contains('2 rendez-vous'),
      reason: 'the salon has two bookings on 11 March',
    );

    // A day with none must not claim any — the marker channel is on for every
    // cell in the month, so an absent day still reserves the row.
    expect(
      tester
          .getSemantics(
            find
                .ancestor(of: find.text('12'), matching: find.byType(Semantics))
                .first,
          )
          .label,
      isNot(contains('rendez-vous')),
    );
    handle.dispose();
  });
}

Appointment _appt(String id, DateTime at) => Appointment(
  id: id,
  userId: 'user1',
  providerId: 'provider1',
  serviceIds: const ['s1'],
  appointmentDate: at,
  status: AppointmentStatus.confirmed,
  totalPrice: 15000,
  depositAmount: 3000,
  balanceDue: 12000,
  createdAt: at,
);
