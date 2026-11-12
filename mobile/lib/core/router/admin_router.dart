import 'package:go_router/go_router.dart';

import '../../providers/admin/admin_auth_provider.dart';
import '../../screens/admin/admin_audit_screen.dart';
import '../../screens/admin/admin_client_version_screen.dart';
import '../../screens/admin/admin_dashboard_screen.dart';
import '../../screens/admin/admin_dispute_detail_screen.dart';
import '../../screens/admin/admin_disputes_screen.dart';
import '../../screens/admin/admin_kyc_detail_screen.dart';
import '../../screens/admin/admin_kyc_queue_screen.dart';
import '../../screens/admin/admin_login_screen.dart';
import '../../screens/admin/admin_moderation_screen.dart';
import '../../screens/admin/admin_provider_detail_screen.dart';
import '../../screens/admin/admin_providers_screen.dart';
import '../../screens/admin/admin_salon_validation_detail_screen.dart';
import '../../screens/admin/admin_salon_validations_screen.dart';
import '../../screens/admin/admin_user_detail_screen.dart';
import '../../screens/admin/admin_users_screen.dart';
import '../utils/salon_id.dart';

/// Admin console routes. Redirects on [AdminAuthProvider] ([adminRedirect]:
/// the login when signed out, carrying where the admin was going; back there
/// — or to the dashboard — once signed in). Each authed screen wraps itself
/// in `AdminScaffold`. Design: docs/design/admin-console-ui.md.
GoRouter createAdminRouter(AdminAuthProvider auth) => GoRouter(
  initialLocation: '/admin/dashboard',
  refreshListenable: auth,
  redirect: (context, state) => adminRedirect(
    restoring: auth.restoring,
    authenticated: auth.isAuthenticated,
    location: state.uri,
  ),
  routes: [
    GoRoute(path: '/admin', builder: (_, _) => const AdminLoginScreen()),
    GoRoute(
      path: '/admin/dashboard',
      builder: (_, _) => const AdminDashboardScreen(),
    ),
    // « Salons à valider » (B0.18 — salon-go-live-approval.md §4.1). The
    // request's path is the one the admin e-mail links to
    // (`adminValidationLink`: `#/admin/salon-validations/{id}`).
    GoRoute(
      path: '/admin/salon-validations',
      builder: (_, _) => const AdminSalonValidationsScreen(),
    ),
    GoRoute(
      path: '/admin/salon-validations/:id',
      builder: (_, state) => AdminSalonValidationDetailScreen(
        id: SalonId(state.pathParameters['id']!),
      ),
    ),
    GoRoute(path: '/admin/kyc', builder: (_, _) => const AdminKycQueueScreen()),
    GoRoute(
      path: '/admin/reviews',
      builder: (_, _) => const AdminModerationScreen(),
    ),
    GoRoute(
      path: '/admin/providers',
      builder: (_, _) => const AdminProvidersScreen(),
    ),
    GoRoute(
      path: '/admin/providers/:id',
      builder: (_, state) =>
          AdminProviderDetailScreen(id: SalonId(state.pathParameters['id']!)),
    ),
    GoRoute(path: '/admin/users', builder: (_, _) => const AdminUsersScreen()),
    GoRoute(
      path: '/admin/users/:id',
      builder: (_, state) =>
          AdminUserDetailScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/admin/disputes',
      builder: (_, _) => const AdminDisputesScreen(),
    ),
    GoRoute(
      path: '/admin/disputes/:id',
      builder: (_, state) =>
          AdminDisputeDetailScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(path: '/admin/audit', builder: (_, _) => const AdminAuditScreen()),
    GoRoute(
      path: '/admin/client-version',
      builder: (_, _) => const AdminClientVersionScreen(),
    ),
    GoRoute(
      path: '/admin/kyc/:id',
      builder: (_, state) =>
          AdminKycDetailScreen(accountId: state.pathParameters['id']!),
    ),
  ],
);

/// Where the console sends [location] (a GoRouter redirect: null stays).
///
/// - While the stored session is being checked: nowhere yet.
/// - Signed out, anywhere but the login: the login, carrying the place in
///   `?from=` — unless it is the dashboard, where the login lands anyway.
///   That is what lets the admin e-mail's link
///   (`https://admin.myweli.com/#/admin/salon-validations/{id}`, B0.18 §4.1)
///   land on the request after a sign-in; before, every login went to the
///   dashboard and the link was lost.
/// - Signed in, at the login: `from` when [adminReturnTarget] accepts it,
///   else the dashboard.
String? adminRedirect({
  required bool restoring,
  required bool authenticated,
  required Uri location,
}) {
  if (restoring) return null;
  final atLogin = location.path == '/admin';
  if (!authenticated) {
    if (atLogin) return null;
    final from = adminReturnTarget(location.toString());
    if (from == null || from == _home) return '/admin';
    return Uri(path: '/admin', queryParameters: {'from': from}).toString();
  }
  if (atLogin) {
    return adminReturnTarget(location.queryParameters['from']) ?? _home;
  }
  return null;
}

const _home = '/admin/dashboard';

/// The login's `from`, when it is a place in this console — else null.
///
/// **An open door until checked:** `from` arrives in a URL anyone can craft
/// and hand to an admin. Only an absolute path under `/admin/` is accepted:
/// nothing protocol-relative (`//host`), no scheme or host, no backslash
/// (browsers read `\` as `/`), no fragment, no control character, not the
/// login itself, and no `.` or `..` segment — written plainly or
/// percent-encoded — that could climb out of `/admin/`. The segments are
/// read RAW: `Uri.parse` removes dot segments, so `/admin/../x` would
/// already read `/x` there and `/admin/../admin/kyc` would pass as
/// `/admin/kyc`. An encoded slash or backslash inside a segment, or a
/// malformed escape (`%zz`, or bytes that are not UTF-8: `%ff`), is refused
/// too — never thrown, which go_router turned into its error page. Everything else is refused whole:
/// never repaired.
String? adminReturnTarget(String? from) {
  if (from == null || from.isEmpty || from.length > _maxFromLength) {
    return null;
  }
  if (!from.startsWith('/admin/')) return null;
  if (from.contains(_backslash) || from.contains('//') || from.contains('#')) {
    return null;
  }
  if (from.codeUnits.any((c) => c < 0x20 || c == 0x7f)) return null;
  final query = from.indexOf('?');
  final path = query < 0 ? from : from.substring(0, query);
  final segments = path.substring(1).split('/'); // ['admin', …]
  if (segments.length < 2 || segments[1].isEmpty) return null;
  for (final raw in segments) {
    final String segment;
    try {
      segment = Uri.decodeComponent(raw);
    } on ArgumentError {
      return null; // a malformed escape: `%zz`, a lone `%`
    } on FormatException {
      return null; // an escape that is not UTF-8: `%ff`, a cut `%c3`
    }
    if (segment == '.' ||
        segment == '..' ||
        segment.contains('/') ||
        segment.contains(_backslash)) {
      return null;
    }
  }
  final uri = Uri.tryParse(from);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  return from;
}

/// Longer than any place in the console; a `from` past it is not one.
const _maxFromLength = 2048;

/// `\`, which browsers read as `/`. Spelled by its code point: the raw
/// literal `r'\'` reads to the typography pin as an escaped apostrophe
/// (design_system_pin_test.dart, « one apostrophe »).
const _backslash = '\u005c';
