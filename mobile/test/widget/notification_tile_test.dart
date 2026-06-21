import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  AppNotification note({bool read = false}) => AppNotification(
        id: '1',
        type: AppNotificationType.bookingConfirmed,
        title: 'Rendez-vous confirmé',
        body: 'Salon Excellence',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        read: read,
      );

  testWidgets('renders the title and body', (tester) async {
    await tester.pumpWidget(
      wrap(NotificationTile(notification: note(), onTap: () {})),
    );

    expect(find.text('Rendez-vous confirmé'), findsOneWidget);
    expect(find.text('Salon Excellence'), findsOneWidget);
  });

  testWidgets('fires onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(NotificationTile(notification: note(), onTap: () => tapped = true)),
    );

    await tester.tap(find.byType(NotificationTile));
    expect(tapped, isTrue);
  });
}
