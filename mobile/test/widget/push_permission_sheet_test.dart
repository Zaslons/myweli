import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/widgets/push/push_permission_sheet.dart';

void main() {
  Widget host(void Function(bool) onResult) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async =>
                  onResult(await showPushPermissionSheet(context)),
              child: const Text('open'),
            ),
          ),
        ),
      );

  testWidgets('renders the rationale and « Activer » returns true',
      (tester) async {
    bool? result;
    await tester.pumpWidget(host((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Activer les notifications'), findsOneWidget);
    expect(find.text('Activer'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);

    await tester.tap(find.text('Activer'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('« Plus tard » returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(host((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
