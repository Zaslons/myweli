import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/admin/admin_kyc_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/timed_cached_image.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/reason_dialog.dart';
import 'widgets/status_chip.dart';

/// KYC submission detail: business info + status (left), submitted documents via
/// signed view URLs (right), and a sticky approve / reject action bar.
/// Design: docs/design/admin-console-ui.md §3.
class AdminKycDetailScreen extends StatefulWidget {
  const AdminKycDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  State<AdminKycDetailScreen> createState() => _AdminKycDetailScreenState();
}

class _AdminKycDetailScreenState extends State<AdminKycDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminKycProvider>().loadDetail(widget.accountId),
    );
  }

  Future<void> _approve() async {
    final p = context.read<AdminKycProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await p.approve(widget.accountId);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Salon vérifié')));
      context.go('/admin/kyc');
      unawaited(p.loadQueue());
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(p.actionError ?? 'Action impossible')),
      );
    }
  }

  Future<void> _reject() async {
    final reason = await showReasonDialog(
      context,
      title: 'Motif du rejet',
      confirmLabel: 'Rejeter',
      hint: 'Visible par le salon (ex. document illisible)',
    );
    if (reason == null || !mounted) return;
    final p = context.read<AdminKycProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await p.reject(widget.accountId, reason);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Demande rejetée')));
      context.go('/admin/kyc');
      unawaited(p.loadQueue());
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(p.actionError ?? 'Action impossible')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminKycProvider>();
    return AdminScaffold(
      title: 'Vérification KYC',
      child: _body(context, p),
    );
  }

  Widget _body(BuildContext context, AdminKycProvider p) {
    if (p.detailLoading && p.detail == null) return const LoadingIndicator();
    if (p.detail == null) {
      return Center(child: Text(p.detailError ?? 'Introuvable'));
    }
    final d = p.detail!;
    final docs = (d['docs'] as List? ?? const []).cast<Map<String, dynamic>>();
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _info(d)),
                const SizedBox(width: AppTheme.spacingL),
                Expanded(flex: 3, child: _documents(docs)),
              ],
            ),
          ),
        ),
        _actionBar(p),
      ],
    );
  }

  Widget _info(Map<String, dynamic> d) {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textTertiary)),
              Text(value, style: AppTextStyles.bodyMedium),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${d['businessName'] ?? '—'}',
                    style: AppTextStyles.titleMedium),
              ),
              StatusChip.forStatus(d['verificationStatus'] as String?),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
          row('Type', '${d['businessType'] ?? '—'}'),
          row('Téléphone', '${d['phoneNumber'] ?? '—'}'),
          if ((d['address'] ?? '').toString().isNotEmpty)
            row('Adresse', '${d['address']}'),
        ],
      ),
    );
  }

  Widget _documents(List<Map<String, dynamic>> docs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Documents', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppTheme.spacingS),
        if (docs.isEmpty)
          Text('Aucun document soumis.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textTertiary))
        else
          Wrap(
            spacing: AppTheme.spacingM,
            runSpacing: AppTheme.spacingM,
            children: [
              for (final doc in docs)
                _DocTile(
                  type: '${doc['type'] ?? 'Document'}',
                  url: doc['viewUrl'] as String?,
                ),
            ],
          ),
      ],
    );
  }

  Widget _actionBar(AdminKycProvider p) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: 160,
            child: AppButton(
              text: 'Rejeter',
              type: AppButtonType.secondary,
              onPressed: p.acting ? null : _reject,
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          SizedBox(
            width: 160,
            child: AppButton(
              text: 'Approuver',
              isLoading: p.acting,
              onPressed: p.acting ? null : _approve,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.type, required this.url});
  final String type;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: SizedBox(
            width: 220,
            height: 160,
            child: url == null
                ? const ColoredBox(
                    color: AppColors.surfaceVariant,
                    child: Center(child: Icon(Icons.description_outlined)),
                  )
                : GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: Colors.transparent,
                        child: InteractiveViewer(
                          child: TimedCachedImage(
                            imageUrl: url!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    child: TimedCachedImage(imageUrl: url!, fit: BoxFit.cover),
                  ),
          ),
        ),
        const SizedBox(height: AppTheme.spacingXS),
        Text(type, style: AppTextStyles.bodySmall),
      ],
    );
  }
}
