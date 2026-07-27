import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/a11y/reduce_motion.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/app_locale.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// The behaviour-test app shell (SYSTEM.md §21 row 21).
///
/// Widget tests used to wrap their subject in a bare `MaterialApp(home: …)` with
/// no `theme:`, so the whole suite would stay green while the product restyled
/// underneath it. `wrapApp` wraps it in the **real** `AppTheme.lightTheme`
/// instead — the same theme `goldenApp` renders (test/support/golden.dart),
/// minus the golden font pin (behaviour tests run at natural size).
///
/// It's a BUILDER, not a pumper, because every widget test already has a
/// `Widget wrap/host/app()` builder returning a `MaterialApp` — so a migration
/// changes only the builder's body and leaves the call sites (and each file's
/// hand-rolled `settle()`) untouched. Pass exactly one of [home] / [routerConfig];
/// [providers] takes any provider shape (`create`, `.value`, or a mix) as a flat
/// list and is `MultiProvider`-wrapped when non-empty.
Widget wrapApp({
  Widget? home,
  RouterConfig<Object>? routerConfig,
  List<SingleChildWidget>? providers,
  // A6: a feedback test drives the messenger DIRECTLY (`AppSnackBar.showOn`),
  // which is also the shape 38 call sites use — capture before the await.
  GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey,
}) {
  assert(
    (home == null) != (routerConfig == null),
    'wrapApp: pass exactly one of home / routerConfig',
  );

  // A9: the `intl` half of French, which the delegates below do not cover.
  // The three app roots call this at boot; a shell that skipped it would let a
  // `table_calendar` render « July 2026 » in a passing test — which is exactly
  // how it reached production. Idempotent.
  initAppLocale();

  // A9: the three app roots declare these, so the shell that claims to be
  // "the real app minus the golden font pin" has to as well — otherwise every
  // behaviour test renders English Material defaults the product never shows.
  // **Plural `delegates`**: `MaterialApp` always appends
  // `DefaultCupertinoLocalizations.delegate`, which supports only `en`, and the
  // singular pairing makes `_debugCheckLocalizations` fail every test here.
  Widget app = home != null
      ? MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('fr', 'FR')],
          scaffoldMessengerKey: scaffoldMessengerKey,
          home: home,
        )
      : MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('fr', 'FR')],
          scaffoldMessengerKey: scaffoldMessengerKey,
          routerConfig: routerConfig,
        );

  // A8: the three app roots wrap `MaterialApp` in this, so the shell that
  // claims to be "the real app minus the golden font pin" has to as well.
  // Without it, a mid-session Reduce Motion toggle is untestable here — and
  // every behaviour test would silently exercise the no-scope fallback instead
  // of the path that actually ships.
  app = ReduceMotionObserver(child: app);

  if (providers != null && providers.isNotEmpty) {
    app = MultiProvider(providers: providers, child: app);
  }
  return app;
}

/// `wrapApp` + `pumpWidget`, for the few tests without their own builder.
Future<void> pumpApp(
  WidgetTester tester, {
  Widget? home,
  RouterConfig<Object>? routerConfig,
  List<SingleChildWidget>? providers,
}) =>
    tester.pumpWidget(
      wrapApp(home: home, routerConfig: routerConfig, providers: providers),
    );
