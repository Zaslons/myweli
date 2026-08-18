import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/external_link.dart';
import '../../widgets/common/settings_tile.dart';

/// « À propos » — the app's legal surface (L1 — docs/design/legal-l1.md).
///
/// **Registered top-level at `/a-propos` in BOTH routers**, not as a `/profile`
/// child. Three reasons, and the first is the one that matters: a store reviewer
/// is never signed in, so a path that reads as account-scoped invites someone to
/// gate it later. It also deep-links cleanly, and it lets the flat
/// `pro_router.dart` register the identical route to the identical screen —
/// one screen, two apps, no capability gate.
///
/// **The documents live on the web, and the app links out.** Rendering them
/// natively would mean a second copy of every legal text, and legal text that
/// drifts between two surfaces is worse than legal text in one place: a user and
/// a regulator would be reading different documents. `AppConfig.siteBaseUrl`
/// defaults to production precisely so a build without defines still points
/// somewhere real.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('À propos')),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingM,
                AppTheme.spacingL,
                AppTheme.spacingM,
                AppTheme.spacingS,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppConstants.appName, style: AppTextStyles.titleLarge),
                  const SizedBox(height: AppTheme.spacingXS),
                  // ONE source, and now the RIGHT one. This printed
                  // `AppConstants.appVersion` — a hand-typed '1.0.0' with no
                  // build number, pinned to nothing, while `pubspec.yaml` held
                  // the real value and both stores read that. Two copies of a
                  // number that must never disagree.
                  //
                  // `PackageInfo` is what the OS actually installed, so it
                  // cannot drift. The build number is shown too, because
                  // « which build is this? » is the question support asks and
                  // the one the version gate compares.
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) {
                      final info = snap.data;
                      return Text(
                        info == null
                            ? 'Version…'
                            : 'Version ${info.version} (${info.buildNumber})',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Politique de confidentialité',
              subtitle: 'Les données que nous traitons, et vos droits',
              trailing: const Icon(
                Icons.open_in_new,
                color: AppColors.textTertiary,
              ),
              onTap: () => openExternalUrl(context, AppConfig.privacyUrl),
            ),
            SettingsTile(
              icon: Icons.gavel_outlined,
              title: 'Conditions d’utilisation',
              subtitle: 'Les règles du service',
              trailing: const Icon(
                Icons.open_in_new,
                color: AppColors.textTertiary,
              ),
              onTap: () => openExternalUrl(context, AppConfig.termsUrl),
            ),
            SettingsTile(
              icon: Icons.business_outlined,
              title: 'Mentions légales',
              subtitle: 'Éditeur et hébergement',
              trailing: const Icon(
                Icons.open_in_new,
                color: AppColors.textTertiary,
              ),
              onTap: () => openExternalUrl(context, AppConfig.legalNoticeUrl),
            ),
            SettingsTile(
              icon: Icons.person_remove_outlined,
              title: 'Supprimer mon compte',
              subtitle: 'Ce qui est supprimé, anonymisé ou conservé',
              trailing: const Icon(
                Icons.open_in_new,
                color: AppColors.textTertiary,
              ),
              onTap: () =>
                  openExternalUrl(context, AppConfig.accountDeletionUrl),
            ),
          ],
        ),
      ),
    );
  }
}
