import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/unnamed_salon.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/salon_time.dart';
import '../../core/utils/text_fit.dart';
import '../../models/admin_salon_validation.dart';
import '../../models/salon_validation.dart';
import '../../providers/admin/admin_salon_validation_count_provider.dart';
import '../../providers/admin/admin_salon_validations_provider.dart';
import '../../widgets/common/label_value_row.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/admin_segmented_control.dart';
import 'widgets/status_chip.dart';
import 'widgets/validation_unavailable.dart';

/// « Salons à valider » — the queue of salons asking to go public (B0.18 —
/// docs/design/salon-go-live-approval.md §4.2).
///
/// - **Three tabs**: « En attente » (the oldest request first — suspended
///   salons are not in it, §3.5), « Refusés », « Validés » (the latest
///   decision first). 50 per page, previous / next.
/// - **A row**: the salon, its commune and city, its country (decision 123's
///   first evidence), the date that tab is about — asked, refused or
///   validated — the owner's e-mail or phone, and the KYC documents sent.
///   A row opens the request (`/admin/salon-validations/:id`).
/// - **The four states** are [AdminDataTable]'s; after a decision the row
///   has already left its tab, and the sidebar's count re-reads
///   ([AdminSalonValidationDetailProvider] does both).
/// - **Before the backend deploy** (§9.2 — the console goes live first) the
///   server has no such route: a calm sentence that says so, never an error,
///   and no tabs to choose between.
class AdminSalonValidationsScreen extends StatefulWidget {
  const AdminSalonValidationsScreen({super.key});

  /// The page's title — the sidebar's and the dashboard's words.
  static const title = 'Salons à valider';

  @override
  State<AdminSalonValidationsScreen> createState() =>
      _AdminSalonValidationsScreenState();
}

