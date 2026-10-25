import 'package:flutter/material.dart';

import '../../models/team_member.dart';
import '../common/app_chip.dart';

/// The role chip (module `access` §5.1), one tinted pill since B9.8 F3
/// (Q18): Propriétaire gold · Manager the strong tint ·
/// Réception/Collaborateur neutral.
///
/// Gold is the Propriétaire's TINT and BORDER, never its text: `gold` at 11 px
/// on its own 12 % tint measured 2.79:1 on the background and 2.97:1 on a
/// card, under §13.1's 4.5:1 text floor. The label is ink, as on the web
/// (B7.1 — docs/design/pro-app-batch7.md §2.1, SYSTEM.md §21 row 28).
class TeamRoleChip extends StatelessWidget {
  const TeamRoleChip({super.key, required this.role});

  final TeamRole role;

  @override
  Widget build(BuildContext context) => AppChip.status(
    label: teamRoleLabel(role),
    tone: switch (role) {
      TeamRole.owner => AppChipTone.gold,
      TeamRole.manager => AppChipTone.strong,
      _ => AppChipTone.neutral,
    },
  );
}
