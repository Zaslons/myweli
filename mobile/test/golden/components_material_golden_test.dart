import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/theme/colors.dart';

import '../support/golden.dart';

/// The Material components A3 themed (docs/design/SYSTEM.md §21 row 9).
///
/// Before A3 these rendered off Material 3's PURPLE defaults — bare chips filled
/// `secondaryContainer` #E8DEF8, switch tracks and slider inactive tracks a
/// purple-tinted grey, tab/icon defaults `onSurfaceVariant`. This sheet is the
/// proof the purple is gone: everything here is monochrome, on-token, and legible
/// in both states.
void main() {
  group('goldens', () {
    setUpAll(loadGoldenFonts);

    testWidgets('the themed Material components', (tester) async {
      await pumpGolden(
        tester,
        const _MaterialSheet(),
        size: const Size(390, 900),
      );
      await expectGolden(tester, 'components_material');
    });

    testWidgets('a dialog', (tester) async {
      goldenSurface(tester, size: const Size(390, 360));
      await tester.pumpWidget(
        goldenApp(
          home: const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: AlertDialog(
                title: Text('Annuler le rendez-vous ?'),
                content: Text(
                  'Cette action est définitive. Le client sera prévenu.',
                ),
                actions: [
                  TextButton(onPressed: _noop, child: Text('Retour')),
                  ElevatedButton(
                    onPressed: _noop,
                    child: Text('Annuler le RDV'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectGolden(tester, 'components_dialog');
    });
  }, skip: kGoldensSkip);
}

class _MaterialSheet extends StatefulWidget {
  const _MaterialSheet();
  @override
  State<_MaterialSheet> createState() => _MaterialSheetState();
}

class _MaterialSheetState extends State<_MaterialSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          GoldenSection(
            title: 'Chips — selected inverts legibly',
            child: Wrap(
              spacing: AppTheme.spacingS,
              runSpacing: AppTheme.spacingS,
              children: [
                const Chip(label: Text('Coiffure')),
                ChoiceChip(
                  label: const Text('Sélectionné'),
                  selected: true,
                  onSelected: _noopBool,
                ),
                ChoiceChip(
                  label: const Text('Non sélectionné'),
                  selected: false,
                  onSelected: _noopBool,
                ),
                FilterChip(
                  label: const Text('À domicile'),
                  selected: true,
                  onSelected: _noopBool,
                ),
              ],
            ),
          ),
          const GoldenSection(
            title: 'Switch · Checkbox',
            child: Row(
              children: [
                Switch(value: true, onChanged: _noopBool),
                Switch(value: false, onChanged: _noopBool),
                SizedBox(width: AppTheme.spacingM),
                Checkbox(value: true, onChanged: _noopBoolN),
                Checkbox(value: false, onChanged: _noopBoolN),
              ],
            ),
          ),
          GoldenSection(
            title: 'Slider — inactive track was purple-tinted',
            child: Slider(value: 0.4, onChanged: _noopDouble),
          ),
          GoldenSection(
            title: 'TabBar — unselected label was onSurfaceVariant',
            child: SizedBox(
              height: 48,
              child: TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Journée'),
                  Tab(text: 'Calendrier'),
                  Tab(text: 'Liste'),
                ],
              ),
            ),
          ),
          GoldenSection(
            title: 'IconButtons — uncolored defaulted to onSurfaceVariant',
            child: Row(
              children: [
                IconButton(
                  onPressed: _noop,
                  icon: const Icon(Icons.calendar_today_outlined),
                ),
                IconButton(
                  onPressed: _noop,
                  icon: const Icon(Icons.notifications_outlined),
                ),
                IconButton(
                  onPressed: _noop,
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
          ),
          const GoldenSection(
            title: 'ListTile — leading/trailing icons',
            child: Card(
              child: ListTile(
                leading: Icon(Icons.storefront_outlined),
                title: Text('Profil du salon'),
                subtitle: Text('Infos publiques, catégorie, carte'),
                trailing: Icon(Icons.chevron_right),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _noop() {}
void _noopBool(bool _) {}
void _noopBoolN(bool? _) {}
void _noopDouble(double _) {}
