import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/salon_membership_info.dart';
import '../../models/team_member.dart';
import '../../providers/pro_auth_provider.dart';
import '../common/brand_loader.dart';
import '../common/inline_feedback.dart';

/// « Mes salons » (module `access` R6 — docs/design/
/// team-access-r6-multi-salons.md §6): the salon switcher bottom sheet.
/// Lists every membership (owned first) with the caller's role there and
/// the salon state; tapping switches the acting salon (per-salon state is
/// reset by [ProAuthProvider.switchSalon]). « Ajouter un salon » appears
/// when the server says the account may (live Réseau offer).
///
/// Returns the switched-to salon id, `'add'` when the add flow was chosen,
/// or null (dismissed / switch refused).
Future<String?> showSalonPicker(BuildContext context) {
  // Refresh in place — the sheet opens on cached data instantly.
  context.read<ProAuthProvider>().loadMySalons();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SalonPickerSheet(),
  );
}

class _SalonPickerSheet extends StatefulWidget {
  const _SalonPickerSheet();

  @override
  State<_SalonPickerSheet> createState() => _SalonPickerSheetState();
}

class _SalonPickerSheetState extends State<_SalonPickerSheet> {
  /// A6: a failed switch keeps the user IN the sheet — they may want another
  /// salon — so the reason renders here. A snackbar would be pruned by the
  /// modal barrier and painted under the scrim.
  String? _error;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    final salons = auth.salons;
    final activeId = auth.activeSalonId;

    // Flutter 3.44 asserts on this (list_tile.dart `_findIntermediateWidget`): a
    // ListTile paints its ink on the nearest Material ANCESTOR, so a coloured box
    // between the two hides the ripple. The tap feedback on these rows has been
    // invisible for as long as the surface has existed — the assertion is new, the
    // defect is not.
    //
    // `MaterialType.transparency` paints nothing, so the surface above is untouched
    // and the goldens do not move; it exists only to give the ink somewhere to
    // land, above the background instead of behind it.
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXXL),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppTheme.spacingS),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingM,
                ),
                child: InlineFeedback(_error),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingM,
                  AppTheme.spacingM,
                  AppTheme.spacingS,
                  AppTheme.spacingS,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Mes salons',
                        style: AppTextStyles.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (auth.isLoading && salons.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppTheme.spacingL),
                  child: BrandLoader(size: AppTheme.iconL, fast: true),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ...salons.map(
                        (s) => _SalonTile(
                          salon: s,
                          isActive: s.salonId == activeId,
                          onFailed: (msg) => setState(() => _error = msg),
                        ),
                      ),
                      if (auth.canAddSalon) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                            Icons.add_business_outlined,
                            color: AppColors.textPrimary,
                          ),
                          title: const Text('Ajouter un salon'),
                          subtitle: const Text(
                            'Offre Réseau — un salon de plus dans votre compte',
                            style: AppTextStyles.bodySmall,
                          ),
                          onTap: () => Navigator.of(context).pop('add'),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: AppTheme.spacingS),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalonTile extends StatelessWidget {
  const _SalonTile({
    required this.salon,
    required this.isActive,
    required this.onFailed,
  });

  final SalonMembershipInfo salon;
  final bool isActive;

  /// Reports a failed switch up to the sheet, which renders it inline.
  final ValueChanged<String> onFailed;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      teamRoleLabel(salon.role),
      if (salon.isDraft) 'Brouillon — pas encore en ligne',
    ];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isActive
            ? AppColors.primary
            : AppColors.surfaceVariant,
        foregroundColor: isActive ? AppColors.secondary : AppColors.textPrimary,
        child: Text(
          salon.salonName.isEmpty
              ? '?'
              : salon.salonName.characters.first.toUpperCase(),
          style: AppTextStyles.titleSmall.copyWith(
            color: isActive ? AppColors.secondary : AppColors.textPrimary,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              salon.salonName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (salon.verified) ...[
            const SizedBox(width: AppTheme.spacingXS),
            const Icon(
              Icons.verified,
              size: AppTheme.iconXS,
              color: AppColors.info,
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        style: AppTextStyles.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isActive
          ? const Icon(Icons.check, color: AppColors.textPrimary)
          : null,
      selected: isActive,
      onTap: () async {
        final auth = context.read<ProAuthProvider>();
        final navigator = Navigator.of(context);
        if (isActive) {
          navigator.pop();
          return;
        }
        final ok = await auth.switchSalon(salon.salonId);
        if (!ok) {
          onFailed(
            'Changement impossible — votre accès à ce salon a '
            'peut-être été retiré.',
          );
          return;
        }
        navigator.pop(salon.salonId);
      },
    );
  }
}