class _AdminSalonValidationsScreenState
    extends State<AdminSalonValidationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  /// The tab, and the sidebar's count with it: arriving here, or asking for
  /// a refresh, is when the admin wants both current.
  void _reload() {
    context.read<AdminSalonValidationsProvider>().load();
    context.read<AdminSalonValidationCountProvider?>()?.load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminSalonValidationsProvider>();
    return AdminScaffold(
      title: AdminSalonValidationsScreen.title,
      actions: [
        IconButton(
          tooltip: 'Rafraîchir',
          icon: const Icon(Icons.refresh, size: AppTheme.iconS),
          onPressed: _reload,
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: p.unavailable
            ? const AdminValidationUnavailable()
            : _queue(context, p),
      ),
    );
  }

  Widget _queue(BuildContext context, AdminSalonValidationsProvider p) {
    final tab = p.tab;
    final empty = _Empty.of(tab);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scrolls sideways rather than overflowing when the three labels at
        // 200 % text are wider than a narrow window.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: AdminSegmentedControl(
            labels: const ['En attente', 'Refusés', 'Validés'],
            selected: AdminSalonValidationsProvider.tabs.indexOf(tab),
            onSelect: (i) => context
                .read<AdminSalonValidationsProvider>()
                .setTab(AdminSalonValidationsProvider.tabs[i]),
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        // Six columns while each column holds its words whole; one stacked
        // column when it cannot — a narrow window at 200 % text broke
        // « Pays », « Documents » and « aucun » inside the word (§13.3).
        // Measured with [TextFit], never a constant.
        LayoutBuilder(
          builder: (context, box) {
            final stacked = !_columnsFit(context, box.maxWidth, tab, p.items);
            return AdminDataTable(
              isLoading: p.isLoading,
              error: p.error,
              onRetry: () =>
                  context.read<AdminSalonValidationsProvider>().load(),
              emptyIcon: empty.icon,
              emptyTitle: empty.title,
              emptyDescription: empty.description,
              columns: stacked
                  ? const [AdminColumn('Salon')]
                  : [
                      for (final (label, flex) in _columns(tab))
                        AdminColumn(label, flex: flex),
                    ],
              rows: [
                for (final item in p.items)
                  stacked
                      ? _stackedRow(context, item, tab)
                      : _row(context, item, tab),
              ],
            );
          },
        ),
        if (!p.isLoading && p.error == null && p.items.isNotEmpty)
          _Pager(provider: p),
      ],
    );
  }

  /// §4.2's columns, and their shares of the row.
  static List<(String, int)> _columns(SalonValidationState tab) => [
    ('Salon', 3),
    ('Commune, ville', 3),
    ('Pays', 1),
    (_dateColumn(tab), 2),
    ('Propriétaire (e-mail ou téléphone)', 4),
    ('Documents KYC', 2),
  ];

  /// Whether every column's header, and every cell that wraps, keeps its
  /// longest word whole at [width] — the table's own padding taken off. The
  /// owner's contact is one ellipsised line, and is not asked.
  static bool _columnsFit(
    BuildContext context,
    double width,
    SalonValidationState tab,
    List<SalonValidationQueueItem> items,
  ) {
    final columns = _columns(tab);
    final share =
        (width - 2 * AppTheme.spacingM) /
        columns.fold<int>(0, (n, c) => n + c.$2);
    final fit = TextFit.of(context);
    final header = AppTextStyles.bodySmall;
    const cell = AppTextStyles.bodyMedium;
    for (final (i, (label, flex)) in columns.indexed) {
      final values = [
        for (final item in items)
          switch (i) {
            0 => salonNameOr(item.name, kUnnamedSalon),
            1 => _place(item),
            2 => item.countryCode ?? '—',
            3 => _date(item.dateFor(tab)),
            5 => _kyc(item),
            _ => '',
          },
      ];
      if (!fit.holds(share * flex, [
        (text: label, style: header),
        for (final v in values) (text: v, style: cell),
      ])) {
        return false;
      }
    }
    return true;
  }

  void _open(BuildContext context, SalonValidationQueueItem item) => context
      .push('/admin/salon-validations/${Uri.encodeComponent(item.providerId)}');

  static String _kyc(SalonValidationQueueItem item) =>
      item.kycDocCount == 0 ? 'aucun' : '${item.kycDocCount}';

  /// One request as a block: its name, then each column's label and value —
  /// the table's facts, when its columns are too narrow to hold them.
  AdminRow _stackedRow(
    BuildContext context,
    SalonValidationQueueItem item,
    SalonValidationState tab,
  ) {
    final label = AppTextStyles.bodySmall.copyWith(
      color: AppColors.textTertiary,
    );
    final value = AppTextStyles.bodyMedium.copyWith(
      color: AppColors.textSecondary,
    );
    Widget fact(String l, String v) => Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingXS),
      child: LabelValueRow(
        label: l,
        value: v,
        labelStyle: label,
        valueStyle: value,
      ),
    );
    return AdminRow(
      onTap: () => _open(context, item),
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _salonCell(item),
            fact('Commune, ville', _place(item)),
            fact('Pays', item.countryCode ?? '—'),
            fact(_dateColumn(tab), _date(item.dateFor(tab))),
            // One line, as in the table: an e-mail is one long word, and
            // a declared ellipsis beats a break inside it (§13.3).
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.spacingXS),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Propriétaire', style: label),
                  Text(
                    item.ownerContact ?? 'sans propriétaire',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: value,
                  ),
                ],
              ),
            ),
            fact('Documents KYC', _kyc(item)),
          ],
        ),
      ],
    );
  }

  /// The salon's name, and what in the row asks for attention.
  static Widget _salonCell(SalonValidationQueueItem item) {
    final chips = [
      // « Validés » holds the validations still to finish — the one row
      // there that asks for something.
      if (item.validation.isFinishing)
        StatusChip.forValidation(item.validation),
      // A suspended salon is in « Refusés » or « Validés », never waiting.
      if (item.salonStatus == 'suspended') StatusChip.forStatus('suspended'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          salonNameOr(item.name, kUnnamedSalon),
          style: AppTextStyles.bodyMedium,
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingXS),
          Wrap(
            spacing: AppTheme.spacingXS,
            runSpacing: AppTheme.spacingXS,
            children: chips,
          ),
        ],
      ],
    );
  }

  AdminRow _row(
    BuildContext context,
    SalonValidationQueueItem item,
    SalonValidationState tab,
  ) {
    final muted = AppTextStyles.bodyMedium.copyWith(
      color: AppColors.textSecondary,
    );
    return AdminRow(
      onTap: () => _open(context, item),
      cells: [
        _salonCell(item),
        Text(_place(item), style: muted),
        Text(item.countryCode ?? '—', style: muted),
        Text(_date(item.dateFor(tab)), style: muted),
        Text(
          // The server's « no active owner » — the restore's own word for it.
          item.ownerContact ?? 'sans propriétaire',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: muted,
        ),
        Text(_kyc(item), style: muted),
      ],
    );
  }

  /// « Demandé le » on « En attente »; the decision's date elsewhere — the
  /// date each tab is sorted by.
  static String _dateColumn(SalonValidationState tab) => switch (tab) {
    SalonValidationState.refused => 'Refusé le',
    SalonValidationState.approved => 'Validé le',
    _ => 'Demandé le',
  };

  static String _place(SalonValidationQueueItem item) {
    final parts = [
      for (final p in [item.commune, item.city])
        if (p != null && p.trim().isNotEmpty) p.trim(),
    ];
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  /// « 12 nov. 2026 » in the salon's time — breaks only between words, so a
  /// narrow column wraps it whole (`formatDateCompact`). A row carries no
  /// timezone: the market's default.
  static String _date(DateTime? d) =>
      d == null ? '—' : Formatters.formatDateCompact(toSalonTime(d));
}

/// Each tab's empty state.
class _Empty {
  const _Empty(this.icon, this.title, this.description);

  final IconData icon;
  final String title;
  final String description;

  static _Empty of(SalonValidationState tab) => switch (tab) {
    SalonValidationState.refused => const _Empty(
      Icons.block,
      'Aucun salon refusé.',
      'Les demandes que vous refusez apparaîtront ici.',
    ),
    SalonValidationState.approved => const _Empty(
      Icons.check_circle_outline,
      'Aucun salon validé.',
      'Les salons que vous validez apparaîtront ici.',
    ),
    _ => const _Empty(
      Icons.add_business_outlined,
      'Aucun salon en attente.',
      'Les nouvelles demandes de mise en ligne arriveront ici.',
    ),
  };
}

/// Previous / next, 50 per page — the audit log's pattern.
class _Pager extends StatelessWidget {
  const _Pager({required this.provider});

  final AdminSalonValidationsProvider provider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingM),
      child: Row(
        children: [
          Expanded(
            child: Text(
              Formatters.count(provider.total, 'demande', 'demandes'),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Précédent',
            icon: const Icon(Icons.chevron_left, size: AppTheme.iconS),
            onPressed: provider.hasPrev
                ? () => context.read<AdminSalonValidationsProvider>().prevPage()
                : null,
          ),
          Text('Page ${provider.page}', style: AppTextStyles.bodyMedium),
          IconButton(
            tooltip: 'Suivant',
            icon: const Icon(Icons.chevron_right, size: AppTheme.iconS),
            onPressed: provider.hasNext
                ? () => context.read<AdminSalonValidationsProvider>().nextPage()
                : null,
          ),
        ],
      ),
    );
  }
}
