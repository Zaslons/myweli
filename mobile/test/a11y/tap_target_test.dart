import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';
import 'package:myweli/widgets/review/review_tile.dart';
import 'package:provider/provider.dart';

import '_a11y.dart';

/// A4a — every interactive element has a ≥48×48 touch target (SYSTEM.md §13.2,
/// register row 12). `androidTapTargetGuideline` is Flutter's own check; before
/// A4a it went red on these components (hand-rolled gestures + a `shrinkWrap`
/// button), which is the whole reason the row existed. Component-level (cheap,
/// precise) — the screen-embedded fixes (contact rows, journal, photo controls)
/// are covered by the goldens + the same pattern.
void main() {
  setUpAll(() {
    initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
  });

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

  testWidgets('CommunePill — the location pill', (tester) async {
    final handle = await pumpForA11y(
      tester,
      CommunePill(commune: 'Cocody', onTap: () {}),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('AdminSegmentedControl — the segments', (tester) async {
    final handle = await pumpForA11y(
      tester,
      AdminSegmentedControl(
        labels: const ['En attente', 'Vérifiés'],
        selected: 0,
        onSelect: (_) {},
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('ReviewTile — the « Signaler » action', (tester) async {
    final handle = await pumpForA11y(
      tester,
      ReviewTile(review: review(), onReport: () {}),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('AppointmentCard — the location + itinéraire rows',
      (tester) async {
    final handle = await pumpForA11y(
      tester,
      AppointmentCard(appointment: appt(), onTap: () {}),
      providers: [ChangeNotifierProvider(create: (_) => ProviderProvider())],
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('NotificationTile — the tile tap', (tester) async {
    final handle = await pumpForA11y(
      tester,
      NotificationTile(notification: note(), onTap: () {}),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
