import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/widgets/common/app_async_view.dart';
import 'package:myweli/widgets/common/app_card.dart';
import 'package:myweli/widgets/common/app_skeleton.dart';

import '../support/pump_app.dart';

/// docs/design/hygiene-batch9.md §2.7.2 (B9.8, Q9–Q12) — the three shared
/// pieces SYSTEM.md §11.3 specified and nobody had built: AppAsyncView (the
/// four states, in AdminDataTable's order), AppCard, and the skeletons.
void main() {
  group('AppAsyncView', () {
    Widget view({
      bool isLoading = false,
      String? error,
      List<String>? data,
      VoidCallback? onRetry,
    }) => Scaffold(
      body: AppAsyncView<List<String>>(
        isLoading: isLoading,
        error: error,
        data: data,
        isEmpty: (d) => d.isEmpty,
        loading: const Text('LOADING'),
        empty: const Text('EMPTY'),
        onRetry: onRetry,
        builder: (context, d) => Text('DATA ${d.join(',')}'),
      ),
    );

    testWidgets('loading with nothing yet: the loading shape', (tester) async {
      await pumpApp(tester, home: view(isLoading: true));
      expect(find.text('LOADING'), findsOneWidget);
      expect(find.text('EMPTY'), findsNothing);
    });

    testWidgets('nothing asked yet (no data, no error, not loading): the '
        'loading shape — never a flash of « empty »', (tester) async {
      await pumpApp(tester, home: view());
      expect(find.text('LOADING'), findsOneWidget);
    });

    testWidgets('loading WITH data: the data stays (a reload)', (tester) async {
      await pumpApp(tester, home: view(isLoading: true, data: ['a']));
      expect(find.text('DATA a'), findsOneWidget);
      expect(find.text('LOADING'), findsNothing);
    });

    testWidgets('an error with nothing: the shared error', (tester) async {
      await pumpApp(
        tester,
        home: view(error: kGenericErrorMessage, data: const []),
      );
      expect(find.text('Chargement impossible'), findsOneWidget);
      expect(find.text(kGenericErrorMessage), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('EMPTY'), findsNothing);
    });

    testWidgets('an error WITH data: the data stays (a failed refresh)', (
      tester,
    ) async {
      await pumpApp(
        tester,
        home: view(error: 'x', data: ['a']),
      );
      expect(find.text('DATA a'), findsOneWidget);
      expect(find.text('Chargement impossible'), findsNothing);
    });

    testWidgets('empty: the empty state', (tester) async {
      await pumpApp(tester, home: view(data: const []));
      expect(find.text('EMPTY'), findsOneWidget);
    });

    testWidgets('data: the builder', (tester) async {
      await pumpApp(tester, home: view(data: ['a', 'b']));
      expect(find.text('DATA a,b'), findsOneWidget);
    });

    for (final (state, error) in [
      ('the error', 'x'),
      ('the empty state', null),
    ]) {
      testWidgets('onRefresh: $state is pulled like the content', (
        tester,
      ) async {
        var pulls = 0;
        await pumpApp(
          tester,
          home: Scaffold(
            body: AppAsyncView<List<String>>(
              isLoading: false,
              error: error,
              data: const [],
              isEmpty: (d) => d.isEmpty,
              loading: const Text('LOADING'),
              empty: const Text('EMPTY'),
              onRefresh: () async => pulls++,
              builder: (context, d) => const Text('DATA'),
            ),
          ),
        );
        await tester.fling(
          find.byType(SingleChildScrollView).first,
          const Offset(0, 400),
          1000,
        );
        await tester.pumpAndSettle();
        expect(pulls, 1);
      });
    }
  });

  group('AppErrorView — one error everywhere (Q9)', () {
    testWidgets('no connection: the wifi-off icon and its sentence', (
      tester,
    ) async {
      await pumpApp(
        tester,
        home: const Scaffold(body: AppErrorView(message: kNoConnectionMessage)),
      );
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.text(kNoConnectionMessage), findsOneWidget);
    });

    testWidgets('anything else: the error icon', (tester) async {
      await pumpApp(
        tester,
        home: const Scaffold(body: AppErrorView(message: 'Introuvable.')),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsNothing);
    });

    testWidgets('« Réessayer » only when the screen can retry, and it does', (
      tester,
    ) async {
      var tries = 0;
      await pumpApp(
        tester,
        home: Scaffold(
          body: AppErrorView(message: 'x', onRetry: () => tries++),
        ),
      );
      await tester.tap(find.text('Réessayer'));
      expect(tries, 1);

      await pumpApp(
        tester,
        home: const Scaffold(body: AppErrorView(message: 'x')),
      );
      expect(
        find.text('Réessayer'),
        findsNothing,
        reason: 'a way out that cannot succeed is not one (SYSTEM §12)',
      );
    });
  });

  group('AppCard (SYSTEM §11.3)', () {
    BoxDecoration? decorationOf(WidgetTester tester) {
      final m = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppCard),
              matching: find.byType(Material),
            )
            .first,
      );
      final shape = m.shape as RoundedRectangleBorder?;
      return BoxDecoration(
        color: m.color,
        borderRadius: shape?.borderRadius as BorderRadius?,
        border: shape?.side == BorderSide.none
            ? null
            : Border.fromBorderSide(shape!.side),
      );
    }

    testWidgets('secondary, radiusXL, elevation 0, spacingM padding', (
      tester,
    ) async {
      await pumpApp(
        tester,
        home: const Scaffold(body: AppCard(child: Text('x'))),
      );
      final d = decorationOf(tester)!;
      expect(d.color, AppColors.secondary);
      expect(d.borderRadius, BorderRadius.circular(AppTheme.radiusXL));
      expect(d.border, isNull);
      final m = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(m.elevation, 0);
      final padding = tester.widget<Padding>(
        find.ancestor(of: find.text('x'), matching: find.byType(Padding)).first,
      );
      expect(padding.padding, const EdgeInsets.all(AppTheme.spacingM));
    });

    testWidgets('outlined: a borderStrong hairline', (tester) async {
      await pumpApp(
        tester,
        home: const Scaffold(body: AppCard(outlined: true, child: Text('x'))),
      );
      expect(decorationOf(tester)!.border?.top.color, AppColors.borderStrong);
    });

    testWidgets('tappable: the tap lands, as a button for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpApp(
        tester,
        home: Scaffold(
          body: AppCard(onTap: () => taps++, child: const Text('Salon')),
        ),
      );
      await tester.tap(find.text('Salon'));
      expect(taps, 1);
      expect(
        tester.getSemantics(find.byType(AppCard)),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
          label: 'Salon',
        ),
      );
      handle.dispose();
    });
  });

  group('AppSkeleton — still, on a card, one label (Q11)', () {
    testWidgets('screen readers hear « Chargement… » once, nothing of the '
        'shapes', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        home: const Scaffold(body: SkeletonCardList(count: 3)),
      );
      expect(find.bySemanticsLabel('Chargement…'), findsOneWidget);
      final labels = <String>[];
      void walk(SemanticsNode n) {
        if (n.label.isNotEmpty) labels.add(n.label);
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      var root = tester.getSemantics(find.byType(SkeletonCardList));
      while (root.parent != null) {
        root = root.parent!;
      }
      walk(root);
      expect(labels, ['Chargement…']);
      // And it is ONE node: the shapes' list is a scrollable of its own, a
      // node a screen reader would stop on, with nothing to say.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Chargement…')).childrenCount,
        0,
      );
      handle.dispose();
    });

    testWidgets('the bars are surfaceVariant, on secondary cards', (
      tester,
    ) async {
      await pumpApp(
        tester,
        home: const Scaffold(body: SkeletonCardList(count: 2)),
      );
      final bars = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(SkeletonBar),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((b) => (b.decoration as BoxDecoration).color)
          .toSet();
      expect(bars, {AppColors.surfaceVariant});
      expect(find.byType(AppCard), findsNWidgets(2));
    });

    testWidgets('still: no ticker runs (nothing to slow under reduced '
        'motion, nothing to keep a test pumping)', (tester) async {
      await pumpApp(
        tester,
        home: const Scaffold(
          body: Column(
            children: [
              Expanded(child: SkeletonCardList(count: 2)),
              Expanded(child: SkeletonTileList(count: 2)),
            ],
          ),
        ),
      );
      // `hasScheduledFrame` is set for a plain Text too; a ticker is what a
      // pulse would add — it registers a transient callback each frame.
      expect(tester.binding.transientCallbackCount, 0);

      // The check can fire: the spinner the skeletons replace runs a ticker.
      await pumpApp(
        tester,
        home: const Scaffold(body: CircularProgressIndicator()),
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });
  });
}
