import 'package:flutter/material.dart';
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
import 'package:provider/provider.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';

class _MockProService extends Mock implements ProServiceInterface {}

/// A day's ranges may not overlap — the web refuses it, and the owner asked
/// for the app to do the same (docs/design/web-pro-availability-ranges.md
/// §9.2). The day editor refuses at « Enregistrer » AND at « Copier sur les
/// autres jours », with the web's sentence, IN the screen (a form error,
/// never a toast — SYSTEM §14), and writes nothing. Touching ranges (12:00 /
/// 12:00) stay allowed. The harness is availability_presets_test.dart's.
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

  TimeSlot slotAt(int startHour, int endHour) {
    final t = salonToday();
    DateTime at(int h) => salonDateTime(t.year, t.month, t.day, hour: h);
    return TimeSlot(
      startTime: at(startHour),
      endTime: at(endHour),
      isAvailable: true,
    );
  }

  Future<void> pumpWith(
    WidgetTester tester,
    Map<int, List<TimeSlot>> schedule,
  ) async {
    final auth = await signInPro(tester);
    when(() => service.getProviderAvailability(any())).thenAnswer(
      (_) async => ApiResponse.success(
        Availability(
          providerId: 'provider1',
          weeklySchedule: schedule,
          blockedDates: const [],
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

  Future<void> openLundi(WidgetTester tester) async {
    final lundi = find.widgetWithText(ListTile, 'Lundi');
    await tester.scrollUntilVisible(lundi, 300);
    await tester.tap(
      find.descendant(of: lundi, matching: find.byTooltip('Modifier')),
    );
    await settleMocks(tester);
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settleMocks(tester);
  }

  const overlap = 'Lundi : deux plages se chevauchent.';

  testWidgets('« Enregistrer » refuses two overlapping ranges — in the screen, '
      'nothing written', (tester) async {
    await pumpWith(tester, {
      0: [slotAt(9, 13), slotAt(12, 18)],
    });
    await openLundi(tester);
    await tapVisible(
      tester,
      find.widgetWithText(ElevatedButton, 'Enregistrer'),
    );

    expect(find.text(overlap), findsOneWidget);
    verifyNever(() => service.updateAvailability(any(), any()));
  });

  testWidgets('« Copier sur les autres jours » refuses them too — before its '
      'confirm', (tester) async {
    await pumpWith(tester, {
      0: [slotAt(9, 13), slotAt(12, 18)],
    });
    await openLundi(tester);
    await tapVisible(tester, find.text('Copier sur les autres jours'));

    expect(find.text(overlap), findsOneWidget);
    expect(find.text('Copier sur les autres jours ?'), findsNothing);
    verifyNever(() => service.updateAvailability(any(), any()));
  });

  testWidgets('touching ranges save', (tester) async {
    await pumpWith(tester, {
      0: [slotAt(9, 12), slotAt(12, 18)],
    });
    await openLundi(tester);
    await tapVisible(
      tester,
      find.widgetWithText(ElevatedButton, 'Enregistrer'),
    );

    expect(find.text(overlap), findsNothing);
    verify(() => service.updateAvailability('provider1', any())).called(1);
  });
}
