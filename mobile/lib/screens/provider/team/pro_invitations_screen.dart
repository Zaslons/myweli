import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../providers/pro_team_provider.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';
import '../../../widgets/team/invitation_card.dart';

/// « Invitations » — the signed-in pro identity's pending team invitations
/// (module `access` R3 §2.3). Accepting joins the salon under the CURRENT
/// session; navigation is unchanged (the multi-salon switcher is R6).
class ProInvitationsScreen extends StatefulWidget {
  const ProInvitationsScreen({super.key});

  @override
  State<ProInvitationsScreen> createState() => _ProInvitationsScreenState();
}

class _ProInvitationsScreenState extends State<ProInvitationsScreen> {
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ProTeamProvider>().loadMyInvitations(),
    );
  }

  Future<void> _accept(String invitationId, String salonName) async {
    final team = context.read<ProTeamProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = invitationId);
    final member = await team.acceptMyInvitation(invitationId);
    if (!mounted) return;
    setState(() => _busyId = null);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          member != null
              ? 'Vous avez rejoint $salonName'
              : (team.actionError ?? 'Invitation impossible à accepter.'),
        ),
        backgroundColor: member != null ? null : AppColors.error,
      ),
    );
  }

  Future<void> _decline(String invitationId) async {
    final team = context.read<ProTeamProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = invitationId);
    final ok = await team.declineMyInvitation(invitationId);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(team.actionError ?? 'Refus impossible.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Invitations')),
      body: Consumer<ProTeamProvider>(
        builder: (context, team, _) {
          if (team.invitationsLoading && team.myInvitations.isEmpty) {
            return const LoadingIndicator();
          }
          if (team.myInvitations.isEmpty) {
            return const EmptyState(
              icon: Icons.mail_outline,
              title: 'Aucune invitation en attente',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            itemCount: team.myInvitations.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppTheme.spacingM),
            itemBuilder: (context, index) {
              final invitation = team.myInvitations[index];
              return InvitationCard(
                invitation: invitation,
                busy: _busyId == invitation.id,
                onAccept: () => _accept(invitation.id, invitation.salonName),
                onDecline: () => _decline(invitation.id),
              );
            },
          );
        },
      ),
    );
  }
}
