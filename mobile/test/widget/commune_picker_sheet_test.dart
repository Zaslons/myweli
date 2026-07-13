import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/locality_provider.dart';
import 'package:myweli/widgets/common/commune_picker_sheet.dart';
import 'package:provider/provider.dart';

/// The commune picker renders the LOCALITY TREE (multi-pays MP2) and returns
/// both the display name (the consumer filter contract) and the areaId (the
/// pro write paths).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupDependencyInjection);

  Widget host(
    void Function(CommuneChoice?) onResult, {
    bool allowAll = true,
  }) =>
      ChangeNotifierProvider(
        create: (_) => LocalityProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  onResult(await showCommunePicker(
                    context,
                    selected: null,
                    allowAll: allowAll,
                  ));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('returns the tapped commune with its areaId', (tester) async {
    CommuneChoice? result;
    await tester.pumpWidget(host((r) => result = r));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir une commune'), findsOneWidget);

    await tester.tap(find.text('Cocody'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.commune, 'Cocody');
    expect(result!.areaId, 'cocody'); // the pro write-path id
  });

  testWidgets('search filters the commune list', (tester) async {
    await tester.pumpWidget(host((_) {}));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'marc');
    await tester.pumpAndSettle();

    expect(find.text('Marcory'), findsOneWidget);
    expect(find.text('Cocody'), findsNothing);
  });

  testWidgets('allowAll: false hides « Toutes les communes » (pro editors)',
      (tester) async {
    await tester.pumpWidget(host((_) {}, allowAll: false));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Toutes les communes'), findsNothing);
    expect(find.text('Cocody'), findsOneWidget);
  });
}
