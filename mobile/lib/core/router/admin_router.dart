import 'package:go_router/go_router.dart';

import '../../providers/admin/admin_auth_provider.dart';
import '../../screens/admin/admin_dashboard_screen.dart';
import '../../screens/admin/admin_kyc_detail_screen.dart';
import '../../screens/admin/admin_kyc_queue_screen.dart';
import '../../screens/admin/admin_login_screen.dart';
import '../../screens/admin/admin_shell.dart';

/// Admin console routes. Redirects on [AdminAuthProvider] (login when signed
/// out; dashboard when signed in and on the login screen). Design:
/// docs/design/admin-console-ui.md.
GoRouter createAdminRouter(AdminAuthProvider auth) => GoRouter(
      initialLocation: '/admin/dashboard',
      refreshListenable: auth,
      redirect: (context, state) {
        // Hold redirects until the stored session has been checked.
        if (auth.restoring) {
          return null;
        }
        final atLogin = state.uri.path == '/admin';
        if (!auth.isAuthenticated) return atLogin ? null : '/admin';
        if (atLogin) return '/admin/dashboard';
        return null;
      },
      routes: [
        GoRoute(path: '/admin', builder: (_, __) => const AdminLoginScreen()),
        ShellRoute(
          builder: (_, __, child) => AdminShell(child: child),
          routes: [
            GoRoute(
              path: '/admin/dashboard',
              builder: (_, __) => const AdminDashboardScreen(),
            ),
            GoRoute(
              path: '/admin/kyc',
              builder: (_, __) => const AdminKycQueueScreen(),
            ),
            GoRoute(
              path: '/admin/kyc/:id',
              builder: (_, state) =>
                  AdminKycDetailScreen(accountId: state.pathParameters['id']!),
            ),
          ],
        ),
      ],
    );
