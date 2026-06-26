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
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

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
                _TopBar(title: title, actions: actions),
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
  const _TopBar({required this.title, required this.actions});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: AppColors.secondary,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
      child: Row(
        children: [
          Text(title, style: AppTextStyles.headlineSmall),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                const Icon(Icons.spa, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
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
                  icon: const Icon(Icons.logout, size: 18),
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                size: 18,
                color: active ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
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
