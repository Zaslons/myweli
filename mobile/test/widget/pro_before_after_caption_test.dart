import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/before_after_pair.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_before_after_provider.dart';
import 'package:myweli/screens/provider/photos/pro_before_after_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_image_upload_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// docs/design/pro-screenshot-shoot-fixes.md §1.7 — a pair without a
/// caption shows NO caption line. It showed « — », a placeholder nobody chose.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = MockAuthService();
  final pro = MockProService();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.proService = pro;
    serviceLocator.imageUploadService = MockImageUploadService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  testWidgets(
    'a captionless pair has no caption line; a captioned one keeps it',
    (tester) async {
      // The seeded owner of provider1: the mock stores pairs on
      // `MockData.providers`, which a freshly registered salon is not in.
      late ProAuthProvider authProvider;
      late List<BeforeAfterPair> seeded;
      await tester.runAsync(() async {
        await auth.requestProviderEmailOtp('jean@salon-excellence.test');
        final res = await auth.verifyProviderEmailOtp(
          'jean@salon-excellence.test',
          MockAuthService.demoOtp,
        );
        expect(res.signedIn, isTrue);
        authProvider = ProAuthProvider();
        for (
          var i = 0;
          i < 60 &&
              (authProvider.isLoading ||
                  (authProvider.isAuthenticated &&
                      authProvider.membership == null));
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        final salon = authProvider.activeSalonId!;
        seeded = MockData.providers
            .firstWhere((p) => p.id == salon)
            .beforeAfters;
        await pro.updateBeforeAfters(salon, const [
          BeforeAfterPair(
            before: 'asset:none-a.png',
            after: 'asset:none-b.png',
          ),
          BeforeAfterPair(
            before: 'asset:none-c.png',
            after: 'asset:none-d.png',
            caption: 'Tresses collées',
          ),
        ]);
      });
      addTearDown(
        () => tester.runAsync(
          () => pro.updateBeforeAfters(authProvider.activeSalonId!, seeded),
        ),
      );

      // Tall enough that both cards are on screen (finders skip off-screen
      // list items).
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrapApp(
          providers: [
            ChangeNotifierProvider.value(value: authProvider),
            ChangeNotifierProvider(create: (_) => ProBeforeAfterProvider()),
          ],
          home: const ProBeforeAfterScreen(),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }

      expect(
        find.text('Supprimer'),
        findsNWidgets(2),
        reason: 'both pairs rendered — the « — » check is not vacuous',
      );
      expect(find.text('Tresses collées'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    },
  );
}
