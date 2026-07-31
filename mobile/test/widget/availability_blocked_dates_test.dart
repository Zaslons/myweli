import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_time.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_availability_provider.dart';
import 'package:myweli/screens/provider/availability/availability_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/widgets/common/myweli_date_picker.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

class _MockProService extends Mock implements ProServiceInterface {}

/// A14e — the blocked-dates half of the pro availability screen, end to end.
///
/// **What this file proves that `blocked_dates_test.dart` cannot.** That one
/// asserts the composer in isolation; this one asserts what the SERVICE
/// actually receives, so the property survives `copyWith` → `toJson` → the
/// wire and not merely the function. The erasure it guards is invisible from
/// the UI — past days never render in the picker — so a green unit test alone
/// would leave the end-to-end path unwatched.
void main() {
  late _MockProService service;

  setUpAll(() {
    serviceLocator.authService = MockAuthService();
    service = _MockProService();
    serviceLocator.proService = service;
    registerFallbackValue(
      const Availability(providerId: 'p', weeklySchedule: {}, blockedDates: []),
    );
  });

  setUp(() => reset(service));

  /// The salon's own day, N days out. The seeded salon is `Africa/Abidjan`,
  /// which is the default zone, so `tz: null` names the same days the screen
  /// does — stated rather than assumed.
  DateTime salonDay(int offset) {
    final t = salonToday();
    return salonDateTime(t.year, t.month, t.day + offset);
  }

  /// The CTA sits under four cards and a weekly-hours list, so it is below the
  /// fold at the test surface — scrolled to rather than tapped blind.
  Future<void> tapBlockedDatesCta(WidgetTester tester) async {
    final cta = find.text('Gérer les dates bloquées');
    await tester.scrollUntilVisible(cta, 300);
    await tester.tap(cta);
    await settleMocks(tester);
  }

  /// Pumps the screen on a salon whose availability holds [blocked].
  Future<void> pumpWith(WidgetTester tester, List<DateTime> blocked) async {
    final auth = await signInPro(tester);
    when(() => service.getProviderAvailability(any())).thenAnswer(
      (_) async => ApiResponse.success(
        Availability(
          providerId: 'provider1',
          weeklySchedule: const {},
          blockedDates: blocked,
        ),
      ),
    );
    when(() => service.updateAvailability(any(), any())).thenAnswer(
      (i) async =>
          ApiResponse.success(i.positionalArguments[1] as Availability),
    );

    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProAvailabilityProvider()),
        ],
        home: const AvailabilityScreen(),
      ),
    );
    await settleMocks(tester, rounds: 3);
  }

  testWidgets('a PAST blocked date survives blocking a new one', (
    tester,
  ) async {
    // The end-to-end half of the erasure gate. The pro has a date blocked last
    // month; they open the picker (which starts TODAY, so that date is not in
    // it), block one more day, and save. A full-set write would send one date
    // where two must go — silently, permanently, and with nothing on screen to
    // show it happened.
    final past = salonDay(-30);
    await pumpWith(tester, [past]);
    await tapBlockedDatesCta(tester);

    // **Next month, always.** The picker opens on today's month, and a
    // « today + 2 » target crosses the boundary at the end of a month — an
    // earlier draft of this test ran on the 31st and tapped the SECOND of the
    // current month, a past and disabled cell, so the toggle silently never
    // happened. One chevron forward makes the 15th unambiguous and in range on
    // every calendar day of the year.
    await tester.tap(find.byTooltip('Mois suivant'));
    await tester.pump();
    const targetDay = 15;
    // Scoped to the picker: `find.text` searches the WHOLE tree, and the
    // screen underneath the route carries numbers too — an unscoped `.first`
    // tapped one of them and the toggle never happened.
    await tester.tap(
      find
          .descendant(
            of: find.byType(MyweliMultiDatePickerScreen),
            matching: find.text('$targetDay'),
          )
          .first,
    );
    await tester.pump();
    // Probe: the summary proves the toggle landed before we commit.
    expect(find.text('1 date bloquée'), findsOneWidget);
    await tester.tap(find.text('Enregistrer'));
    await settleMocks(tester, rounds: 3);

    // The one confirm — and for a pure addition it names the direction.
    expect(find.text('Bloquer cette date ?'), findsOneWidget);
    await tester.tap(find.text('Bloquer'));
    await settleMocks(tester);

    final sent =
        verify(
              () => service.updateAvailability(any(), captureAny()),
            ).captured.last
            as Availability;

    expect(
      sent.blockedDates,
      contains(past),
      reason:
          'the picker never showed the past date, so it is in neither added '
          'nor removed — a full-set write would drop it for good',
    );
    expect(sent.blockedDates, hasLength(2));
  });

  testWidgets('removing a date now CONFIRMS — it used to write at once', (
    tester,
  ) async {
    // Adding always confirmed and removing never did, which put the guard on
    // the safer half: unblocking is the direction that produces an unwanted
    // booking.
    await pumpWith(tester, [salonDay(5)]);

    final del = find.byTooltip('Supprimer').first;
    await tester.scrollUntilVisible(del, 300);
    await tester.tap(del);
    await settleMocks(tester);

    expect(find.text('Débloquer cette date ?'), findsOneWidget);
    verifyNever(() => service.updateAvailability(any(), any()));

    await tester.tap(find.text('Débloquer'));
    await settleMocks(tester);

    final sent =
        verify(
              () => service.updateAvailability(any(), captureAny()),
            ).captured.last
            as Availability;
    expect(sent.blockedDates, isEmpty);
  });
}
