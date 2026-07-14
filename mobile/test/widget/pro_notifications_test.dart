import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/screens/provider/notifications/pro_notifications_screen.dart';
import 'package:myweli/services/interfaces/notification_service_interface.dart';
import 'package:myweli/widgets/common/empty_state.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';
import 'package:myweli/widgets/notifications/notifications_list.dart';
import 'package:provider/provider.dart';

class _MockNotificationService extends Mock
    implements NotificationServiceInterface {}

/// The salon's notification centre (docs/design/push-notifications-fcm.md §10)
/// and the shared feed body behind it. The pro app runs the SAME list on its
/// own session — the service is INJECTED, never taken from the locator.
void main() {
  late _MockNotificationService service;

  setUpAll(() => initializeDateFormatting('fr_FR', null));
  setUp(() => service = _MockNotificationService());

  AppNotification note(String id, {bool read = false, String? route}) =>
      AppNotification(
        id: id,
        type: AppNotificationType.general,
        title: 'Nouvelle réservation',
        body: 'Nouvelle demande de réservation le 28/06/2026 à 14:30.',
        createdAt: DateTime(2026, 6, 28),
        read: read,
        route: route,
      );

  Widget host(
    NotificationsProvider provider, {
    Widget? child,
    void Function(BuildContext, String)? onOpenRoute,
  }) =>
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: child ??
              Scaffold(body: NotificationsList(onOpenRoute: onOpenRoute)),
        ),
      );

  testWidgets(
      'the provider runs the INJECTED service (the pro session), '
      'never the locator', (tester) async {
    when(() => service.getNotifications())
        .thenAnswer((_) async => ApiResponse.success([note('n1')]));

    await tester.pumpWidget(host(NotificationsProvider(service: service)));
    await tester.pumpAndSettle();

    verify(() => service.getNotifications()).called(1);
    expect(find.byType(NotificationTile), findsOneWidget);
  });

  testWidgets('state: loading', (tester) async {
    final pending = Completer<ApiResponse<List<AppNotification>>>();
    when(() => service.getNotifications()).thenAnswer((_) => pending.future);

    await tester.pumpWidget(host(NotificationsProvider(service: service)));
    await tester.pump(); // the post-frame load fires
    await tester.pump();

    expect(find.byType(LoadingIndicator), findsOneWidget);

    pending.complete(ApiResponse.success([]));
    await tester.pumpAndSettle();
  });

  testWidgets('state: error → « Réessayer » reloads', (tester) async {
    when(() => service.getNotifications())
        .thenAnswer((_) async => ApiResponse.error('boom'));

    await tester.pumpWidget(host(NotificationsProvider(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('Chargement impossible'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    verify(() => service.getNotifications()).called(2);
  });

  testWidgets('state: success — unread rows counted', (tester) async {
    when(() => service.getNotifications()).thenAnswer(
      (_) async => ApiResponse.success([note('n1'), note('n2', read: true)]),
    );

    final provider = NotificationsProvider(service: service);
    await tester.pumpWidget(host(provider));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationTile), findsNWidgets(2));
    expect(provider.unreadCount, 1);
  });

  testWidgets(
      'a tap marks the row read AND follows its route — the salon '
      'rides in it (?salon=)', (tester) async {
    when(() => service.getNotifications()).thenAnswer(
      (_) async => ApiResponse.success([
        note('n1', route: '/pro/appointment/a1?salon=p2'),
      ]),
    );
    when(() => service.markRead(any()))
        .thenAnswer((_) async => ApiResponse.success(true));

    final opened = <String>[];
    await tester.pumpWidget(
      host(
        NotificationsProvider(service: service),
        onOpenRoute: (_, route) => opened.add(route),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NotificationTile));
    await tester.pumpAndSettle();

    verify(() => service.markRead('n1')).called(1);
    expect(opened, ['/pro/appointment/a1?salon=p2']);
  });

  testWidgets(
      'the PRO screen: its own chrome (no consumer bottom nav) and '
      'its own empty copy', (tester) async {
    when(() => service.getNotifications())
        .thenAnswer((_) async => ApiResponse.success([]));

    await tester.pumpWidget(
      host(
        NotificationsProvider(service: service),
        child: const ProNotificationsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(
      find.textContaining('réservations, annulations et acomptes'),
      findsOneWidget,
    );
    expect(find.text('Tout lire'), findsNothing); // nothing unread
  });

  testWidgets(
      '« Tout lire » appears only when something is unread, and '
      'clears the badge', (tester) async {
    when(() => service.getNotifications())
        .thenAnswer((_) async => ApiResponse.success([note('n1')]));
    when(() => service.markAllRead())
        .thenAnswer((_) async => ApiResponse.success(true));

    final provider = NotificationsProvider(service: service);
    await tester.pumpWidget(
      host(provider, child: const ProNotificationsScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tout lire'), findsOneWidget);
    await tester.tap(find.text('Tout lire'));
    await tester.pumpAndSettle();

    verify(() => service.markAllRead()).called(1);
    expect(provider.unreadCount, 0);
    expect(find.text('Tout lire'), findsNothing);
  });
}
