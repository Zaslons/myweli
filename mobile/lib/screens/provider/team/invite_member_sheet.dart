import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/team_member.dart';
import '../../../providers/pro_artist_provider.dart';
import '../../../providers/pro_team_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_text_field.dart';

/// The 3-step invite sheet (module `access` §5.1): e-mail → rôle (3 cartes)
/// → Collaborateur : fiche employé (picker + « + Créer une fiche » inline).
/// Pops with the invited email on success.
/// Design: docs/design/team-access-r3-app.md §2.1.
class InviteMemberSheet extends StatefulWidget {
  const InviteMemberSheet({super.key, required this.providerId});

  final String providerId;

  @override
  State<InviteMemberSheet> createState() => _InviteMemberSheetState();
}

enum _InviteStep { email, role, artist }

/// Plain-French capability summaries for the role cards (spec-locked copy).
String roleSummary(TeamRole role) => switch (role) {
      TeamRole.manager =>
        'Gère les rendez-vous, le catalogue et les disponibilités. '
            'Ne voit pas les revenus.',
      TeamRole.reception =>
        'Gère le planning et le fichier clients. Pas de catalogue ni de '
            'réglages.',
      TeamRole.staff => 'Voit uniquement son propre planning.',
      TeamRole.owner => '',
    };

class _InviteMemberSheetState extends State<InviteMemberSheet> {
  _InviteStep _step = _InviteStep.email;
  final _emailController = TextEditingController();
  String? _emailError;
  TeamRole? _role;
  String? _artistId;
  bool _creatingArtist = false;
  final _newArtistController = TextEditingController();

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProTeamProvider>().resetInviteState();
      context.read<ProArtistProvider>().loadArtists(widget.providerId);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _newArtistController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim().toLowerCase();
  bool get _emailValid => _emailRegex.hasMatch(_email);

  void _continueFromEmail() {
    if (!_emailValid) {
      setState(() => _emailError = 'Adresse e-mail invalide.');
      return;
    }
    setState(() {
      _emailError = null;
      _step = _InviteStep.role;
    });
  }

  Future<void> _submit() async {
    final team = context.read<ProTeamProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final member = await team.invite(
      email: _email,
      role: _role!,
      artistId: _artistId,
    );
    if (!mounted) return;
    if (member != null) {
      Navigator.of(context).pop(member.email);
      messenger.showSnackBar(
        SnackBar(content: Text('Invitation envoyée à ${member.email}')),
      );
    }
  }

  Future<void> _createArtistInline() async {
    final name = _newArtistController.text.trim();
    if (name.isEmpty) return;
    final artists = context.read<ProArtistProvider>();
    final ok = await artists.createArtist(widget.providerId, {'name': name});
    if (!mounted) return;
    if (ok && artists.artists.isNotEmpty) {
      setState(() {
        _artistId = artists.artists.last.id;
        _creatingArtist = false;
        _newArtistController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = context.watch<ProTeamProvider>();
    return Padding(
      padding: EdgeInsets.only(
        left: AppTheme.spacingL,
        right: AppTheme.spacingL,
        top: AppTheme.spacingL,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppTheme.spacingL,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_step != _InviteStep.email)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() {
                    _step = _step == _InviteStep.artist
                        ? _InviteStep.role
                        : _InviteStep.email;
                  }),
                ),
              Expanded(
                child:
                    Text('Inviter un membre', style: AppTextStyles.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
          ...switch (_step) {
            _InviteStep.email => _emailStep(),
            _InviteStep.role => _roleStep(team),
            _InviteStep.artist => _artistStep(team),
          },
          if (team.inviteError != null) ...[
            const SizedBox(height: AppTheme.spacingM),
            Text(
              team.inviteError!,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
            if (team.inviteErrorCode == 'offer_required' ||
                team.inviteErrorCode == 'seat_limit') ...[
              const SizedBox(height: AppTheme.spacingS),
              AppButton(
                text: team.inviteErrorCode == 'offer_required'
                    ? 'Choisir mon offre'
                    : 'Changer d\'offre',
                type: AppButtonType.secondary,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/pro/subscription');
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _emailStep() => [
        Text(
          'À quelle adresse e-mail envoyer l\'invitation ?',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        AppTextField(
          label: 'E-mail du membre',
          hint: 'exemple@email.com',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          errorText: _emailError,
          onChanged: (_) => setState(() => _emailError = null),
        ),
        const SizedBox(height: AppTheme.spacingM),
        AppButton(
          text: 'Continuer',
          isFullWidth: true,
          onPressed: _emailValid ? _continueFromEmail : null,
        ),
      ];

  List<Widget> _roleStep(ProTeamProvider team) => [
        Text(
          'Quel rôle pour $_email ?',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        for (final role in const [
          TeamRole.manager,
          TeamRole.reception,
          TeamRole.staff,
        ]) ...[
          _RoleCard(
            role: role,
            selected: _role == role,
            onTap: () => setState(() => _role = role),
          ),
          const SizedBox(height: AppTheme.spacingS),
        ],
        const SizedBox(height: AppTheme.spacingS),
        AppButton(
          text: _role == TeamRole.staff ? 'Continuer' : 'Envoyer l\'invitation',
          isFullWidth: true,
          isLoading: team.isInviting,
          onPressed: _role == null || team.isInviting
              ? null
              : () {
                  if (_role == TeamRole.staff) {
                    setState(() => _step = _InviteStep.artist);
                  } else {
                    _submit();
                  }
                },
        ),
      ];

  List<Widget> _artistStep(ProTeamProvider team) {
    final artists = context.watch<ProArtistProvider>();
    return [
      Text(
        'Associer à un membre de l\'équipe',
        style: AppTextStyles.titleSmall,
      ),
      const SizedBox(height: AppTheme.spacingXS),
      Text(
        'Le collaborateur verra le planning de cette fiche employé.',
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppTheme.spacingM),
      if (artists.isLoading)
        const Padding(
          padding: EdgeInsets.all(AppTheme.spacingM),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        )
      else ...[
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final artist in artists.artists)
                InkWell(
                  onTap: () => setState(() => _artistId = artist.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTheme.spacingS,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _artistId == artist.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: _artistId == artist.id
                              ? AppColors.primary
                              : AppColors.textTertiary,
                        ),
                        const SizedBox(width: AppTheme.spacingM),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(artist.name, style: AppTextStyles.bodyLarge),
                              if (artist.specialization != null)
                                Text(
                                  artist.specialization!,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_creatingArtist) ...[
          const SizedBox(height: AppTheme.spacingS),
          AppTextField(
            label: 'Nom de l\'employé',
            controller: _newArtistController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppTheme.spacingS),
          AppButton(
            text: 'Créer la fiche',
            type: AppButtonType.secondary,
            isLoading: artists.isLoading,
            onPressed: _newArtistController.text.trim().isEmpty
                ? null
                : _createArtistInline,
          ),
        ] else
          TextButton.icon(
            onPressed: () => setState(() => _creatingArtist = true),
            icon: const Icon(Icons.add),
            label: const Text('Créer une fiche'),
          ),
      ],
      const SizedBox(height: AppTheme.spacingM),
      AppButton(
        text: 'Envoyer l\'invitation',
        isFullWidth: true,
        isLoading: team.isInviting,
        onPressed: _artistId == null || team.isInviting ? null : _submit,
      ),
    ];
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final TeamRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceVariant : AppColors.secondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderStrong,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.textTertiary,
            ),
            const SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(teamRoleLabel(role), style: AppTextStyles.titleSmall),
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(
                    roleSummary(role),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
