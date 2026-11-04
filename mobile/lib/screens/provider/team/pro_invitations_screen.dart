import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/failure_messages.dart';
import '../../../core/constants/unnamed_salon.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/team_error_messages.dart';
import '../../../models/team_invitation.dart';
import '../../../models/team_member.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_team_provider.dart';
import '../../../widgets/common/app_async_view.dart';
import '../../../widgets/common/app_skeleton.dart';
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

  /// A refused accept or decline, in the invitee's words
  /// ([invitationActionError]).
  String _actionError(ProTeamProvider team, String failed) =>
      invitationActionError(
        code: team.actionErrorCode,
        message: team.actionError,
        failed: failed,
      );

  Future<void> _accept(TeamInvitation invitation) async {
    // One answer at a time: the tapped card shows it is busy, the others
    // wait ([InvitationCard.locked]).
    if (_busyId != null) return;
    final team = context.read<ProTeamProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = invitation.id);
    if (_gate) return _acceptOnGate(invitation, team, messenger);
    // Nullable: this screen's own tests mount it without a session.
    final auth = context.read<ProAuthProvider?>();
    Future<TeamMember?> accept() => team.acceptMyInvitation(invitation.id);
    // Through the session, which reloads « Mes salons » on a join (B7.6).
    final member = await (auth?.acceptInvitation(accept) ?? accept());
    if (!mounted) return;
    setState(() => _busyId = null);
    AppSnackBar.outcomeOn(
      messenger,
      ok: member != null,
      success:
          'Vous avez rejoint ${salonNameOr(invitation.salonName, kUnnamedSalonInSentence)}',
      error: _actionError(team, invitationAcceptFailedMessage),
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
          'Vous avez rejoint ${salonNameOr(invitation.salonName, kUnnamedSalonInSentence)}',
          kind: SnackKind.success,
        );
      }
      return;
    }
    if (!mounted) return;
    if (await _leaveIfSignedOut(team, auth, messenger)) return;
    final error = _actionError(team, invitationAcceptFailedMessage);
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
        _actionError(team, invitationDeclineFailedMessage),
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
    if (!await auth.endExpiredRejoin()) {
      // The refresh got no answer and the session still stands: offline,
      // not signed out (S4) — the card stays and answers again.
      if (!mounted) return true;
      setState(() {
        _leaving = false;
        _busyId = null;
      });
      AppSnackBar.showOn(
        messenger,
        kNoConnectionMessage,
        kind: SnackKind.error,
      );
      return true;
    }
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
      // Cards are `secondary` on `background` (SYSTEM §3.1): the step that
      // lifts them, now they have no shadow (B9.8 F2).
      backgroundColor: AppColors.background,
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

  Widget _profileBody(ProTeamProvider team) =>
      AppAsyncView<List<TeamInvitation>>(
        isLoading: team.invitationsLoading,
        error: team.invitationsError,
        // Null until asked: the read starts after the first frame.
        data: team.invitationsAsked ? team.myInvitations : null,
        isEmpty: (d) => d.isEmpty,
        loading: const SkeletonCardList(count: 2),
        empty: const EmptyState(
          icon: Icons.mail_outline,
          title: 'Aucune invitation en attente',
        ),
        onRetry: team.loadMyInvitations,
        builder: (context, cards) => ListView.separated(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spacingM),
          itemBuilder: (context, index) => _card(cards[index]),
        ),
      );

  Widget _card(TeamInvitation invitation) => InvitationCard(
    invitation: invitation,
    busy: _busyId == invitation.id,
    // One answer at a time: the other cards wait too, visibly.
    locked: _busyId != null,
    onAccept: () => _accept(invitation),
    onDecline: () => _decline(invitation.id),
  );
}
