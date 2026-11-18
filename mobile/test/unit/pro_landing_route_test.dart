import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/router/pro_landing.dart';
import 'package:myweli/core/router/pro_router.dart';

/// Where a signed-in Pro lands (pro-android-signup.md §5.2, « The landing
/// helper »). The sign-in's rule, moved out of `_finish` so the Android
/// sign-up lands the same way (S3, PR B) instead of copying it.
///
/// Moving it out of a `context.go(...)` call also moves its three paths out
/// of `route_literals_test`'s scanner, which reads navigation calls. So this
/// file checks each landing resolves on the real router, which the scanner
/// used to do for them.
void main() {
  final router = ProRouter.build(null);
  bool resolves(String location) =>
      router.configuration.findMatch(Uri.parse(location)).isNotEmpty;

  test('a former member re-invited waits on their invitations, first — '
      'whatever else is true', () {
    expect(
      proLandingFor(rejoinPending: true, isStaff: true, returnTo: '/pro/x'),
      '/pro/invitations',
    );
  });

  test('a Collaborateur lands on their shell, never on returnTo', () {
    expect(
      proLandingFor(
        rejoinPending: false,
        isStaff: true,
        returnTo: '/pro/earnings',
      ),
      '/pro/staff',
    );
  });

  test('an owner or manager lands on returnTo, else the dashboard', () {
    expect(
      proLandingFor(
        rejoinPending: false,
        isStaff: false,
        returnTo: '/pro/earnings',
      ),
      '/pro/earnings',
    );
    expect(
      proLandingFor(rejoinPending: false, isStaff: false, returnTo: null),
      '/pro/dashboard',
    );
  });

  test('every landing it can give is a route the app has', () {
    for (final l in [
      proLandingFor(rejoinPending: true, isStaff: false, returnTo: null),
      proLandingFor(rejoinPending: false, isStaff: true, returnTo: null),
      proLandingFor(rejoinPending: false, isStaff: false, returnTo: null),
    ]) {
      expect(resolves(l), isTrue, reason: l);
    }
    expect(resolves('/pro/nowhere'), isFalse, reason: 'the control');
  });
}
