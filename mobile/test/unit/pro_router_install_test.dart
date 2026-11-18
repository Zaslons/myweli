import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/pro_app_extensions.dart';
import 'package:myweli/core/router/pro_router.dart';

/// `ProRouter.build` and `ProRouter.install` (pro-android-signup.md §5.2).
///
/// The Pro app's router is read from a global by the app root, the salon
/// gate and the push handler. Android adds routes to it (`/pro/register`,
/// PR B), iOS adds none, so the router is built from the extensions — once,
/// before anything reads it. An install after a read would leave the reader
/// holding the router without the routes: a sign-up button pushing a path
/// that does not exist. So `install` refuses, loudly.
///
/// Each test file runs in its own isolate, so the global starts empty here.
/// The install case is ONE test, in order: install, read, install again.
GoRoute _route(String path) =>
    GoRoute(path: path, builder: (_, _) => const SizedBox.shrink());

Set<String> _paths(GoRouter r) => {
  for (final route in r.configuration.routes)
    if (route is GoRoute) route.path,
};

void main() {
  test('build(null) is today\'s router: the sign-in, the « Aperçu », no '
      'sign-up', () {
    final paths = _paths(ProRouter.build(null));
    expect(paths, containsAll(['/pro/splash', '/pro/login', '/pro/apercu']));
    expect(paths, isNot(contains('/pro/register')));
  });

  test('build(extensions) adds their routes and keeps every other', () {
    final base = _paths(ProRouter.build(null));
    final extended = _paths(
      ProRouter.build(ProAppExtensions(routes: [_route('/pro/x-extension')])),
    );
    expect(extended, containsAll(base));
    expect(extended.difference(base), {'/pro/x-extension'});
  });

  test('build is pure: each call is a fresh router, the global untouched', () {
    expect(ProRouter.build(null), isNot(same(ProRouter.build(null))));
  });

  test('install puts the extensions in the global router, once — and '
      'refuses after a read', () {
    ProRouter.install(ProAppExtensions(routes: [_route('/pro/x-installed')]));
    expect(_paths(ProRouter.router), contains('/pro/x-installed'));
    expect(ProRouter.router, same(ProRouter.router), reason: 'one router');
    expect(
      () => ProRouter.install(null),
      throwsStateError,
      reason: 'the router was read: a second install would split the app',
    );
  });

  test('launchPaths is unchanged — a pushed sign-up reads as /pro/login', () {
    expect(ProRouter.launchPaths, {'/pro/splash', '/pro/login'});
  });
}
