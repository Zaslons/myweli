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

/// KYC submission detail: business info + submitted docs (signed view URLs) +
/// approve / reject (reason). Design: docs/design/admin-console-ui.md.
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
    final reason = await _askReason();
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

  Future<String?> _askReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Motif du rejet'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Visible par le salon (ex. document illisible)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminKycProvider>();
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Vérification KYC')),
      body: Builder(
        builder: (context) {
          if (p.detailLoading && p.detail == null) {
            return const LoadingIndicator();
          }
          if (p.detail == null) {
            return Center(child: Text(p.detailError ?? 'Introuvable'));
          }
          final d = p.detail!;
          final docs =
              (d['docs'] as List? ?? const []).cast<Map<String, dynamic>>();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${d['businessName'] ?? '—'}',
                    style: AppTextStyles.titleMedium),
                Text(
                  '${d['businessType'] ?? ''} · ${d['phoneNumber'] ?? ''}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                ),
                const SizedBox(height: AppTheme.spacingL),
                Text('Documents', style: AppTextStyles.titleSmall),
                const SizedBox(height: AppTheme.spacingS),
                if (docs.isEmpty)
                  Text(
                    'Aucun document soumis.',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  )
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
                const SizedBox(height: AppTheme.spacingXL),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: 'Approuver',
                        isLoading: p.acting,
                        onPressed: p.acting ? null : _approve,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingM),
                    Expanded(
                      child: AppButton(
                        text: 'Rejeter',
                        type: AppButtonType.secondary,
                        onPressed: p.acting ? null : _reject,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
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
        const SizedBox(height: 4),
        Text(type, style: AppTextStyles.bodySmall),
      ],
    );
  }
}
