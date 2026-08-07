import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fonts.dart';
import '_a11y.dart';

/// The two hazards [pumpPushedAtWidth] is shaped around — proven, because a
/// precaution nobody has watched fail is indistinguishable from a decoration
/// (§21 row 70).
///
/// Both were mis-stated before they were measured, and the correction matters:
/// the first is not « the sweeps see stale geometry », it is « two of the four
/// sweeps **crash** », which reads like a broken test rather than a caught
/// defect.
void main() {
  setUpAll(loadRealFonts);

  /// A host route carrying a `Text` — the shape [pumpPushedAtWidth] refuses.
  GoRouter routerWithTextHost() => GoRouter(
    initialLocation: '/host/subject',
    routes: [
      GoRoute(
        path: '/host',
        builder: (_, _) => const Scaffold(
          body: SizedBox(
            width: 40,
            height: 12,
            child: Text('une phrase bien trop longue pour quarante points'),
          ),
        ),
        routes: [
          GoRoute(
            path: 'subject',
            builder: (_, _) => const Scaffold(body: Text('le sujet')),
          ),
        ],
      ),
    ],
  );

  testWidgets('HAZARD 1: a host route with TEXT leaves the sweeps unable to '
      'run at all', (tester) async {
    // An offstage route's children stay in `allRenderObjects` and are NEVER
    // LAID OUT — `_RenderTheatre` skips them in layout as well as paint. So
    // `p.size` and `p.getMaxIntrinsicWidth` do not return a stale number: they
    // trip `!debugNeedsLayout` and throw an _AssertionError, which is not a
    // `TestFailure` and does not read like one.
    final router = routerWithTextHost();
    addTearDown(router.dispose);
    await pumpAtWidth(tester, width: 360, routerConfig: router, rounds: 3);

    final unlaid = tester.allRenderObjects
        .whereType<RenderParagraph>()
        .where((p) => !p.hasSize)
        .length;
    expect(
      unlaid,
      greaterThan(0),
      reason:
          'if the offstage host has no unlaid paragraphs, the text-free host '
          'is a precaution against nothing and this file should be deleted',
    );

    expect(
      () => expectNoUndeclaredTruncation(tester, context: 'the hazard'),
      throwsA(isA<AssertionError>()),
      reason: 'the truncation sweep reads p.size on every paragraph it finds',
    );
    expect(
      () => expectNoLegibilityCrush(tester, context: 'the hazard'),
      throwsA(isA<AssertionError>()),
    );
    // The pair — the third sweep survives, because `_isPainted` happens to
    // filter offstage children first. That it is one out of three is exactly
    // why the host must be text-free rather than the sweeps hardened.
    expectNoVerticalClip(tester, context: 'the hazard');
  });

  testWidgets('…and the shipping helper leaves none', (tester) async {
    // The green half — and the reason the host is EMPTY rather than merely
    // text-free. Measured: a bare `IconButton`, tooltip or not, still leaves
    // one unlaid paragraph behind; `SizedBox.shrink()` leaves zero.
    await pumpPushedAtWidth(
      tester,
      width: 360,
      subject: const Scaffold(appBar: null, body: Text('le sujet')),
      rounds: 0,
      leadingIsCustom: true,
    );
    expect(
      tester.allRenderObjects.whereType<RenderParagraph>().where(
        (p) => !p.hasSize,
      ),
      isEmpty,
    );
    expectNoUndeclaredTruncation(tester, context: 'the control');
    expectNoLegibilityCrush(tester, context: 'the control');
    expectNoVerticalClip(tester, context: 'the control');
  });

  testWidgets('HAZARD 2: without a throwing errorBuilder a stray go() is '
      'SILENT — the subject is simply gone', (tester) async {
    // Under `home:` a stray `context.go` threw and surfaced through assertion
    // A. With a router in the tree GoRouter renders its default error page
    // instead: the subject vanishes, `takeException()` is null, and a title
    // assertion would then pass against a screen that is not the subject.
    // Two screens redirect on build today (`my_bookings_screen.dart:48`,
    // `dashboard_screen.dart:49`).
    final router = GoRouter(
      initialLocation: '/host/subject',
      routes: [
        GoRoute(
          path: '/host',
          builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
          routes: [
            GoRoute(path: 'subject', builder: (_, _) => const _Redirector()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpAtWidth(tester, width: 360, routerConfig: router, rounds: 3);

    expect(find.byType(_Redirector), findsNothing);
    expect(
      tester.takeException(),
      isNull,
      reason:
          'nothing complained. That silence is the hazard: the gate would '
          'have measured GoRouter’s error page and called it the subject',
    );
  });

  testWidgets('…and the shipping helper turns it into an exception', (
    tester,
  ) async {
    await pumpPushedAtWidth(
      tester,
      width: 360,
      subject: const _Redirector(),
      rounds: 3,
      leadingIsCustom: true,
    );
    expect(
      tester.takeException(),
      isA<StateError>(),
      reason:
          'the gate router throws rather than routing, so a subject that '
          'navigates away is loud',
    );
  });
}

class _Redirector extends StatefulWidget {
  const _Redirector();
  @override
  State<_Redirector> createState() => _RedirectorState();
}

class _RedirectorState extends State<_Redirector> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => GoRouter.of(context).go('/ailleurs'),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('le sujet'));
}
