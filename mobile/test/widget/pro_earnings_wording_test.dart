import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_earnings_provider.dart';
import 'package:myweli/screens/provider/earnings/earnings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';
import '../support/pump_app.dart';
import '../support/secure_storage.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/tab_flows.dart';

/// The « Revenus » screen says what its total counts
/// (docs/design/provider-earnings.md §12).
///
/// The total is completed bookings only, while the Accueil cards beside the
/// same word counted confirmed + completed — on the demo salon 15 000 here
/// against 62 000 there, for one day. Both definitions are deliberate; the
/// words were the defect. So the total is « Total réalisé », with what it
/// counts under the figure, and nothing on the screen says the salon
/// « encaissé » anything: MyWeli never sees a payment.
///
/// These read the RENDERED text, in the order a reader meets it.
void main() {
  setUpAll(() async {
    AppClock.freeze(kFixedNow);
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    stubSecureStorage();
    setupDependencyInjection();
  });
  tearDownAll(AppClock.restore);
  setUp(() => freezeClock(kFixedNow));

  Future<void> pumpEarnings(WidgetTester tester) async {
    final auth = await signInPro(tester);
    await pumpApp(
      tester,
      providers: [
        ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => ProEarningsProvider()),
      ],
      home: const EarningsScreen(),
    );
    await settleMocks(tester, rounds: 3);
  }

  /// The summary card's texts, top to bottom: the card is the `Column` that
  /// holds the label.
  List<(String, Rect)> summaryCard(WidgetTester tester) {
    final label = find.text('Total réalisé');
    expect(
      label,
      findsOneWidget,
      reason: 'the total is labelled « Total réalisé » — not « Total »',
    );
    final card = find.ancestor(of: label, matching: find.byType(Column)).first;
    return [
      for (final e
          in find.descendant(of: card, matching: find.byType(Text)).evaluate())
        (
          (e.widget as Text).data ?? '',
          tester.getRect(find.byElementPredicate((x) => identical(x, e))),
        ),
    ];
  }

  testWidgets('with takings: « Total réalisé », the figure, then « Rendez-vous '
      'terminés »', (tester) async {
    await pumpEarnings(tester);
    await openEarningsAll(tester);

    final texts = summaryCard(tester);
    expect(
      texts.map((t) => t.$1).toList(),
      [
        'Total réalisé',
        matches(RegExp(r'\d')), // the amount, whatever the mock sums to
        'Rendez-vous terminés',
      ],
      reason: 'label, figure, what the figure counts — in that order',
    );
    // Under the figure, not beside it.
    expect(texts[1].$2.top, greaterThanOrEqualTo(texts[0].$2.bottom));
    expect(texts[2].$2.top, greaterThanOrEqualTo(texts[1].$2.bottom));

    expect(find.text('Total'), findsNothing);
    expect(find.textContaining('encaiss'), findsNothing);
  });

  testWidgets('empty period: the same card, and the empty state promises '
      'completed bookings, not payments', (tester) async {
    await pumpEarnings(tester);

    // « Aujourd'hui » is the default tab, and MockData seeds no booking today.
    expect(find.text('Aucune transaction'), findsOneWidget);
    expect(summaryCard(tester).map((t) => t.$1).toList(), [
      'Total réalisé',
      matches(RegExp(r'\d')),
      'Rendez-vous terminés',
    ]);
    // Before the exact string, so the old « Les paiements encaissés … »
    // fails on the word that is wrong rather than on a near-miss.
    expect(find.textContaining('encaiss'), findsNothing);
    expect(
      find.text('Les rendez-vous terminés sur cette période apparaîtront ici.'),
      findsOneWidget,
    );
  });
}
