import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/admin/admin_disputes_provider.dart';
import '../../providers/admin/admin_provider_detail_provider.dart';
import '../../providers/admin/admin_providers_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';
import 'widgets/admin_detail_widgets.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/reason_dialog.dart';

/// Salon support view: profile + recent bookings + suspend/restore/feature.
/// Design: docs/design/admin-console-ui.md §3.
class AdminProviderDetailScreen extends StatefulWidget {
  const AdminProviderDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<AdminProviderDetailScreen> createState() =>
      _AdminProviderDetailScreenState();
}

class _AdminProviderDetailScreenState extends State<AdminProviderDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminProviderDetailProvider>().load(widget.id),
    );
  }

  Future<void> _suspend() async {
    final reason = await showReasonDialog(
      context,
      title: 'Suspendre ce salon ?',
      confirmLabel: 'Suspendre',
      hint: 'Motif (interne)',
      reasonRequired: false,
    );
    if (reason == null || !mounted) return;
    await _run(
        () => context
            .read<AdminProviderDetailProvider>()
            .suspend(widget.id, reason),
        'Salon suspendu');
  }

  Future<void> _restore() => _run(
      () => context.read<AdminProviderDetailProvider>().restore(widget.id),
      'Salon réactivé');

  Future<void> _feature(bool featured) => _run(
      () => context
          .read<AdminProviderDetailProvider>()
          .feature(widget.id, featured),
      featured ? 'Mis en avant' : 'Retiré de la mise en avant');

  /// Manual billing (T54): the salon paid via « Nous contacter » — record
  /// N months. Republishes a billing-unpublished salon server-side.
  Future<void> _markPaid() async {
    final months = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Paiement reçu — combien de mois ?'),
        children: [
          for (final m in const [1, 3, 6, 12])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text('$m mois'),
            ),
        ],
      ),
    );
    if (months == null || !mounted) return;
    await _run(
        () => context
            .read<AdminProviderDetailProvider>()
            .markPaid(widget.id, months),
        'Paiement enregistré ($months mois)');
  }

  Future<void> _run(Future<bool> Function() action, String okMsg) async {
    final p = context.read<AdminProviderDetailProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await action();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? okMsg : (p.actionError ?? 'Échec'))),
    );
    if (ok) unawaited(context.read<AdminProvidersProvider>().load());
  }

  Future<void> _openDispute(String appointmentId) async {
    final reason = await showReasonDialog(
      context,
      title: 'Ouvrir un litige',
      confirmLabel: 'Ouvrir',
      hint: 'Motif du litige',
    );
    if (reason == null || !mounted) return;
    final disputes = context.read<AdminDisputesProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await disputes.open(appointmentId, reason);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Litige ouvert' : (disputes.actionError ?? 'Échec')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminProviderDetailProvider>();
    return AdminScaffold(
      title: 'Salon',
      showBack: true,
      child: _body(p),
    );
  }

  Widget _body(AdminProviderDetailProvider p) {
    if (p.isLoading && p.provider == null) return const LoadingIndicator();
    if (p.provider == null) {
      return AdminDetailError(
        message: p.error ?? 'Introuvable',
        onRetry: () =>
            context.read<AdminProviderDetailProvider>().load(widget.id),
      );
    }
    final s = p.provider!;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _profile(s)),
                const SizedBox(width: AppTheme.spacingL),
                Expanded(
                  flex: 3,
                  child: AdminBookingsCard(
                    items: p.appointments,
                    onOpenDispute: _openDispute,
                  ),
                ),
              ],
            ),
          ),
        ),
        _actionBar(s, p.acting),
      ],
    );
  }

  Widget _profile(Map<String, dynamic> s) {
    final featured = s['featured'] == true;
    final rating = (s['rating'] as num?)?.toDouble();
    return AdminProfileCard(
      title: '${s['name'] ?? '—'}',
      status: '${s['status'] ?? 'active'}',
      rows: [
        ('Commune', '${s['commune'] ?? '—'}'),
        if ((s['address'] ?? '').toString().isNotEmpty)
          ('Adresse', '${s['address']}'),
        ('Téléphone', '${s['phoneNumber'] ?? s['phone'] ?? '—'}'),
        ('Note', rating == null ? '—' : '${rating.toStringAsFixed(1)} / 5'),
        ('En avant', featured ? 'Oui' : 'Non'),
      ],
    );
  }

  Widget _actionBar(Map<String, dynamic> s, bool acting) {
    final featured = s['featured'] == true;
    final suspended = s['status'] == 'suspended';
    return AdminActionBar(
      children: [
        SizedBox(
          width: 220,
          child: AppButton(
            text: featured ? 'Retirer la mise en avant' : 'Mettre en avant',
            type: AppButtonType.secondary,
            onPressed: acting ? null : () => _feature(!featured),
          ),
        ),
        const SizedBox(width: AppTheme.spacingM),
        SizedBox(
          width: 160,
          child: AppButton(
            text: suspended ? 'Réactiver' : 'Suspendre',
            type: suspended ? AppButtonType.primary : AppButtonType.secondary,
            isLoading: acting,
            onPressed: acting ? null : (suspended ? _restore : _suspend),
          ),
        ),
        const SizedBox(width: AppTheme.spacingM),
        SizedBox(
          width: 160,
          child: AppButton(
            text: 'Marquer payé',
            type: AppButtonType.secondary,
            onPressed: acting ? null : _markPaid,
          ),
        ),
      ],
    );
  }
}
