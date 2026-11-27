import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/revenue_periods.dart';
import '../../../models/revenue_analytics.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_card.dart';
import '../../../widgets/common/myweli_date_picker.dart';

/// The bottom sheets of « Revenus » (docs/design/pro-revenue-analytics.md
/// §4.3, §4.7): the comparison, the custom range, the sort.

Future<T?> _sheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLarge),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingL),
          child: builder(ctx),
        ),
      ),
    );

Widget _sheetTitle(String text) => Semantics(
  header: true,
  child: Text(
    text,
    style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
  ),
);

/// The names of the comparison modes (§4.13).
String revenueCompareName(RevenueCompare c) => switch (c) {
  RevenueCompare.previous => 'Période précédente',
  RevenueCompare.year => 'Même période l’an dernier',
  RevenueCompare.none => 'Aucune comparaison',
};

/// « Comparer à » — three option cards, the chosen one marked (§4.3).
Future<RevenueCompare?> showRevenueCompareSheet(
  BuildContext context,
  RevenueCompare current,
) => _sheet<RevenueCompare>(
  context,
  (ctx) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sheetTitle('Comparer à'),
      const SizedBox(height: AppTheme.spacingM),
      for (final mode in RevenueCompare.values) ...[
        AppCard(
          outlined: true,
          selected: mode == current,
          onTap: () => Navigator.pop(ctx, mode),
          child: Text(
            revenueCompareName(mode),
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacingS),
      ],
    ],
  ),
);

/// « Dates… » — « Du » and « Au », each MyWeli's own picker (there is no
/// Material picker in the app, SYSTEM §21 row 73), the field's error under
/// « Au », never a toast. Returns the range to ask, or null.
Future<({DateTime from, DateTime to})?> showRevenueRangeSheet(
  BuildContext context, {
  required DateTime latest,
  DateTime? from,
  DateTime? to,
}) => _sheet<({DateTime from, DateTime to})>(
  context,
  (ctx) => _RangeSheet(latest: latest, from: from, to: to),
);

class _RangeSheet extends StatefulWidget {
  const _RangeSheet({required this.latest, this.from, this.to});

  final DateTime latest;
  final DateTime? from;
  final DateTime? to;

  @override
  State<_RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends State<_RangeSheet> {
  late DateTime? _from = widget.from;
  late DateTime? _to = widget.to;

  Future<void> _pick({required bool start}) async {
    final current = start ? _from : _to;
    final picked = await showMyweliDatePicker(
      context: context,
      initialDate: current ?? (start ? _to : _from) ?? widget.latest,
      firstDate: kRevenueEarliestDay,
      lastDate: widget.latest,
      helpText: start ? 'Du' : 'Au',
    );
    if (picked == null || !mounted) return;
    final day = revenueDay(picked.year, picked.month, picked.day);
    setState(() => start ? _from = day : _to = day);
  }

  @override
  Widget build(BuildContext context) {
    final from = _from;
    final to = _to;
    final error = (from == null || to == null)
        ? null
        : customRangeError(from, to);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetTitle('Choisir les dates'),
        const SizedBox(height: AppTheme.spacingM),
        _DateField(label: 'Du', value: from, onTap: () => _pick(start: true)),
        const SizedBox(height: AppTheme.spacingSM),
        _DateField(
          label: 'Au',
          value: to,
          error: error,
          onTap: () => _pick(start: false),
        ),
        const SizedBox(height: AppTheme.spacingL),
        AppButton(
          text: 'Afficher',
          onPressed: from == null || to == null || error != null
              ? null
              : () => Navigator.pop(context, (from: from, to: to)),
        ),
      ],
    );
  }
}

/// A field that opens a picker: its label, the chosen date (or « Choisir »),
/// and its own error under it (§14 — an error belongs to its field).
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.error,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final shown = value == null
        ? 'Choisir une date'
        : Formatters.formatDayMonthYear(value!);
    final invalid = error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingXS),
        Semantics(
          button: true,
          label: '$label : $shown',
          hint: error,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            child: Container(
              // §13.2 touch target.
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingSM,
                vertical: AppTheme.spacingSM,
              ),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(
                  color: invalid ? AppColors.error : AppColors.borderStrong,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: AppTheme.iconS,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppTheme.spacingS),
                  Expanded(
                    child: Text(
                      shown,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: value == null
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (error case final e?) ...[
          const SizedBox(height: AppTheme.spacingXS),
          Semantics(
            liveRegion: true,
            child: Text(
              e,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ],
    );
  }
}

/// How « Répartition » is sorted (§4.7).
enum RevenueSort { amount, count, name }

String revenueSortName(RevenueSort s) => switch (s) {
  RevenueSort.amount => 'Montant',
  RevenueSort.count => 'Rendez-vous',
  RevenueSort.name => 'Nom',
};

/// « Trier par » — the three choices, the current one ticked.
Future<RevenueSort?> showRevenueSortSheet(
  BuildContext context,
  RevenueSort current,
) => _sheet<RevenueSort>(
  context,
  (ctx) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sheetTitle('Trier par'),
      const SizedBox(height: AppTheme.spacingS),
      for (final s in RevenueSort.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(revenueSortName(s)),
          selected: s == current,
          trailing: s == current
              ? const Icon(Icons.check, color: AppColors.primary)
              : null,
          onTap: () => Navigator.pop(ctx, s),
        ),
    ],
  ),
);
