import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/salon_membership_info.dart';
import '../../models/team_member.dart';
import '../../providers/pro_auth_provider.dart';
import '../common/brand_loader.dart';

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

class _SalonPickerSheet extends StatelessWidget {
  const _SalonPickerSheet();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    final salons = auth.salons;
    final activeId = auth.activeSalonId;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXXL),
        ),
      ),
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
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingM,
                AppTheme.spacingM,
                AppTheme.spacingS,
                AppTheme.spacingS,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Mes salons', style: AppTextStyles.titleMedium),
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
    );
  }
}

class _SalonTile extends StatelessWidget {
  const _SalonTile({required this.salon, required this.isActive});

  final SalonMembershipInfo salon;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      teamRoleLabel(salon.role),
      if (salon.isDraft) 'Brouillon — pas encore en ligne',
    ];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            isActive ? AppColors.primary : AppColors.surfaceVariant,
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
            const Icon(Icons.verified,
                size: AppTheme.iconXS, color: AppColors.info),
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
        final messenger = ScaffoldMessenger.of(context);
        if (isActive) {
          navigator.pop();
          return;
        }
        final ok = await auth.switchSalon(salon.salonId);
        if (!ok) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Changement impossible — votre accès à ce salon a peut-être '
                'été retiré.',
              ),
            ),
          );
          return;
        }
        navigator.pop(salon.salonId);
      },
    );
  }
}
