import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';
import 'package:myweli/widgets/provider/provider_card.dart';
import 'package:myweli/widgets/review/review_tile.dart';
import 'package:myweli/widgets/team/team_role_chip.dart';
import 'package:provider/provider.dart';

import '_a11y.dart';
import '_fixtures.dart';

/// A4c — the rendered contrast holds in real widgets (SYSTEM.md §13.1, register
/// row 14 gate). A1 fixed the *tokens*; `textContrastGuideline` is Flutter's own
/// check that the *painted* text clears WCAG AA against the colour behind it.
void main() {
  setUpAll(() {
    initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
  });

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

  // B7.1 — the « Propriétaire » label was `gold` (11 px) on a 12 % gold tint:
  // 2.79:1 on the background, 2.97:1 on a white card (SYSTEM §21 row 28).
  // Measured where it shows: the team list's card and the page background.
  for (final (name, surface) in [
    ('on the background', null),
    ('on a white card', Colors.white),
  ]) {
    testWidgets('TeamRoleChip — Propriétaire $name', (tester) async {
      const chip = TeamRoleChip(role: TeamRole.owner);
      final handle = await pumpForA11y(
        tester,
        surface == null
            ? const Center(child: chip)
            : ColoredBox(
                color: surface,
                child: const Center(child: chip),
              ),
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

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
