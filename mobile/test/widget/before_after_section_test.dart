import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/before_after_pair.dart';
import 'package:myweli/widgets/providers/before_after_section.dart';

import '../support/pump_app.dart';

Widget _host(List<BeforeAfterPair> pairs) => wrapApp(
      home: Scaffold(
        body: SingleChildScrollView(child: BeforeAfterSection(pairs: pairs)),
      ),
    );

/// Asset bytes aren't bundled in `flutter test`, so `TimedCachedImage` throws
/// "Unable to load asset" during layout. Swallow only those so the structural
/// assertions stand. Must run inside the test body (the binding installs its own
/// handler after setUp).
void _ignoreAssetImageErrors() {
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('Unable to load asset')) return;
    prev?.call(details);
  };
}

void main() {
  testWidgets('renders the slider, Avant/Après labels + caption',
      (tester) async {
    _ignoreAssetImageErrors();
    await tester.pumpWidget(_host(const [
      BeforeAfterPair(
          before: 'asset:a.png', after: 'asset:b.png', caption: 'Tresses'),
    ]));

    expect(find.byType(BeforeAfterSlider), findsOneWidget);
    expect(find.text('Avant'), findsOneWidget);
    expect(find.text('Après'), findsOneWidget);
    expect(find.text('Tresses'), findsOneWidget);
    expect(find.textContaining('Glisser pour comparer'), findsOneWidget);
  });

  testWidgets('shows a thumbnail strip + only the active caption for 2 pairs',
      (tester) async {
    _ignoreAssetImageErrors();
    await tester.pumpWidget(_host(const [
      BeforeAfterPair(
          before: 'asset:a1.png', after: 'asset:a2.png', caption: 'Un'),
      BeforeAfterPair(
          before: 'asset:b1.png', after: 'asset:b2.png', caption: 'Deux'),
    ]));

    expect(find.text('Un'), findsOneWidget);
    expect(find.text('Deux'), findsNothing); // not selected yet
    expect(find.byType(BeforeAfterSlider), findsOneWidget);
  });

  testWidgets('the drag handle is present', (tester) async {
    _ignoreAssetImageErrors();
    await tester.pumpWidget(_host(const [
      BeforeAfterPair(before: 'asset:a.png', after: 'asset:b.png'),
    ]));
    expect(find.byIcon(Icons.compare_arrows), findsOneWidget);
  });
}
