import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/consumer_bottom_nav.dart';

import '../support/pump_app.dart';

/// **The label and the destination, asserted together.**
///
/// Every assertion here taps a tab by its VISIBLE FRENCH LABEL and then checks
/// which route the app actually landed on. Pinning either alone is what let the
/// strip be misread: the four screens declared « Carte » at index 1 and pushed
/// `/favorites`, a route that builds `MapScreen` — correct behaviour under a
/// name that contradicted it. A test of the item list would have passed. A test
/// of the destinations would have passed. Only the pair shows that « Carte »
/// opens the map, which is PRD FR-FAV-001's « favorites map view ».
///
/// A fifth, unreachable copy of the strip lived in `favorites_screen.dart` —
/// registered on no route, referenced by nothing — declaring `Favoris` and
/// `Profil` instead. It is deleted; this file is why no sixth appears.
///
/// The *highlighted* tab is not asserted here: `consumer_screens_golden_test`
/// photographs the home and bookings screens, so a screen passing the wrong
/// `current` moves a baseline.
void main() {
  /// A router whose destinations render their own path, so an assertion can
  /// name the route rather than a screen that happens to sit on it.
  GoRouter routerFor(ConsumerTab current) => GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (_, _) => Scaffold(
          body: const Center(child: Text('HOST')),
          bottomNavigationBar: ConsumerBottomNav(current: current),
        ),
      ),
      for (final tab in ConsumerTab.values)
        GoRoute(
          path: tab.route,
          builder: (_, _) => Scaffold(body: Center(child: Text(tab.route))),
        ),
    ],
  );

  Future<void> pumpAt(WidgetTester tester, ConsumerTab current) async {
    await pumpApp(tester, routerConfig: routerFor(current));
    await tester.pumpAndSettle();
  }

  group('the four tabs are the four tabs', () {
    testWidgets('exactly four, in order, each with its icon', (tester) async {
      await pumpAt(tester, ConsumerTab.accueil);

      expect(find.byType(BottomNavigationBarItem), findsNothing);
      final bar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bar.items.map((i) => i.label).toList(), [
        'Accueil',
        'Carte',
        'Rendez-vous',
        'Actu',
      ]);
      expect(bar.items.map((i) => (i.icon as Icon).icon).toList(), [
        Icons.home,
        Icons.map,
        Icons.calendar_today,
        Icons.notifications_none,
      ]);
    });

    testWidgets('and « Carte » is the map, not a favourites list', (
      tester,
    ) async {
      // The one that started this. `/carte` builds `MapScreen`; the route used
      // to be called `/favorites`, which is what made a correct tab look wrong.
      expect(ConsumerTab.carte.route, '/carte');
      expect(ConsumerTab.carte.label, 'Carte');
      expect(ConsumerTab.carte.icon, Icons.map);
    });
  });

  group('tapping a label lands on that label\'s destination', () {
    // Every (from, to) pair — 4 hosts × 3 other tabs. The strip is shared, so
    // this covers home, carte, bookings and notifications at once, which is the
    // point of extracting it.
    for (final from in ConsumerTab.values) {
      for (final to in ConsumerTab.values.where((t) => t != from)) {
        testWidgets('from ${from.label}, « ${to.label} » → ${to.route}', (
          tester,
        ) async {
          await pumpAt(tester, from);
          expect(find.text('HOST'), findsOneWidget);

          await tester.tap(find.text(to.label));
          await tester.pumpAndSettle();

          expect(
            find.text(to.route),
            findsOneWidget,
            reason:
                'tapping « ${to.label} » must open ${to.route} — a label that '
                'does not lead where it says is the defect this file exists for',
          );
        });
      }
    }
  });

  group('the tab you are already on', () {
    for (final tab in ConsumerTab.values) {
      testWidgets('${tab.label} does not re-push itself', (tester) async {
        await pumpAt(tester, tab);
        await tester.tap(find.text(tab.label));
        await tester.pumpAndSettle();

        // Still the host, not a second copy of the screen stacked on itself
        // with the back button pointing at the same place.
        expect(find.text('HOST'), findsOneWidget);
        expect(find.text(tab.route), findsNothing);
      });
    }
  });

  group('Accueil is the root, and the others sit on top of it', () {
    testWidgets('Accueil replaces the stack rather than growing it', (
      tester,
    ) async {
      final router = routerFor(ConsumerTab.actu);
      await tester.pumpWidget(wrapApp(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accueil'));
      await tester.pumpAndSettle();

      expect(find.text('/home'), findsOneWidget);
      expect(
        router.routerDelegate.canPop(),
        isFalse,
        reason:
            'Accueil uses `go`: pushing it would leave a back button that '
            'returns to the screen the user just left the tab strip from',
      );
    });

    testWidgets('the other tabs push, so back returns', (tester) async {
      final router = routerFor(ConsumerTab.accueil);
      await tester.pumpWidget(wrapApp(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rendez-vous'));
      await tester.pumpAndSettle();

      expect(find.text('/bookings'), findsOneWidget);
      expect(router.routerDelegate.canPop(), isTrue);
    });
  });
}
