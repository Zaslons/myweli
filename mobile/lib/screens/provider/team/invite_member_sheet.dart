import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/forms/field_errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../models/team_member.dart';
import '../../../providers/pro_artist_provider.dart';
import '../../../providers/pro_team_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/inline_feedback.dart';

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
  TeamRole? _role;
  String? _artistId;
  bool _creatingArtist = false;
  final _newArtistController = TextEditingController();

  // A7/§14 — the LAST of the five e-mail regexes. It also accepted a
  // single-character TLD, which the shared strict rule rejects.
  //
  // `_role` and `_artistId` are in the map too: their faults have no field to
  // sit under, so they surface form-level (decision 8) — but they are still
  // rules, and keeping them here means one place decides what "ready" means.
  late final _errors = FieldErrors({
    'email': Validators.email,
    'role': Validators.requiredField('un rôle'),
    'artist': Validators.requiredField('la fiche employé du collaborateur'),
    'artistName': Validators.requiredField('le nom de l\'employé'),
  });
  final _emailFocus = FocusNode();
  final _artistNameFocus = FocusNode();

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
    _emailFocus.dispose();
    _artistNameFocus.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim().toLowerCase();

  void _continueFromEmail() {
    // Before A7 this could not run unless the e-mail was ALREADY valid — the
    // button was gated on exactly that — so the `errorText` it set was
    // unreachable. It was the codebase's only field-anchored error, and it
    // never rendered once.
    if (!_errors.validate({'email': _emailController.text})) {
      setState(() {});
      _emailFocus.requestFocus();
      return;
    }
    setState(() => _step = _InviteStep.role);
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
      AppSnackBar.showOn(messenger, 'Invitation envoyée à ${member.email}',
          kind: SnackKind.success);
    }
  }

  Future<void> _createArtistInline() async {
    // It used to `return` on an empty name — a press that did nothing at all.
    if (!_errors.validate({'artistName': _newArtistController.text})) {
      setState(() {});
      _artistNameFocus.requestFocus();
      return;
    }
    final name = _newArtistController.text.trim();
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
      // A7/§13.3: the sheet must scroll. Adding twelve pixels of feedback
      // overflowed it — which means it was already overflowing at any raised
      // text scale, and with the keyboard up. Same class as A6's dialog
      // `scrollable: true`, found the same way: by a message that needed room.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_step != _InviteStep.email)
                  IconButton(
                    tooltip: 'Retour',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() {
                      _step = _step == _InviteStep.artist
                          ? _InviteStep.role
                          : _InviteStep.email;
                    }),
                  ),
                Expanded(
                  child: Text('Inviter un membre',
                      style: AppTextStyles.titleLarge),
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
              // A6's in-modal slot, replacing a hand-rolled red Text: a snackbar
              // here would be pruned by the sheet's ModalBarrier, and a bare Text
              // is not a live region — so this failure was silent either way.
              InlineFeedback(team.inviteError),
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
          focusNode: _emailFocus,
          errorText: _errors['email'],
          onChanged: (v) => setState(() => _errors.revalidate('email', v)),
        ),
        const SizedBox(height: AppTheme.spacingM),
        AppButton(
          text: 'Continuer',
          isFullWidth: true,
          // §14 rule 5 — and the reason the errorText above is now reachable.
          onPressed: _continueFromEmail,
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
        // A role is a SELECTION — no field to sit under, so §14's fault lands
        // form-level (the three-slot boundary).
        InlineFeedback(_errors['role']),
        AppButton(
          text: _role == TeamRole.staff ? 'Continuer' : 'Envoyer l\'invitation',
          isFullWidth: true,
          isLoading: team.isInviting,
          onPressed: team.isInviting
              ? null
              : () {
                  if (!_errors.validate({'role': _role?.name ?? ''})) {
                    setState(() {});
                    return;
                  }
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
                          size: AppTheme.iconS,
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
            focusNode: _artistNameFocus,
            errorText: _errors['artistName'],
            onChanged: (v) =>
                setState(() => _errors.revalidate('artistName', v)),
          ),
          const SizedBox(height: AppTheme.spacingS),
          AppButton(
            text: 'Créer la fiche',
            type: AppButtonType.secondary,
            isLoading: artists.isLoading,
            onPressed: artists.isLoading ? null : _createArtistInline,
          ),
        ] else
          TextButton.icon(
            onPressed: () => setState(() => _creatingArtist = true),
            icon: const Icon(Icons.add),
            label: const Text('Créer une fiche'),
          ),
      ],
      const SizedBox(height: AppTheme.spacingM),
      InlineFeedback(_errors['artist']),
      AppButton(
        text: 'Envoyer l\'invitation',
        isFullWidth: true,
        isLoading: team.isInviting,
        onPressed: team.isInviting
            ? null
            : () {
                if (!_errors.validate({'artist': _artistId ?? ''})) {
                  setState(() {});
                  return;
                }
                _submit();
              },
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
