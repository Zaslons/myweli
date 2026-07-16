import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/screens/admin/widgets/admin_segmented_control.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/common/commune_pill.dart';
import 'package:myweli/widgets/provider/provider_card.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '_a11y.dart';

/// A4b — every tap target carries a screen-reader label (SYSTEM.md §13.4, register
/// row 13). `labeledTapTargetGuideline` is Flutter's own check; before A4b it went
/// red on the icon-only controls (the bare-gesture favourite heart, the tooltip-less
/// IconButtons) — announced to TalkBack/VoiceOver as nothing.
void main() {
  setUpAll(() {
    initializeDateFormatting('fr_FR', null);
    setupDependencyInjection();
  });

  Widget card({bool isGrid = false}) => ProviderCard(
        provider: MockData.providers.first,
        isGrid: isGrid,
        onTap: () {},
      );

  List<SingleChildWidget> favProviders() => [
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ];

  testWidgets('ProviderCard (list) — the favourite heart is labelled',
      (tester) async {
    final handle = await pumpForA11y(tester, card(), providers: favProviders());
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('ProviderCard (grid) — the favourite heart is labelled',
      (tester) async {
    final handle = await pumpForA11y(
      tester,
      card(isGrid: true),
      providers: favProviders(),
    );
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('CommunePill — the location pill is labelled', (tester) async {
    final handle = await pumpForA11y(
      tester,
      CommunePill(commune: 'Cocody', onTap: () {}),
    );
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('AdminSegmentedControl — the segments are labelled',
      (tester) async {
    final handle = await pumpForA11y(
      tester,
      AdminSegmentedControl(
        labels: const ['En attente', 'Vérifiés'],
        selected: 0,
        onSelect: (_) {},
      ),
    );
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
