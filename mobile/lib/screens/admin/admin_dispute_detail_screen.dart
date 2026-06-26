import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../providers/admin/admin_dispute_detail_provider.dart';
import '../../providers/admin/admin_disputes_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';
import 'widgets/admin_detail_widgets.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/reason_dialog.dart';

/// Dispute detail: the dispute + its booking + deposit-screenshot evidence, and
/// a resolve action. No money moves (no-custody) — resolution is advisory.
/// Design: docs/design/admin-console-ui.md §3.
class AdminDisputeDetailScreen extends StatefulWidget {
  const AdminDisputeDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<AdminDisputeDetailScreen> createState() =>
      _AdminDisputeDetailScreenState();
}

class _AdminDisputeDetailScreenState extends State<AdminDisputeDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminDisputeDetailProvider>().load(widget.id),
    );
  }

  Future<void> _resolve() async {
    final resolution = await showReasonDialog(
      context,
      title: 'Résoudre le litige',
      confirmLabel: 'Résoudre',
      hint: 'Décision (visible en interne)',
    );
    if (resolution == null || !mounted) return;
    final p = context.read<AdminDisputeDetailProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await p.resolve(widget.id, resolution);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
          content: Text(ok ? 'Litige résolu' : (p.actionError ?? 'Échec'))),
    );
    if (ok) unawaited(context.read<AdminDisputesProvider>().load());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminDisputeDetailProvider>();
    return AdminScaffold(title: 'Litige', showBack: true, child: _body(p));
  }

  Widget _body(AdminDisputeDetailProvider p) {
    if (p.isLoading && p.dispute == null) return const LoadingIndicator();
    if (p.dispute == null) {
      return AdminDetailError(
        message: p.error ?? 'Introuvable',
        onRetry: () =>
            context.read<AdminDisputeDetailProvider>().load(widget.id),
      );
    }
    final d = p.dispute!;
    final open = d['status'] == 'open';
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _left(d, p.appointment)),
                const SizedBox(width: AppTheme.spacingL),
                Expanded(flex: 3, child: _evidence(p.evidenceUrl)),
              ],
            ),
          ),
        ),
        if (open) _actionBar(p.acting),
      ],
    );
  }

  Widget _left(Map<String, dynamic> d, Map<String, dynamic>? appt) {
    final resolved = d['status'] == 'resolved';
    return Column(
      children: [
        AdminProfileCard(
          title: 'Litige',
          status: '${d['status'] ?? 'open'}',
          rows: [
            ('Motif', '${d['reason'] ?? '—'}'),
            ('Ouvert le', _date(d['createdAt'])),
            if (resolved) ('Résolution', '${d['resolution'] ?? '—'}'),
            if (resolved) ('Résolu le', _date(d['resolvedAt'])),
          ],
        ),
        const SizedBox(height: AppTheme.spacingM),
        if (appt != null)
          AdminProfileCard(
            title: 'Réservation',
            status: '${appt['status'] ?? 'pending'}',
            rows: [
              ('Date', _date(appt['appointmentDate'])),
              ('Montant', _fcfa(appt['totalPrice'])),
              ('Client', '${appt['clientName'] ?? '—'}'),
            ],
          ),
      ],
    );
  }

  Widget _evidence(String? url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminEvidenceImage(url: url, caption: "Preuve — capture de l'acompte"),
        const SizedBox(height: AppTheme.spacingS),
        SizedBox(
          width: 240,
          child: Text(
            "Aucun mouvement d'argent — Myweli ne détient pas les fonds. "
            'La résolution est consultative.',
            style:
                AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _actionBar(bool acting) {
    return AdminActionBar(
      children: [
        SizedBox(
          width: 180,
          child: AppButton(
            text: 'Résoudre',
            isLoading: acting,
            onPressed: acting ? null : _resolve,
          ),
        ),
      ],
    );
  }

  String _date(Object? raw) {
    final d = DateTime.tryParse('${raw ?? ''}');
    return d == null ? '—' : Formatters.formatDateShort(d);
  }

  String _fcfa(Object? raw) {
    final n = raw as num?;
    return n == null ? '—' : Formatters.formatCurrency(n.toDouble());
  }
}
