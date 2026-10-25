import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/team_error_messages.dart';
import '../../../models/pro_membership.dart';
import '../../../models/team_member.dart';
import '../../../providers/pro_artist_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_subscription_provider.dart';
import '../../../providers/pro_team_provider.dart';
import '../../../widgets/common/app_async_view.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/common/app_skeleton.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/brand_refresh.dart';
import '../../../widgets/common/confirm_dialog.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/team/team_role_chip.dart';
import 'invite_member_sheet.dart';

/// « Équipe » — the owner's member roster (module `access` §5.1): list /
/// invite / change role / resend / revoke, with the offer's seats header.
/// Server authority: every mutation is owner-gated backend-side (T36).
/// Design: docs/design/team-access-r3-app.md §2.1.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  /// The auth session loads asynchronously — the seats header's
  /// subscription fetch waits for the providerId to materialize.
  bool _subsRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  void _loadAll() {
    context.read<ProTeamProvider>().load();
    _subsRequested = false;
    _maybeLoadSubscription();
  }

  void _maybeLoadSubscription() {
    if (_subsRequested) return;
    final providerId = context.read<ProAuthProvider>().activeSalonId;
    if (providerId == null) return;
    _subsRequested = true;
    context.read<ProSubscriptionProvider>().load(providerId);
  }

  Future<void> _openInviteSheet() async {
    final providerId = context.read<ProAuthProvider>().activeSalonId;
    if (providerId == null) return;
    final invited = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: context.read<ProTeamProvider>()),
          ChangeNotifierProvider.value(
            value: context.read<ProArtistProvider>(),
          ),
          // The offer state this screen loaded — the sheet reads it to tell
          // a setup salon from an expired one on `offer_required`.
          ChangeNotifierProvider.value(
            value: context.read<ProSubscriptionProvider>(),
          ),
        ],
        child: InviteMemberSheet(providerId: providerId),
      ),
    );
    if (invited != null) _loadAll();
  }

  Future<void> _openActionsSheet(TeamMember member) async {
    // The ACTING salon (R6) — the account's `businessName` is a sign-up copy
    // of its default salon (docs/design/r6-salon-fact-reads.md §2.2).
    final salonName = context.read<ProAuthProvider>().salonName;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ProTeamProvider>(),
        child: _MemberActionsSheet(member: member, salonName: salonName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    // R6: the gate is the ACTING salon's capability. The account's default
    // `providerId` says whether it owns A salon, not this one — an owner
    // switched to a salon they only manage passed it
    // (docs/design/r6-salon-id-pin.md).
    if (auth.activeSalonId == null || !auth.can(ProCap.membersManage)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Équipe')),
        body: const EmptyState(
          icon: Icons.group_outlined,
          title: 'Réservé au propriétaire',
          description: 'L’équipe du salon est gérée par son propriétaire.',
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeLoadSubscription(),
    );
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Équipe')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openInviteSheet,
        icon: const Icon(Icons.person_add),
        label: const Text('Inviter un membre'),
      ),
      body: Consumer<ProTeamProvider>(
        builder: (context, team, _) => _body(team),
      ),
    );
  }

  Widget _body(ProTeamProvider team) => AppAsyncView<List<TeamMember>>(
    isLoading: team.isLoading,
    error: team.error,
    data: team.members,
    // "Empty" = the owner alone (their own row always exists).
    isEmpty: (d) => d.length <= 1,
    loading: const SkeletonCardList(lead: SkeletonLead.avatar),
    // A column, not a list: the pull around it is the scroll view.
    empty: Padding(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: Column(
        children: [
          const _SeatsHeader(),
          const SizedBox(height: AppTheme.spacingXL),
          EmptyState(
            icon: Icons.group_outlined,
            title: 'Invitez votre équipe',
            description:
                'Chaque membre a son propre accès. Les collaborateurs ne '
                'voient que leur propre planning.',
            actionText: 'Inviter un membre',
            onAction: _openInviteSheet,
          ),
        ],
      ),
    ),
    onRetry: _loadAll,
    onRefresh: () async => _loadAll(),
    builder: (context, members) => _members(members),
  );

  Widget _members(List<TeamMember> members) {
    return BrandRefresh(
      onRefresh: () async => _loadAll(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingM,
          AppTheme.spacingM,
          AppTheme.spacingM,
          AppTheme.fabClearance,
        ),
        itemCount: members.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppTheme.spacingS),
        itemBuilder: (context, index) {
          if (index == 0) return const _SeatsHeader();
          final member = members[index - 1];
          return _MemberRow(
            member: member,
            // The owner and a revoked member are inert, as on the web: a
            // revoked member's only action would be « Changer le rôle »,
            // which the server refuses (409 member_revoked — B7.5).
            onTap: member.isOwner || member.status == TeamMemberStatus.revoked
                ? null
                : () => _openActionsSheet(member),
          );
        },
      ),
    );
  }
}

