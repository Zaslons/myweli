import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
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
}) {
  assert(
    (home == null) != (routerConfig == null),
    'wrapApp: pass exactly one of home / routerConfig',
  );

  Widget app = home != null
      ? MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: home,
        )
      : MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          routerConfig: routerConfig,
        );

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
