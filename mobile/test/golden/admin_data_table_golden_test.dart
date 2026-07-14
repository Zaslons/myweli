import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/text_styles.dart';
import 'package:myweli/screens/admin/widgets/admin_data_table.dart';
import 'package:myweli/screens/admin/widgets/status_chip.dart';

import '../support/golden.dart';

/// `AdminDataTable` in all four states (docs/design/SYSTEM.md §12).
///
/// This is the ONE component in the repo that implements the four-state contract
/// completely — loading (skeleton) · empty · error (+ retry) · success — which is
/// why §12 promotes its shape as the reference every new async component copies.
///
/// The loading state is also the reason this component, and not a screen, carries
/// the "loading" golden: its skeleton is STATIC. The app's other loading state is
/// `BrandLoader`, an infinitely-repeating Lottie that no golden can pin.
///
/// Watch the skeleton row in A5: its `height: 52` is a hard height around content
/// (register row 15) and it is one of the sites that breaks at 200% text scale.
void main() {
  group('goldens', () {
    setUpAll(loadGoldenFonts);

    testWidgets('four states: loading', (tester) async {
      await pumpGolden(tester, _table(isLoading: true), size: _size);
      await expectGolden(tester, 'admin_table_loading');
    });

    testWidgets('four states: empty', (tester) async {
      await pumpGolden(tester, _table(), size: _size);
      await expectGolden(tester, 'admin_table_empty');
    });

    testWidgets('four states: error (+ retry)', (tester) async {
      await pumpGolden(
        tester,
        _table(error: 'Chargement impossible. Vérifiez votre connexion.'),
        size: _size,
      );
      await expectGolden(tester, 'admin_table_error');
    });

    testWidgets('four states: success', (tester) async {
      await pumpGolden(tester, _table(rows: _rows), size: _size);
      await expectGolden(tester, 'admin_table_success');
    });
  }, skip: kGoldensSkip);
}

const _size = Size(720, 420);

Widget _table({
  bool isLoading = false,
  String? error,
  List<AdminRow> rows = const [],
}) =>
    Padding(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: AdminDataTable(
        columns: const [
          AdminColumn('Salon', flex: 2),
          AdminColumn('Commune'),
          AdminColumn('Statut'),
        ],
        rows: rows,
        isLoading: isLoading,
        error: error,
        onRetry: _noop,
        emptyTitle: 'Aucune demande en attente',
        emptyIcon: Icons.inbox_outlined,
        emptyDescription: 'Les nouvelles demandes de vérification arriveront ici.',
      ),
    );

final _rows = [
  _row('Beauté Divine', 'Cocody', 'verified'),
  _row('Salon Excellence', 'Plateau', 'pending'),
  _row('Institut Belle Vue', 'Yopougon', 'rejected'),
  _row('Barber Kings', 'Marcory', 'active'),
];

AdminRow _row(String name, String commune, String status) => AdminRow(
      cells: [
        Text(name, style: AppTextStyles.bodyMedium),
        Text(commune, style: AppTextStyles.bodyMedium),
        Align(
          alignment: Alignment.centerLeft,
          child: StatusChip.forStatus(status),
        ),
      ],
    );

void _noop() {}
