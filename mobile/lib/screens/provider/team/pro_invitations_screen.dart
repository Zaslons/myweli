import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/team_error_messages.dart';
import '../../../models/team_invitation.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_team_provider.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';
import '../../../widgets/team/invitation_card.dart';
import '../../../widgets/team/revoked_access_banner.dart';

/// « Invitations » — the signed-in pro identity's pending team invitations
/// (module `access` R3 §2.3), in two modes:
///
/// - **Profil → Invitations** (pushed): accepting joins the salon under the
///   CURRENT session; navigation is unchanged (the multi-salon switcher is
///   R6).
/// - **The rejoin gate** (docs/design/pro-rejoin-gate.md §3): a former member
///   re-invited, whose session `ProAuthProvider` holds here instead of
///   signing it out. No way back, no tabs, nothing of the lost salon — the
///   cards and « Déconnexion ». « Rejoindre » enters the joined salon;
///   declining the last card, or the last one turning out expired, signs out
///   with the banner. The cards are the ones the provider already fetched,
///   so there is no loading or error state on the way in.
class ProInvitationsScreen extends StatefulWidget {
  const ProInvitationsScreen({super.key});

  @override
  State<ProInvitationsScreen> createState() => _ProInvitationsScreenState();
}

class _ProInvitationsScreenState extends State<ProInvitationsScreen> {
  String? _busyId;

  /// Opened as the rejoin gate — decided once, at mount. The gate is only
  /// ever reached by a `go`, so it is always a fresh page; latched, it stays
  /// a gate through its own exit (a rejoin, a sign-out) instead of flashing
  /// the ordinary screen while the session changes under it.
  late final bool _gate;

  /// The lost salon, for the gate's banner — null when none is known (§3).
  String? _lostSalon;

