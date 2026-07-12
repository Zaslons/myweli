import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/team_error_messages.dart';
import '../../../models/team_member.dart';
import '../../../providers/pro_artist_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_subscription_provider.dart';
import '../../../providers/pro_team_provider.dart';
import '../../../widgets/common/brand_refresh.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';
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
    final providerId = context.read<ProAuthProvider>().provider?.providerId;
    if (providerId == null) return;
    _subsRequested = true;
    context.read<ProSubscriptionProvider>().load(providerId);
  }

  Future<void> _openInviteSheet() async {
    final providerId = context.read<ProAuthProvider>().provider?.providerId;
    if (providerId == null) return;
    final invited = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(
            value: context.read<ProTeamProvider>(),
          ),
          ChangeNotifierProvider.value(
            value: context.read<ProArtistProvider>(),
          ),
        ],
        child: InviteMemberSheet(providerId: providerId),
      ),
    );
    if (invited != null) _loadAll();
  }

  Future<void> _openActionsSheet(TeamMember member) async {
    final salonName =
        context.read<ProAuthProvider>().provider?.businessName ?? 'votre salon';
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
    final account = context.watch<ProAuthProvider>().provider;
    if (account?.providerId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Équipe')),
        body: const EmptyState(
          icon: Icons.group_outlined,
          title: 'Réservé au propriétaire',
          description: 'L\'équipe du salon est gérée par son propriétaire.',
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

  Widget _body(ProTeamProvider team) {
    if (team.isLoading && team.members.isEmpty) {
      return const LoadingIndicator();
    }
    if (team.error != null && team.members.isEmpty) {
      return EmptyState(
        icon: Icons.wifi_off,
        title: 'Une erreur est survenue',
        description: team.error,
        actionText: 'Réessayer',
        onAction: _loadAll,
      );
    }
    // "Empty" = the owner alone (their own row always exists).
    if (team.members.length <= 1) {
      return ListView(
        padding: const EdgeInsets.all(AppTheme.spacingM),
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
      );
    }

    return BrandRefresh(
      onRefresh: () async => _loadAll(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingM,
          AppTheme.spacingM,
          AppTheme.spacingM,
          96, // clear the FAB
        ),
        itemCount: team.members.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingS),
        itemBuilder: (context, index) {
          if (index == 0) return const _SeatsHeader();
          final member = team.members[index - 1];
          return _MemberRow(
            member: member,
            onTap: member.isOwner ? null : () => _openActionsSheet(member),
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
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppColors.border),
      ),
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
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
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
    return Card(
      margin: EdgeInsets.zero,
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
      lines.add(Text(
        'Employé : ${member.artistName}',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textSecondary,
        ),
      ));
    }
    if (member.status == TeamMemberStatus.revoked) {
      lines.add(Text(
        'Accès révoqué',
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
      ));
    } else if (member.isPending) {
      if (member.expired) {
        lines.add(Text(
          'Expirée — renvoyez l\'invitation',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
        ));
      } else {
        lines.add(Text(
          'Invitation envoyée'
          '${member.expiresAt != null ? ' · expire le '
              '${Formatters.formatDate(member.expiresAt!)}' : ''}',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ));
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
                'Renvoyer l\'invitation (${member.resendsLeft} '
                'restant${member.resendsLeft > 1 ? 's' : ''})',
              ),
              enabled: member.resendsLeft > 0,
              onTap:
                  member.resendsLeft > 0 ? () => _resend(context, team) : null,
            ),
          if (member.status != TeamMemberStatus.revoked)
            ListTile(
              leading:
                  const Icon(Icons.person_off_outlined, color: AppColors.error),
              title: const Text(
                'Révoquer l\'accès',
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Rôle de ${member.email} : ${teamRoleLabel(role)}.',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            team.actionErrorCode == 'artist_required'
                ? teamErrorMessage('artist_required')
                : (team.actionError ?? 'Action impossible.'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _resend(BuildContext context, ProTeamProvider team) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await team.resend(member.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Invitation renvoyée à ${member.email}.'
              : (team.actionError ?? 'Renvoi impossible.'),
        ),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }

  Future<void> _revoke(BuildContext context, ProTeamProvider team) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Révoquer l\'accès ?'),
        content: Text(
          '${member.email} perdra immédiatement l\'accès à $salonName. '
          'Son compte MyWeli n\'est pas supprimé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await team.revoke(member.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Accès de ${member.email} révoqué.'
              : (team.actionError ?? 'Révocation impossible.'),
        ),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }
}
