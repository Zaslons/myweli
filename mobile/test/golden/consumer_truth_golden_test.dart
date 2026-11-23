import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/cancellation_policy.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/booking/cancellation_notice_box.dart';
import 'package:provider/provider.dart';

import '../support/golden.dart';

/// What A1 made true, as pictures (docs/design/consumer-app-truth.md §2.2,
/// §2.7): the cancel sentence's three tones, and the four chips a past booking
/// can wear — at 200 % text on the floor phone, where a chip is longest.
void main() {
  group('goldens', () {
    final now = DateTime(2026, 6, 22, 12);

    setUpAll(() async {
      await loadRealFonts();
      await initializeDateFormatting('fr_FR', null);
      // The card reads the discovery list (empty here, as for a salon in
      // another commune), which needs its service registered.
      setupDependencyInjection();
    });

    setUp(() => AppClock.freeze(now));
    tearDown(AppClock.restore);

    Appointment appt(String id, AppointmentStatus status, String salon) =>
        Appointment(
          id: id,
          userId: 'u1',
          providerId: const SalonId('p1'),
          serviceIds: const ['s1'],
          appointmentDate: DateTime(2026, 6, 10, 15),
          status: status,
          totalPrice: 20000,
          depositAmount: 5000,
          depositScreenshotUrl: 'p.jpg',
          createdAt: DateTime(2026),
          providerName: salon,
          serviceNames: const ['Tresses'],
        );

    Widget page(List<Widget> children) => ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, c) in children.indexed) ...[
              if (i > 0) const SizedBox(height: AppTheme.spacingM),
              c,
            ],
          ],
        ),
      ),
    );

    // The three tones, from the real function, so the picture shows the
    // sentences the app says.
    final at = DateTime(2026, 6, 21, 18);
    final notices = [
      cancellationNotice(
        appt(
          'n',
          AppointmentStatus.pending,
          'A',
        ).copyWith(appointmentDate: at, depositScreenshotUrl: ''),
        at.subtract(const Duration(days: 2)),
      )!,
      cancellationNotice(
        appt(
          'r',
          AppointmentStatus.confirmed,
          'A',
        ).copyWith(appointmentDate: at),
        at.subtract(const Duration(days: 2)),
      )!,
      cancellationNotice(
        appt(
          'k',
          AppointmentStatus.confirmed,
          'A',
        ).copyWith(appointmentDate: at),
        at.subtract(const Duration(hours: 5)),
      )!,
    ];

    for (final (name, size, scale) in [
      ('consumer_cancel_notice_tones', const Size(390, 560), 1.0),
      ('consumer_cancel_notice_tones_w360_x2', const Size(360, 1100), 2.0),
    ]) {
      testWidgets('the cancel sentence: neutral, returned, kept ($name)', (
        tester,
      ) async {
        goldenSurface(tester, size: size, scale: scale);
        await tester.pumpWidget(
          goldenApp(
            child: page([
              for (final n in notices) CancellationNoticeBox(notice: n),
            ]),
          ),
        );
        await tester.pump();
        await expectGolden(tester, name);
      });
    }

    testWidgets('« Passés »: the four chips of a past booking, at 200 %', (
      tester,
    ) async {
      goldenSurface(tester, size: const Size(360, 2000), scale: 2);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ProviderProvider(),
          child: goldenApp(
            child: SingleChildScrollView(
              child: page([
                for (final (id, status, salon) in const [
                  ('u', AppointmentStatus.pending, 'Beauté Awa'),
                  ('c', AppointmentStatus.confirmed, 'Studio Kady'),
                  ('d', AppointmentStatus.completed, 'Salon Ivoire'),
                  ('a', AppointmentStatus.noShow, 'Chez Mariam'),
                ])
                  AppointmentCard(
                    appointment: appt(id, status, salon),
                    onTap: () {},
                  ),
              ]),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Non confirmé'), findsOneWidget, reason: 'C');
      expect(find.text('Absent'), findsOneWidget, reason: 'C');
      await expectGolden(tester, 'consumer_past_chips_w360_x2');
    });
  }, skip: kGoldensSkip);
}
