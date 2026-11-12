import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/external_link.dart';
import '../../providers/admin/admin_kyc_provider.dart';
import '../../widgets/common/app_async_view.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_skeleton.dart';
import '../../widgets/common/app_snack_bar.dart';
import 'widgets/admin_remote_image.dart';
import 'widgets/admin_scaffold.dart';
import 'widgets/reason_dialog.dart';
import 'widgets/status_chip.dart';

/// KYC submission detail: business info + status (left), submitted documents via
/// signed view URLs (right), and a sticky approve / reject action bar — only
/// while the file awaits review. A PDF is a tile that opens in a new tab.
/// Design: docs/design/admin-console-ui.md §3,
/// docs/design/admin-kyc-queue-submitted.md §4.5–§4.7.
///
/// The French document labels mirror the Pro app (`pro_kyc_screen.dart`,
/// `_label`) and the web (`web/lib/pro/kyc.ts`, `KYC_DOC_TYPES`): the tile
/// printed the wire id (`idCard`).
const Map<String, String> kKycDocumentLabels = {
  'idCard': 'Pièce d’identité (CNI / passeport)',
  'selfie': 'Photo du visage',
  'businessRegistration': 'Registre de commerce (RCCM)',
  'addressProof': 'Justificatif d’adresse',
};

/// The signed links live 5 minutes (`_docTtl`, backend `admin_kyc_service.dart`).
/// Images load at once and stay in memory; a PDF is fetched only when clicked,
/// so past this its tile offers a fresh link instead of an expired one.
const Duration kKycLinkFreshFor = Duration(minutes: 4, seconds: 30);

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
      AppSnackBar.showOn(messenger, 'Salon vérifié', kind: SnackKind.success);
      context.go('/admin/kyc');
      unawaited(p.loadQueue());
    } else {
      AppSnackBar.showOn(
        messenger,
        p.actionError ?? 'Action impossible',
        kind: SnackKind.error,
      );
    }
  }

  Future<void> _reject() async {
    final reason = await showReasonDialog(
      context,
      title: 'Motif du rejet',
      confirmLabel: 'Rejeter',
      isDestructive: true,
      hint: 'Visible par le salon (ex. document illisible)',
    );
    if (reason == null || !mounted) return;
    final p = context.read<AdminKycProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await p.reject(widget.accountId, reason);
    if (!mounted) return;
    if (ok) {
      AppSnackBar.showOn(messenger, 'Demande rejetée', kind: SnackKind.success);
      context.go('/admin/kyc');
      unawaited(p.loadQueue());
    } else {
      AppSnackBar.showOn(
        messenger,
        p.actionError ?? 'Action impossible',
        kind: SnackKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminKycProvider>();
    return AdminScaffold(title: 'Vérification KYC', child: _body(context, p));
  }

  // « Réessayer » was missing here: a failed file was a bare sentence.
  Widget _body(
    BuildContext context,
    AdminKycProvider p,
  ) => AppAsyncView<Map<String, dynamic>>(
    isLoading: p.detailLoading,
    error: p.detailError,
    // Another file's, on this screen's first frame (the provider outlives it).
    data: p.detailId == widget.accountId ? p.detail : null,
    isEmpty: (_) => false,
    loading: const SkeletonDetail(sections: 2),
    empty: const SizedBox.shrink(),
    onRetry: () =>
        context.read<AdminKycProvider>().loadDetail(widget.accountId),
    builder: (context, d) => _detail(p, d),
  );

  Widget _detail(AdminKycProvider p, Map<String, dynamic> d) {
    final docs = (d['docs'] as List? ?? const []).cast<Map<String, dynamic>>();
    // `!= false`, not `== true`: a backend from before the field has none,
    // and must keep today's buttons rather than lose them.
    final awaiting = d['awaitingReview'] != false;
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
                Expanded(
                  flex: 3,
                  child: _documents(docs, p.detailLoadedAt ?? AppClock.now()),
                ),
              ],
            ),
          ),
        ),
        if (awaiting) _actionBar(p) else _notPendingBar(),
      ],
    );
  }

  Widget _info(Map<String, dynamic> d) {
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
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
                child: Text(
                  '${d['businessName'] ?? '—'}',
                  style: AppTextStyles.titleMedium,
                ),
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

  Widget _documents(List<Map<String, dynamic>> docs, DateTime loadedAt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Documents', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppTheme.spacingS),
        if (docs.isEmpty)
          Text(
            'Aucun document soumis.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          )
        else
          Wrap(
            spacing: AppTheme.spacingM,
            runSpacing: AppTheme.spacingM,
            children: [
              for (final doc in docs)
                _DocTile(
                  label: kKycDocumentLabels[doc['type']] ?? 'Document',
                  url: doc['viewUrl'] as String?,
                  isPdf: doc['format'] == 'pdf',
                  loadedAt: loadedAt,
                  onRefresh: () => context.read<AdminKycProvider>().loadDetail(
                    widget.accountId,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// In place of the buttons when the file does not await review (reached by
  /// URL or from a salon request's KYC link, or acted on meanwhile): the
  /// server would refuse them (409).
  Widget _notPendingBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Text(
        'Aucune soumission en attente.',
        textAlign: TextAlign.end,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
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
  const _DocTile({
    required this.label,
    required this.url,
    required this.isPdf,
    required this.loadedAt,
    required this.onRefresh,
  });
  final String label;
  final String? url;
  final bool isPdf;
  final DateTime loadedAt;
  final VoidCallback onRefresh;

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
                : isPdf
                ? _PdfTile(
                    label: label,
                    url: url!,
                    loadedAt: loadedAt,
                    onRefresh: onRefresh,
                  )
                : GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => Dialog(
                        backgroundColor: Colors.transparent,
                        child: InteractiveViewer(
                          child: AdminRemoteImage(
                            url: url!,
                            fit: BoxFit.contain,
                            // The file reloads under the zoom: close it first,
                            // or it keeps the dead link.
                            onReload: () {
                              Navigator.of(dialogContext).pop();
                              onRefresh();
                            },
                          ),
                        ),
                      ),
                    ),
                    // A signed link on R2's origin, which sends the console no
                    // CORS header: drawn by the browser (admin-remote-images.md).
                    // A failure reloads the file, which signs new links.
                    child: AdminRemoteImage(url: url!, onReload: onRefresh),
                  ),
          ),
        ),
        const SizedBox(height: AppTheme.spacingXS),
        SizedBox(
          width: 220,
          child: Text(label, style: AppTextStyles.bodySmall),
        ),
      ],
    );
  }
}

