import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../providers/admin/admin_disputes_provider.dart';
import '../../providers/admin/admin_user_detail_provider.dart';
import '../../providers/admin/admin_users_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';
import 'widgets/admin_detail_widgets.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/reason_dialog.dart';

/// Client support view: profile + recent bookings + ban/réactiver.
/// Design: docs/design/admin-console-ui.md §3.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AdminUserDetailProvider>().load(widget.id),
    );
  }

  Future<void> _ban() async {
    final reason = await showReasonDialog(
      context,
      title: 'Bannir ce client ?',
      confirmLabel: 'Bannir',
      hint: 'Motif (interne)',
      reasonRequired: false,
    );
    if (reason == null || !mounted) return;
    await _run(
        () => context.read<AdminUserDetailProvider>().ban(widget.id, reason),
        'Client banni');
  }

  Future<void> _unban() => _run(
      () => context.read<AdminUserDetailProvider>().unban(widget.id),
      'Client réactivé');

  Future<void> _run(Future<bool> Function() action, String okMsg) async {
    final p = context.read<AdminUserDetailProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await action();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? okMsg : (p.actionError ?? 'Échec'))),
    );
    if (ok) unawaited(context.read<AdminUsersProvider>().load());
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
    final p = context.watch<AdminUserDetailProvider>();
    return AdminScaffold(
      title: 'Client',
      showBack: true,
      child: _body(p),
    );
  }

  Widget _body(AdminUserDetailProvider p) {
    if (p.isLoading && p.user == null) return const LoadingIndicator();
    if (p.user == null) {
      return AdminDetailError(
        message: p.error ?? 'Introuvable',
        onRetry: () => context.read<AdminUserDetailProvider>().load(widget.id),
      );
    }
    final u = p.user!;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _profile(u)),
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
        _actionBar(u, p.acting),
      ],
    );
  }

  Widget _profile(Map<String, dynamic> u) {
    final joined = DateTime.tryParse('${u['createdAt'] ?? ''}');
    return AdminProfileCard(
      title: '${u['name'] ?? 'Client'}',
      status: '${u['status'] ?? 'active'}',
      rows: [
        ('Téléphone', '${u['phoneNumber'] ?? '—'}'),
        (
          'Inscrit le',
          joined == null ? '—' : Formatters.formatDateShort(joined)
        ),
      ],
    );
  }

  Widget _actionBar(Map<String, dynamic> u, bool acting) {
    final banned = u['status'] == 'banned';
    return AdminActionBar(
      children: [
        SizedBox(
          width: 160,
          child: AppButton(
            text: banned ? 'Réactiver' : 'Bannir',
            type: banned ? AppButtonType.primary : AppButtonType.secondary,
            isLoading: acting,
            onPressed: acting ? null : (banned ? _unban : _ban),
          ),
        ),
      ],
    );
  }
}
