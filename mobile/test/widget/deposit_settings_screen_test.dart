import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/providers/pro_deposit_settings_provider.dart';
import 'package:myweli/screens/provider/settings/deposit_settings_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:provider/provider.dart';

class _MockProService extends Mock implements ProServiceInterface {}

void main() {
  setUpAll(() {
    serviceLocator.authService = MockAuthService();
  });

  late _MockProService service;

  setUpAll(() {
    service = _MockProService();
    serviceLocator.proService = service;
  });

  setUp(() => reset(service));

  Widget host() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ProDepositSettingsProvider()),
          // T52 lock reads the session's verification status.
          ChangeNotifierProvider(create: (_) => ProAuthProvider()),
        ],
        child: const MaterialApp(
          home: DepositSettingsScreen(providerId: 'p1'),
        ),
      );

  testWidgets('shows the loaded policy', (tester) async {
    when(() => service.getDepositPolicy(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(depositRequired: true, depositPercentage: 0.30),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Exiger un acompte'), findsOneWidget);
    expect(find.text('30 %'), findsOneWidget);
    // T52: an unverified session sees the lock banner.
    expect(
      find.textContaining('après la vérification'),
      findsOneWidget,
    );
    // The banner lengthens the lazy ListView — bring the tail into view.
    await tester.scrollUntilVisible(
      find.text('Enregistrer', skipOffstage: false),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Enregistrer', skipOffstage: false), findsOneWidget);
    expect(
        find.text("Recevoir l'acompte", skipOffstage: false), findsOneWidget);
  });

  testWidgets('hides the percentage when the deposit is off', (tester) async {
    when(() => service.getDepositPolicy(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(depositRequired: false, depositPercentage: 0.30),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text("Pourcentage de l'acompte"), findsNothing);
  });
}
