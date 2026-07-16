import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';
import 'package:myweli/widgets/provider/provider_card.dart';
import 'package:myweli/widgets/review/review_tile.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '_a11y.dart';

/// A4c — the rendered contrast holds in real widgets (SYSTEM.md §13.1, register
/// row 14 gate). A1 fixed the *tokens*; `textContrastGuideline` is Flutter's own
/// check that the *painted* text clears WCAG AA against the colour behind it.
void main() {
  setUpAll(() {
    initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
  });

  List<SingleChildWidget> favProviders() => [
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ];

  Review review() => Review(
        id: 'r1',
        providerId: 'p1',
        userId: 'u1',
        userName: 'Marie Diallo',
        rating: 5,
        text: 'Super service',
        createdAt: DateTime(2025, 2, 4),
      );

  Appointment appt() => Appointment(
        id: 'a1',
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDate: DateTime(2026, 6, 30, 10),
        status: AppointmentStatus.confirmed,
        totalPrice: 20000,
        createdAt: DateTime(2026),
      );

  AppNotification note() => AppNotification(
        id: '1',
        type: AppNotificationType.bookingConfirmed,
        title: 'Rendez-vous confirmé',
        body: 'Salon Excellence',
        createdAt: DateTime(2026, 6, 29, 10),
        read: false,
      );

  testWidgets('CommunePill', (tester) async {
    final handle = await pumpForA11y(
      tester,
      CommunePill(commune: 'Cocody', onTap: () {}),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('AdminSegmentedControl', (tester) async {
    final handle = await pumpForA11y(
      tester,
      AdminSegmentedControl(
        labels: const ['En attente', 'Vérifiés'],
        selected: 0,
        onSelect: (_) {},
      ),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('ReviewTile', (tester) async {
    final handle = await pumpForA11y(
      tester,
      ReviewTile(review: review(), onReport: () {}),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('AppointmentCard', (tester) async {
    final handle = await pumpForA11y(
      tester,
      AppointmentCard(appointment: appt(), onTap: () {}),
      providers: [ChangeNotifierProvider(create: (_) => ProviderProvider())],
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('NotificationTile', (tester) async {
    final handle = await pumpForA11y(
      tester,
      NotificationTile(notification: note(), onTap: () {}),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('ProviderCard (list)', (tester) async {
    final handle = await pumpForA11y(
      tester,
      ProviderCard(provider: MockData.providers.first, onTap: () {}),
      providers: favProviders(),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
