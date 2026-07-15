import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../providers/admin/admin_auth_provider.dart';

class _NavItem {
  const _NavItem(this.path, this.icon, this.label);
  final String path;
  final IconData icon;
  final String label;
}

class _NavGroup {
  const _NavGroup(this.title, this.items);
  final String title;
  final List<_NavItem> items;
}

// Only built routes appear here; later slices add Avis / Salons / Clients /
// Litiges / Audit as they ship (no dead links).
const _groups = [
  _NavGroup('Vue', [
    _NavItem('/admin/dashboard', Icons.dashboard_outlined, "Vue d'ensemble"),
  ]),
  _NavGroup('Modération', [
    _NavItem('/admin/kyc', Icons.verified_user_outlined, 'KYC'),
    _NavItem('/admin/reviews', Icons.flag_outlined, 'Avis'),
  ]),
  _NavGroup('Marché', [
    _NavItem('/admin/providers', Icons.storefront_outlined, 'Salons'),
    _NavItem('/admin/users', Icons.people_outline, 'Clients'),
  ]),
  _NavGroup('Opérations', [
    _NavItem('/admin/disputes', Icons.gavel_outlined, 'Litiges'),
    _NavItem('/admin/audit', Icons.history, 'Journal'),
  ]),
];

/// The admin console frame: a grouped sidebar + a top bar with the page [title]
/// and optional [actions], wrapping the screen [child]. Each screen uses it
/// directly. Design: docs/design/admin-console-ui.md §2.
class AdminScaffold extends StatelessWidget {
  const AdminScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.showBack = false,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  /// Show a back affordance in the top bar (detail screens).
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(currentPath: GoRouterState.of(context).uri.path),
          const VerticalDivider(width: 1, color: AppColors.divider),
          Expanded(
            child: Column(
              children: [
                _TopBar(title: title, actions: actions, showBack: showBack),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.actions,
    this.showBack = false,
  });
  final String title;
  final List<Widget> actions;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: AppColors.secondary,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
      child: Row(
        children: [
          if (showBack)
            Padding(
              padding: const EdgeInsets.only(right: AppTheme.spacingS),
              child: IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back, size: AppTheme.iconS),
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(_parentPath(context)),
              ),
            ),
          Text(title, style: AppTextStyles.headlineSmall),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// Fallback when there's no back-stack (e.g. a deep-link): the parent list path.
String _parentPath(BuildContext context) {
  final loc = GoRouterState.of(context).uri.path;
  final i = loc.lastIndexOf('/');
  final parent = i > 0 ? loc.substring(0, i) : '';
  return parent.isEmpty ? '/admin/dashboard' : parent;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.currentPath});
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.spacingL,
                AppTheme.spacingL, AppTheme.spacingL, AppTheme.spacingM),
            child: Row(
              children: [
                const Icon(Icons.spa,
                    size: AppTheme.iconS, color: AppColors.primary),
                const SizedBox(width: AppTheme.spacingS),
                Text('Myweli · Admin', style: AppTextStyles.titleMedium),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final group in _groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacingL,
                        AppTheme.spacingSM,
                        AppTheme.spacingL,
                        AppTheme.spacingXS),
                    child: Text(
                      group.title,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ),
                  for (final item in group.items)
                    _NavTile(
                      item: item,
                      active: currentPath.startsWith(item.path),
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.spacingL,
                AppTheme.spacingS, AppTheme.spacingS, AppTheme.spacingS),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Admin',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ),
                IconButton(
                  tooltip: 'Déconnexion',
                  icon: const Icon(Icons.logout, size: AppTheme.iconS),
                  onPressed: () => context.read<AdminAuthProvider>().logout(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.active});
  final _NavItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.surfaceVariant : Colors.transparent,
      child: InkWell(
        onTap: () => context.go(item.path),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingM, vertical: AppTheme.spacingSM),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: AppTheme.iconS,
                color: active ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: AppTheme.spacingSM),
              Text(
                item.label,
                style: (active
                        ? AppTextStyles.titleSmall
                        : AppTextStyles.bodyMedium)
                    .copyWith(
                  color:
                      active ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
