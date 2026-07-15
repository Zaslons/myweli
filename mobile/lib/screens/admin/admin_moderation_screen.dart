import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/admin/admin_moderation_provider.dart';
import '../../widgets/common/app_button.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/reason_dialog.dart';
import 'widgets/status_chip.dart';

/// Review moderation: **Signalés** (reported → Masquer / Ignorer) and **Masqués**
/// (hidden → Restaurer). Design: docs/design/admin-console-ui.md §3.
class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  int _segment = 0; // 0 = Signalés, 1 = Masqués

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminModerationProvider>().loadReported(),
    );
  }

  void _select(int s) {
    if (_segment == s) return;
    setState(() => _segment = s);
    final p = context.read<AdminModerationProvider>();
    if (s == 0 && p.reported.isEmpty) p.loadReported();
    if (s == 1 && p.hidden.isEmpty) p.loadHidden();
  }

  Future<void> _hide(String reviewId) async {
    final reason = await showReasonDialog(
      context,
      title: 'Masquer cet avis ?',
      confirmLabel: 'Masquer',
      hint: 'Motif interne (optionnel)',
      reasonRequired: false,
    );
    if (reason == null || !mounted) return;
    await _run(
        () => context.read<AdminModerationProvider>().hide(reviewId, reason),
        'Avis masqué');
  }

  Future<void> _dismiss(String reviewId) => _run(
      () => context.read<AdminModerationProvider>().dismiss(reviewId),
      'Signalements ignorés');

  Future<void> _restore(String reviewId) => _run(
      () => context.read<AdminModerationProvider>().restore(reviewId),
      'Avis restauré');

  Future<void> _run(Future<bool> Function() action, String okMsg) async {
    final p = context.read<AdminModerationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await action();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? okMsg : (p.actionError ?? 'Échec'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminModerationProvider>();
    return AdminScaffold(
      title: 'Avis',
      actions: [
        IconButton(
          tooltip: 'Rafraîchir',
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: () => _segment == 0 ? p.loadReported() : p.loadHidden(),
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Segments(
              selected: _segment,
              onSelect: _select,
              reportedCount: p.reported.length,
              hiddenCount: p.hidden.length,
            ),
            const SizedBox(height: AppTheme.spacingM),
            if (_segment == 0) _reportedTable(p) else _hiddenTable(p),
          ],
        ),
      ),
    );
  }

  Widget _reportedTable(AdminModerationProvider p) {
    return AdminDataTable(
      isLoading: p.reportedLoading,
      error: p.reportedError,
      onRetry: () => context.read<AdminModerationProvider>().loadReported(),
      emptyIcon: Icons.flag_outlined,
      emptyTitle: 'Aucun avis signalé',
      emptyDescription: 'Les avis signalés par les clients apparaîtront ici.',
      columns: const [
        AdminColumn('Avis', flex: 4),
        AdminColumn('Signalements', flex: 2),
        AdminColumn('Action', flex: 3),
      ],
      rows: [
        for (final r in p.reported)
          AdminRow(
            cells: [
              _reviewCell(
                rating: (r['rating'] as num?)?.toInt() ?? 0,
                text: '${r['text'] ?? ''}',
                sub: 'par ${r['userName'] ?? 'Client'} · motif : '
                    '${r['lastReason'] ?? '—'}',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(
                  label: '${r['reportCount'] ?? 1} signalement(s)',
                  kind: ((r['reportCount'] as num?) ?? 1) >= 2
                      ? AdminChipKind.danger
                      : AdminChipKind.pending,
                ),
              ),
              _actions([
                _btn('Masquer', () => _hide('${r['reviewId']}'), p.acting),
                _btn('Ignorer', () => _dismiss('${r['reviewId']}'), p.acting,
                    secondary: true),
              ]),
            ],
          ),
      ],
    );
  }

  Widget _hiddenTable(AdminModerationProvider p) {
    return AdminDataTable(
      isLoading: p.hiddenLoading,
      error: p.hiddenError,
      onRetry: () => context.read<AdminModerationProvider>().loadHidden(),
      emptyIcon: Icons.visibility_off_outlined,
      emptyTitle: 'Aucun avis masqué',
      emptyDescription: 'Les avis masqués apparaîtront ici.',
      columns: const [
        AdminColumn('Avis', flex: 4),
        AdminColumn('Statut', flex: 2),
        AdminColumn('Action', flex: 3),
      ],
      rows: [
        for (final r in p.hidden)
          AdminRow(
            cells: [
              _reviewCell(
                rating: (r['rating'] as num?)?.toInt() ?? 0,
                text: '${r['text'] ?? ''}',
                sub: 'par ${r['userName'] ?? 'Client'}',
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(label: 'masqué', kind: AdminChipKind.danger),
              ),
              _actions([
                _btn('Restaurer', () => _restore('${r['id']}'), p.acting,
                    secondary: true),
              ]),
            ],
          ),
      ],
    );
  }

  Widget _reviewCell({
    required int rating,
    required String text,
    required String sub,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.star, size: 13, color: AppColors.starRating),
            const SizedBox(width: AppTheme.spacingXS),
            Text('$rating/5',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: AppTheme.spacingXS),
        Text(text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium),
        const SizedBox(height: AppTheme.spacingXS),
        Text(sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textTertiary)),
      ],
    );
  }

  Widget _actions(List<Widget> buttons) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: buttons,
      );

  Widget _btn(String label, VoidCallback onTap, bool acting,
          {bool secondary = false}) =>
      SizedBox(
        width: 104,
        child: AppButton(
          text: label,
          type: secondary ? AppButtonType.secondary : AppButtonType.primary,
          onPressed: acting ? null : onTap,
        ),
      );
}

class _Segments extends StatelessWidget {
  const _Segments({
    required this.selected,
    required this.onSelect,
    required this.reportedCount,
    required this.hiddenCount,
  });
  final int selected;
  final ValueChanged<int> onSelect;
  final int reportedCount;
  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      padding: const EdgeInsets.all(AppTheme.spacingXS),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg('Signalés', 0),
          _seg('Masqués', 1),
        ],
      ),
    );
  }

  Widget _seg(String label, int index) {
    final active = selected == index;
    return Builder(
      builder: (context) => InkWell(
        onTap: () => onSelect(index),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingM, vertical: AppTheme.spacingS),
          decoration: BoxDecoration(
            color: active ? AppColors.secondary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: active ? Border.all(color: AppColors.borderStrong) : null,
          ),
          child: Text(
            label,
            style:
                (active ? AppTextStyles.titleSmall : AppTextStyles.bodyMedium)
                    .copyWith(
              color: active ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
