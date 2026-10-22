import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/team_error_messages.dart';
import '../../models/team_invitation.dart';
import '../../providers/pro_auth_provider.dart';
import '../../providers/pro_team_provider.dart';
import '../common/app_snack_bar.dart';
import 'invitation_card.dart';

/// « Invitations d’équipe » — the account's own pending invitations, at the
/// top of « Accueil » and of the Collaborateur's « Journée »
/// (docs/design/pro-app-batch7.md §2.6, B7.6, decision 23). The web's card
/// (`web/components/pro/ProInvitationsCard.tsx`): « Rejoindre » / « Refuser »
/// in place, where before only a row in Profil said an invitation waited.
///
/// - **Nothing at all** when there is none — no title, no room kept — and
///   when the list could not be read: silent, as on the web.
/// - **Read** on mount and whenever the acting salon changes: a switch
///   empties the list ([ProTeamProvider.resetForSalonSwitch] — the rejoin
///   gate leans on that reset, so it stays), and a switch does not remount
///   the host. The host's pull reads it again too.
/// - **One answer at a time**: every button waits while one is out.
/// - « Profil » keeps its row and its count; both read the same list.
class ProInvitationsCard extends StatefulWidget {
  const ProInvitationsCard({super.key});

  @override
  State<ProInvitationsCard> createState() => _ProInvitationsCardState();
}

class _ProInvitationsCardState extends State<ProInvitationsCard> {
  static const Object _never = Object();

  /// The salon the list was last read for; a different one reads it again.
  /// [_never] at first, so the first build reads whatever the salon is.
  Object? _readFor = _never;

  /// The card whose answer is out — null when none is.
  String? _busyId;

  void _readIfSalonChanged(String? salonId) {
    if (salonId == _readFor) return;
    _readFor = salonId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProTeamProvider>().loadMyInvitations();
    });
  }

  String _error(ProTeamProvider team, String failed) => invitationActionError(
    code: team.actionErrorCode,
    message: team.actionError,
    failed: failed,
  );

  Future<void> _accept(TeamInvitation invitation) async {
    if (_busyId != null) return;
    final team = context.read<ProTeamProvider>();
    final auth = context.read<ProAuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = invitation.id);
    // Through the session: a join reloads « Mes salons ».
    final joined = await auth.acceptInvitation(
      () => team.acceptMyInvitation(invitation.id),
    );
    if (mounted) setState(() => _busyId = null);
    // An expired or vanished card is already gone from the list; the
    // sentence says why.
    AppSnackBar.outcomeOn(
      messenger,
      ok: joined != null,
      success: 'Vous avez rejoint ${invitation.salonName}',
      error: _error(team, invitationAcceptFailedMessage),
    );
  }

  /// No confirmation — the web asks none either.
  Future<void> _decline(TeamInvitation invitation) async {
    if (_busyId != null) return;
    final team = context.read<ProTeamProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = invitation.id);
    final declined = await team.declineMyInvitation(invitation.id);
    if (mounted) setState(() => _busyId = null);
    if (!declined) {
      AppSnackBar.showOn(
        messenger,
        _error(team, invitationDeclineFailedMessage),
        kind: SnackKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _readIfSalonChanged(
      context.select<ProAuthProvider, String?>((a) => a.activeSalonId),
    );
    final cards = context.select<ProTeamProvider, List<TeamInvitation>>(
      (t) => t.myInvitations,
    );
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Invitations d’équipe',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingSM),
          for (final (i, invitation) in cards.indexed) ...[
            if (i > 0) const SizedBox(height: AppTheme.spacingM),
            InvitationCard(
              invitation: invitation,
              busy: _busyId == invitation.id,
              locked: _busyId != null,
              onAccept: () => _accept(invitation),
              onDecline: () => _decline(invitation),
            ),
          ],
        ],
      ),
    );
  }
}