/// « {used} / {cap} places » from the salon's offer (hidden in setup state).
class _SeatsHeader extends StatelessWidget {
  const _SeatsHeader();

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<ProSubscriptionProvider>();
    final seats = subs.salon?.seats;
    if (seats == null) return const SizedBox.shrink();
    final ratio = seats.cap == 0 ? 0.0 : seats.used / seats.cap;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${seats.used} / ${seats.cap} places',
            style: AppTextStyles.titleSmall,
          ),
          const SizedBox(height: AppTheme.spacingS),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, this.onTap});

  final TeamMember member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = member.email.isEmpty ? '?' : member.email[0].toUpperCase();
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.surfaceVariant,
          child: Text(initial, style: AppTextStyles.titleMedium),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                member.email,
                style: AppTextStyles.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppTheme.spacingS),
            TeamRoleChip(role: member.role),
          ],
        ),
        subtitle: _subtitle(),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget? _subtitle() {
    final lines = <Widget>[];
    if (member.role == TeamRole.staff && member.artistName != null) {
      lines.add(
        Text(
          'Employé : ${member.artistName}',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    if (member.status == TeamMemberStatus.revoked) {
      lines.add(
        Text(
          'Accès révoqué',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
        ),
      );
    } else if (member.isPending) {
      if (member.expired) {
        lines.add(
          Text(
            'Expirée — renvoyez l’invitation',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        );
      } else {
        lines.add(
          Text(
            'Invitation envoyée'
            '${member.expiresAt != null ? ' · expire le '
                      '${Formatters.formatDate(member.expiresAt!)}' : ''}',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        );
      }
    }
    if (lines.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }
}

/// Actions on a non-owner member: changer le rôle · renvoyer · révoquer.
class _MemberActionsSheet extends StatelessWidget {
  const _MemberActionsSheet({required this.member, required this.salonName});

  final TeamMember member;
  final String salonName;

  @override
  Widget build(BuildContext context) {
    final team = context.watch<ProTeamProvider>();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    member.email,
                    style: AppTextStyles.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TeamRoleChip(role: member.role),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Changer le rôle'),
            onTap: () => _changeRole(context),
          ),
          if (member.isPending)
            ListTile(
              leading: const Icon(Icons.forward_to_inbox_outlined),
              title: Text(
                'Renvoyer l’invitation (${member.resendsLeft} '
                'restant${member.resendsLeft > 1 ? 's' : ''})',
              ),
              enabled: member.resendsLeft > 0,
              onTap: member.resendsLeft > 0
                  ? () => _resend(context, team)
                  : null,
            ),
          if (member.status != TeamMemberStatus.revoked)
            ListTile(
              leading: const Icon(
                Icons.person_off_outlined,
                color: AppColors.error,
              ),
              title: const Text(
                'Révoquer l’accès',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () => _revoke(context, team),
            ),
          const SizedBox(height: AppTheme.spacingS),
        ],
      ),
    );
  }

  Future<void> _changeRole(BuildContext context) async {
    final team = context.read<ProTeamProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final role = await showModalBottomSheet<TeamRole>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: Text('Nouveau rôle', style: AppTextStyles.titleMedium),
            ),
            for (final r in const [
              TeamRole.manager,
              TeamRole.reception,
              TeamRole.staff,
            ])
              ListTile(
                title: Text(teamRoleLabel(r)),
                subtitle: Text(
                  roleSummary(r),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                trailing: member.role == r
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(r),
              ),
          ],
        ),
      ),
    );
    if (role == null || role == member.role) return;
    final ok = await team.changeRole(member.id, role: role);
    navigator.pop();
    if (ok) {
      AppSnackBar.showOn(
        messenger,
        'Rôle de ${member.email} : ${teamRoleLabel(role)}.',
        kind: SnackKind.success,
      );
    } else {
      AppSnackBar.showOn(
        messenger,
        team.actionErrorCode == 'artist_required'
            ? teamErrorMessage('artist_required')
            : (team.actionError ?? 'Action impossible.'),
        kind: SnackKind.error,
      );
    }
  }

  Future<void> _resend(BuildContext context, ProTeamProvider team) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await team.resend(member.id);
    navigator.pop();
    AppSnackBar.outcomeOn(
      messenger,
      ok: ok,
      success: 'Invitation renvoyée à ${member.email}.',
      error: team.actionError ?? 'Renvoi impossible.',
    );
  }

  Future<void> _revoke(BuildContext context, ProTeamProvider team) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Révoquer l’accès ?',
      message:
          '${member.email} perdra immédiatement l’accès à $salonName. '
          'Son compte MyWeli n’est pas supprimé.',
      confirmLabel: 'Révoquer',
    );
    // No `mounted` here by design: this is a stateless row, and the messenger
    // and navigator were captured BEFORE the dialog — the census flagged the
    // old `confirmed != true` as a missing guard, but the capture is the fix.
    if (!confirmed) return;
    final ok = await team.revoke(member.id);
    navigator.pop();
    AppSnackBar.outcomeOn(
      messenger,
      ok: ok,
      success: 'Accès de ${member.email} révoqué.',
      error: team.actionError ?? 'Révocation impossible.',
    );
  }
}