/// A PDF cannot be drawn as an image: Flutter's decoder and the browser's
/// both refuse its bytes, and the image tile showed « image not available »
/// (admin-kyc-queue-submitted.md §1.3). So it opens the signed link in a new
/// tab — `noopener,noreferrer`, on R2's origin, not the console's — where the
/// browser's own viewer shows it. Past [kKycLinkFreshFor] the link is about to
/// expire, and the tile reloads the file instead (a tab opened after an
/// `await` is what popup blockers stop).
class _PdfTile extends StatefulWidget {
  const _PdfTile({
    required this.label,
    required this.url,
    required this.loadedAt,
    required this.onRefresh,
  });
  final String label;
  final String url;
  final DateTime loadedAt;
  final VoidCallback onRefresh;

  @override
  State<_PdfTile> createState() => _PdfTileState();
}

class _PdfTileState extends State<_PdfTile> {
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant _PdfTile old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.loadedAt != widget.loadedAt) {
      _timer?.cancel();
      _expired = false;
      _arm();
    }
  }

  void _arm() {
    final left = kKycLinkFreshFor - AppClock.now().difference(widget.loadedAt);
    if (left <= Duration.zero) {
      _expired = true;
      return;
    }
    _timer = Timer(left, () {
      if (mounted) setState(() => _expired = true);
    });
  }

  /// The timer drives the label; the clock decides the click — a background
  /// tab's timers are throttled, so the label may lag behind the link.
  bool get _isExpired =>
      _expired ||
      AppClock.now().difference(widget.loadedAt) >= kKycLinkFreshFor;

  void _open() {
    if (_isExpired) {
      widget.onRefresh();
      return;
    }
    openExternalUrl(
      context,
      widget.url,
      failureMessage: 'Impossible d’ouvrir le document.',
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _expired;
    // The name sits ABOVE the InkWell and only the visible content is
    // excluded: `excludeSemantics` on this node would also drop the InkWell's
    // tap — a button a screen reader announces and cannot press.
    return Semantics(
      button: true,
      label: expired
          ? 'Lien expiré, actualiser : « ${widget.label} » (PDF)'
          : 'Ouvrir « ${widget.label} » (PDF) dans un nouvel onglet',
      child: Material(
        color: AppColors.surfaceVariant,
        child: InkWell(
          onTap: _open,
          mouseCursor: SystemMouseCursors.click,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingS),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      expired ? Icons.refresh : Icons.picture_as_pdf_outlined,
                      size: AppTheme.iconL,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(
                      expired ? 'Lien expiré — Actualiser' : 'Document PDF',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
