import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/commune_pill.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows "Toutes les communes" when none is selected',
      (tester) async {
    await tester.pumpWidget(wrap(CommunePill(commune: null, onTap: () {})));
    expect(find.text('Toutes les communes'), findsOneWidget);
  });

  testWidgets('shows the commune name when one is selected', (tester) async {
    await tester.pumpWidget(wrap(CommunePill(commune: 'Cocody', onTap: () {})));
    expect(find.text('Cocody'), findsOneWidget);
  });

  testWidgets('fires onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(CommunePill(commune: 'Cocody', onTap: () => tapped = true)),
    );
    await tester.tap(find.byType(CommunePill));
    expect(tapped, isTrue);
  });
}
