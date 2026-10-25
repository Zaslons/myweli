import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/widgets/common/app_chip.dart';
import 'package:myweli/widgets/team/team_role_chip.dart';

import '../support/pump_app.dart';

/// docs/design/hygiene-batch9.md §2.7.4 (B9.8 F3, Q18) — a role is one
/// tinted pill, and the three steps stay three: Propriétaire gold, Manager
/// strong (the brand line), Réception and Collaborateur neutral — as the
/// web's `TeamRoleChip` keeps them (gold · filled · outlined).
void main() {
  for (final (role, tone) in [
    (TeamRole.owner, AppChipTone.gold),
    (TeamRole.manager, AppChipTone.strong),
    (TeamRole.reception, AppChipTone.neutral),
    (TeamRole.staff, AppChipTone.neutral),
  ]) {
    testWidgets('${teamRoleLabel(role)}: $tone', (tester) async {
      await pumpApp(
        tester,
        home: Scaffold(
          body: Center(child: TeamRoleChip(role: role)),
        ),
      );
      expect(tester.widget<AppChip>(find.byType(AppChip)).tone, tone);
      expect(find.text(teamRoleLabel(role)), findsOneWidget);
    });
  }
}
