import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/colors.dart';
import '../../providers/admin/admin_auth_provider.dart';

/// Console shell: a NavigationRail (Dashboard, KYC) + logout, hosting the routed
/// child. Design: docs/design/admin-console-ui.md.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    ('/admin/dashboard', Icons.dashboard_outlined, 'Tableau de bord'),
    ('/admin/kyc', Icons.verified_user_outlined, 'KYC'),
  ];

  int _indexFor(String location) {
    final i = _destinations.indexWhere((d) => location.startsWith(d.$1));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _indexFor(location),
            onDestinationSelected: (i) => context.go(_destinations[i].$1),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.spa, color: AppColors.primary),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    tooltip: 'Déconnexion',
                    icon: const Icon(Icons.logout),
                    onPressed: () => context.read<AdminAuthProvider>().logout(),
                  ),
                ),
              ),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.$2),
                  label: Text(d.$3),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
