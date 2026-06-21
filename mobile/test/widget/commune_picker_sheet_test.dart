import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/common/commune_picker_sheet.dart';

void main() {
  testWidgets('returns the tapped commune as a CommuneChoice', (tester) async {
    CommuneChoice? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showCommunePicker(context, selected: null);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir une commune'), findsOneWidget);

    await tester.tap(find.text('Cocody'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.commune, 'Cocody');
  });

  testWidgets('search filters the commune list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCommunePicker(context, selected: null),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'marc');
    await tester.pumpAndSettle();

    expect(find.text('Marcory'), findsOneWidget);
    expect(find.text('Cocody'), findsNothing);
  });
}
