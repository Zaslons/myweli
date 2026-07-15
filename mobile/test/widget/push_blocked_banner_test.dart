import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/notification_preferences.dart';
import 'package:myweli/providers/notification_preferences_provider.dart';
import 'package:myweli/screens/profile/notification_preferences_screen.dart';
import 'package:myweli/services/interfaces/notification_service_interface.dart';
import 'package:myweli/services/interfaces/push_notification_service_interface.dart';
import 'package:myweli/widgets/push/push_blocked_banner.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

class _MockNotificationService extends Mock
    implements NotificationServiceInterface {}

/// The one dead end the app can't fix from the inside: notifications denied at
/// the OS level. No in-app toggle can bring them back — so the prefs screen
/// says so and opens the system settings
/// (docs/design/push-notifications-app.md).
void main() {
  late _MockNotificationService service;

  setUpAll(() {
    service = _MockNotificationService();
    serviceLocator.notificationService = service;
  });

  setUp(() {
    reset(service);
    when(() => service.getPreferences()).thenAnswer(
      (_) async => ApiResponse.success(const NotificationPreferences()),
    );
  });

  Widget host({
    required PushPermissionStatus status,
    Future<void> Function()? onOpen,
  }) =>
      wrapApp(
        providers: [
          ChangeNotifierProvider(
              create: (_) => NotificationPreferencesProvider())
        ],
        home: NotificationPreferencesScreen(
          permissionStatus: () async => status,
          openSettings: onOpen ?? () async {},
        ),
      );

  testWidgets(
      'DENIED → the banner explains why the toggles can’t help, and '
      '« Ouvrir les réglages » opens the OS settings', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      host(
        status: PushPermissionStatus.denied,
        onOpen: () async => opened++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PushBlockedBanner), findsOneWidget);
    expect(
      find.text('Notifications désactivées pour l’appareil'),
      findsOneWidget,
    );

    await tester.tap(find.text('Ouvrir les réglages'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('granted → no banner (the toggles alone govern)', (tester) async {
    await tester.pumpWidget(host(status: PushPermissionStatus.granted));
    await tester.pumpAndSettle();

    expect(find.byType(PushBlockedBanner), findsNothing);
    // The three preference switches still render.
    expect(find.text('Notifications push'), findsOneWidget);
  });

  testWidgets('notDetermined → no banner (nothing to re-enable yet)',
      (tester) async {
    await tester.pumpWidget(host(status: PushPermissionStatus.notDetermined));
    await tester.pumpAndSettle();

    expect(find.byType(PushBlockedBanner), findsNothing);
  });
}
