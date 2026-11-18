import '../../providers/pro_auth_provider.dart';

/// Where a signed-in Pro lands (docs/design/pro-android-signup.md §5.2,
/// « The landing helper »): the sign-in's rule, out of its `_finish` so the
/// Android sign-up lands the same way (S3, B0.17 PR B) instead of copying it.
///
/// Its paths are no longer `context.go('…')` literals, which
/// `route_literals_test` scans; `pro_landing_route_test` checks each one
/// resolves on the real router instead.
String proLandingRoute(ProAuthProvider auth, String? returnTo) => proLandingFor(
  rejoinPending: auth.rejoinPending,
  isStaff: auth.isStaff,
  returnTo: returnTo,
);

/// The rule, on plain values:
/// - a former member re-invited — signed in, no salon — waits on their
///   invitations (docs/design/pro-rejoin-gate.md §2). FIRST: the session is
///   live, so anything below would open a salon it has lost;
/// - a Collaborateur lands on their shell: [returnTo] may point at owner
///   surfaces they cannot use (access R4b);
/// - everyone else, [returnTo] or « Accueil ».
String proLandingFor({
  required bool rejoinPending,
  required bool isStaff,
  String? returnTo,
}) {
  if (rejoinPending) return '/pro/invitations';
  if (isStaff) return '/pro/staff';
  return returnTo ?? '/pro/dashboard';
}