  /// Leaving the gate — into the joined salon, or signed out: the whole
  /// screen is the loader (S2).
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // Nullable: this screen's own tests mount it without a session.
    final auth = context.read<ProAuthProvider?>();
    final team = context.read<ProTeamProvider>();
    _gate = auth?.rejoinPending ?? false;
    if (_gate) {
      _lostSalon = auth!.rejoinRevokedSalon;
      team.seedMyInvitations(auth.rejoinInvitations);
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => team.loadMyInvitations(),
      );
    }
  }

  static const _acceptFailed = 'Invitation impossible à accepter.';
  static const _declineFailed = 'Refus impossible.';

  /// A refused accept or decline, in the INVITEE's words — the web's
  /// `invitationActionError`, code for code (S5, S7). `forbidden` here is
  /// the server's address check (T37), where `teamErrorMessage` would tell an
  /// invitee the action is reserved to the salon's owner (G12); a code the
  /// table does not know (a 5xx's `internal_error`) is the action's own line,
  /// not the generic sentence. With no code the service's own sentence
  /// stands — « Pas de connexion. Réessayez. » offline (S4).
  String _actionError(ProTeamProvider team, String failed) {
    final code = team.actionErrorCode;
    if (code == null) return team.actionError ?? failed;
    if (code == 'forbidden') return failed;
    return teamErrorMessage(code, fallback: failed);
  }

  Future<void> _accept(TeamInvitation invitation) async {
    // One answer at a time: only the tapped card shows it is busy.
    if (_busyId != null) return;
    final team = context.read<ProTeamProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = invitation.id);
    if (_gate) return _acceptOnGate(invitation, team, messenger);
    final member = await team.acceptMyInvitation(invitation.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    AppSnackBar.outcomeOn(
      messenger,
      ok: member != null,
      success: 'Vous avez rejoint ${invitation.salonName}',
      error: _actionError(team, _acceptFailed),
    );
  }

  Future<void> _acceptOnGate(
    TeamInvitation invitation,
    ProTeamProvider team,
    ScaffoldMessengerState messenger,
  ) async {
    final auth = context.read<ProAuthProvider>();
    final joined = await auth.acceptRejoin(
      () => team.acceptMyInvitation(invitation.id),
      onAccepted: () {
        if (mounted) setState(() => _leaving = true);
      },
    );
    if (joined != null) {
      // In the joined salon — `completeRejoin` went there — unless the
      // session ended while the answer travelled: then the sign-in is on
      // screen, and « Vous avez rejoint » would contradict it. The root
      // messenger outlives this page, so the message lands on the new one.
      if (auth.isAuthenticated && !auth.rejoinPending) {
        AppSnackBar.showOn(
          messenger,
          'Vous avez rejoint ${invitation.salonName}',
          kind: SnackKind.success,
        );
      }
      return;
    }
    if (!mounted) return;
    if (await _leaveIfSignedOut(team, auth, messenger)) return;
    final error = _actionError(team, _acceptFailed);
    if (team.myInvitations.isNotEmpty) {
      setState(() => _busyId = null);
      AppSnackBar.showOn(messenger, error, kind: SnackKind.error);
      return;
    }
    // Expired or withdrawn meanwhile: the store dropped the card (S3), and
    // none is left (S6). The reason is told only on the sign-out — it rides
    // the root messenger onto the sign-in screen; a card gone because it was
    // accepted elsewhere enters that salon, where « Introuvable » would lie.
    setState(() => _leaving = true);
    if (!await auth.leaveEmptiedRejoin()) {
      AppSnackBar.showOn(messenger, error, kind: SnackKind.error);
    }
  }

  Future<void> _decline(String invitationId) async {
    if (_busyId != null) return;
    final team = context.read<ProTeamProvider>();
    // Nullable: this screen's own tests mount it without a session.
    final auth = context.read<ProAuthProvider?>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = invitationId);
    final ok = await team.declineMyInvitation(invitationId);
    if (!mounted) return;
    if (!ok) {
      if (_gate && await _leaveIfSignedOut(team, auth!, messenger)) return;
      setState(() => _busyId = null);
      AppSnackBar.showOn(
        messenger,
        _actionError(team, _declineFailed),
        kind: SnackKind.error,
      );
    } else if (_gate && team.myInvitations.isEmpty) {
      // The last card declined (S6): the row is « revoked » again
      // server-side, and a session with no salon is not kept — unless the
      // re-check finds one (§2.4).
      setState(() => _leaving = true);
      await auth!.leaveEmptiedRejoin();
    } else {
      setState(() => _busyId = null);
    }
  }

  /// A refusal that says the session itself is gone (`unauthorized` — a
  /// refresh the server refused cleared it): every retry would fail the same
  /// way, so the gate goes to the sign-in and says why. True = left.
  Future<bool> _leaveIfSignedOut(
    ProTeamProvider team,
    ProAuthProvider auth,
    ScaffoldMessengerState messenger,
  ) async {
    if (team.actionErrorCode != 'unauthorized') return false;
    setState(() => _leaving = true);
    await auth.endExpiredRejoin();
    AppSnackBar.showOn(
      messenger,
      'Veuillez vous reconnecter.',
      kind: SnackKind.error,
    );
    return true;
  }

  /// « Déconnexion » (S8) — the plain sign-out the person asked for.
  Future<void> _signOut() async {
    setState(() => _leaving = true);
    await context.read<ProAuthProvider>().signOutRevoked();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Invitations'),
        // The gate has nowhere to go back to (§3) — only out.
        automaticallyImplyLeading: !_gate,
        actions: [
          if (_gate)
            // An icon, not a text action: an action's label scales by the
            // full system scaler while the title is clamped, so a
            // « Déconnexion » TextButton crowds the bar at 200% (SYSTEM.md
            // §13.3, §21 row 79). The tooltip is the label.
            //
            // Held while an answer is out (one answer at a time, the way out
            // included): a sign-out now would be undone by an accept landing
            // after it.
            IconButton(
              onPressed: (_leaving || _busyId != null) ? null : _signOut,
              icon: const Icon(Icons.logout),
              tooltip: 'Déconnexion',
            ),
        ],
      ),
      body: _leaving
          ? const LoadingIndicator()
          : Consumer<ProTeamProvider>(
              builder: (context, team, _) =>
                  _gate ? _gateBody(team) : _profileBody(team),
            ),
    );
  }

  Widget _gateBody(ProTeamProvider team) {
    final cards = team.myInvitations;
    // Never « Aucune invitation » here, and never a sign-out decided from a
    // build: an empty gate is an explicit way out already under way (S3, S6).
    if (cards.isEmpty) return const LoadingIndicator();
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        if (_lostSalon != null) ...[
          RevokedAccessBanner(salonName: _lostSalon!),
          const SizedBox(height: AppTheme.spacingL),
        ],
        Semantics(
          header: true,
          child: Text(
            'Vous êtes invité(e)',
            style: AppTextStyles.headlineSmall,
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        for (final (i, invitation) in cards.indexed) ...[
          if (i > 0) const SizedBox(height: AppTheme.spacingM),
          _card(invitation),
        ],
      ],
    );
  }

  Widget _profileBody(ProTeamProvider team) {
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
      separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spacingM),
      itemBuilder: (context, index) => _card(team.myInvitations[index]),
    );
  }

  Widget _card(TeamInvitation invitation) => InvitationCard(
    invitation: invitation,
    busy: _busyId == invitation.id,
    onAccept: () => _accept(invitation),
    onDecline: () => _decline(invitation.id),
  );
}
