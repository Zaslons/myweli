import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/notification_preferences.dart';
import 'package:myweli/providers/notification_preferences_provider.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/screens/profile/notification_preferences_screen.dart';
import 'package:myweli/screens/provider/notifications/pro_notifications_screen.dart';
import 'package:myweli/services/interfaces/notification_service_interface.dart';
import 'package:myweli/services/interfaces/push_notification_service_interface.dart';
import 'package:myweli/widgets/push/push_blocked_banner.dart';
import 'package:myweli/widgets/push/push_off_card.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

class _MockNotificationService extends Mock
    implements NotificationServiceInterface {}

/// consumer-signin-push.md §2.9 and §2.11 (decisions 209, 211, 212): a phone
/// never asked gets « Activer les notifications », in the client's
/// Préférences and on MyWeli Pro's notifications page; Préférences says what
/// is true.
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
    when(
      () => service.getNotifications(),
    ).thenAnswer((_) async => ApiResponse.success(const []));
  });

  Widget prefs({
    required PushPermissionStatus status,
    Future<PushPermissionStatus> Function()? enable,
  }) => wrapApp(
    providers: [
      ChangeNotifierProvider(create: (_) => NotificationPreferencesProvider()),
    ],
    home: NotificationPreferencesScreen(
      permissionStatus: () async => status,
      openSettings: () async {},
      enablePush: enable,
    ),
  );

  group('Préférences', () {
    testWidgets('never asked → the card, and no banner', (tester) async {
      await tester.pumpWidget(
        prefs(status: PushPermissionStatus.notDetermined),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PushOffCard), findsOneWidget);
      expect(find.byType(PushBlockedBanner), findsNothing);
      expect(
        find.text('Notifications non activées sur ce téléphone'),
        findsOneWidget,
      );
      expect(find.text(PushOffCard.clientBody), findsOneWidget);
      expect(find.text('Activer les notifications'), findsOneWidget);
    });

    testWidgets('granted → neither card nor banner', (tester) async {
      await tester.pumpWidget(prefs(status: PushPermissionStatus.granted));
      await tester.pumpAndSettle();
      expect(find.byType(PushOffCard), findsNothing);
      expect(find.byType(PushBlockedBanner), findsNothing);
    });

    testWidgets('refused → the banner, not the card', (tester) async {
      await tester.pumpWidget(prefs(status: PushPermissionStatus.denied));
      await tester.pumpAndSettle();
      expect(find.byType(PushOffCard), findsNothing);
      expect(find.byType(PushBlockedBanner), findsOneWidget);
    });

    testWidgets('« Activer », granted → the card goes, and it is said', (
      tester,
    ) async {
      var asked = 0;
      await tester.pumpWidget(
        prefs(
          status: PushPermissionStatus.notDetermined,
          enable: () async {
            asked++;
            return PushPermissionStatus.granted;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activer les notifications'));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.byType(PushOffCard), findsNothing);
      expect(find.text('Notifications activées'), findsOneWidget);
    });

    testWidgets('« Activer », refused → the banner takes its place', (
      tester,
    ) async {
      await tester.pumpWidget(
        prefs(
          status: PushPermissionStatus.notDetermined,
          enable: () async => PushPermissionStatus.denied,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activer les notifications'));
      await tester.pumpAndSettle();
      expect(find.byType(PushOffCard), findsNothing);
      expect(find.byType(PushBlockedBanner), findsOneWidget);
      expect(find.text('Notifications activées'), findsNothing);
    });

    testWidgets('« Activer », no answer → the card stays, and the failure is '
        'said', (tester) async {
      await tester.pumpWidget(
        prefs(
          status: PushPermissionStatus.notDetermined,
          enable: () async => PushPermissionStatus.notDetermined,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activer les notifications'));
      await tester.pumpAndSettle();
      expect(find.byType(PushOffCard), findsOneWidget);
      expect(find.text('Une erreur est survenue. Réessayez.'), findsOneWidget);
    });

    testWidgets('the two sentences say what is true (decision 211)', (
      tester,
    ) async {
      await tester.pumpWidget(prefs(status: PushPermissionStatus.granted));
      await tester.pumpAndSettle();
      expect(
        find.text('Sur tous les téléphones connectés à votre compte.'),
        findsOneWidget,
      );
      expect(find.text('Notifications sur cet appareil.'), findsNothing);
      expect(
        find.text(
          'Les confirmations et changements de rendez-vous restent toujours '
          'dans « Actu ».',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('toujours envoyés'), findsNothing);
    });
  });

  group('MyWeli Pro (decision 212)', () {
    Widget pro({
      required PushPermissionStatus status,
      Future<PushPermissionStatus> Function()? enable,
    }) => wrapApp(
      providers: [
        ChangeNotifierProvider(
          create: (_) => NotificationsProvider(service: service),
        ),
      ],
      home: ProNotificationsScreen(
        permissionStatus: () async => status,
        openSettings: () async {},
        enablePush: enable,
      ),
    );

    testWidgets('never asked → the card, with the salon\'s reason', (
      tester,
    ) async {
      await tester.pumpWidget(pro(status: PushPermissionStatus.notDetermined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PushOffCard), findsOneWidget);
      expect(find.text(PushOffCard.proBody), findsOneWidget);
      expect(find.text(PushOffCard.clientBody), findsNothing);
      expect(find.byType(PushBlockedBanner), findsNothing);
    });

    testWidgets('granted: neither, as before', (tester) async {
      await tester.pumpWidget(pro(status: PushPermissionStatus.granted));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PushOffCard), findsNothing);
      expect(find.byType(PushBlockedBanner), findsNothing);
    });

    testWidgets('refused: the banner, as before', (tester) async {
      await tester.pumpWidget(pro(status: PushPermissionStatus.denied));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PushOffCard), findsNothing);
      expect(find.byType(PushBlockedBanner), findsOneWidget);
    });
  });
}
