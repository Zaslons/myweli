import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/data_export.dart';
import '../../core/utils/formatters.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../widgets/common/app_async_view.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_skeleton.dart';
import '../../widgets/common/app_snack_bar.dart';

/// « Mes données » (FR-AUTH-005): the profile, the appointments and the
/// favourites, assembled on the device into one JSON the client can copy.
///
/// The copy is whole or it is not offered: a read that fails names the
/// missing data and the screen offers « Réessayer », never a section emptied
/// by its failure (docs/design/consumer-export-completeness.md).
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  bool _loading = true;

  /// The reads that failed on the last attempt. Not empty → the refusal, and
  /// nothing to copy: a section emptied by its failure reads as « you have
  /// none » (docs/design/consumer-export-completeness.md §3).
  List<DataExportSection> _failed = const [];

  /// Every read answered and the file could not be made from them — its own
  /// sentence, not the reads (docs/design/web-client-polish.md §2.3).
  bool _buildFailed = false;
  Map<String, dynamic>? _export;
  int _appointmentCount = 0;
  int _favoriteCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = const [];
      _buildFailed = false;
    });

    try {
      final user = context.read<AuthProvider>().user;
      if (user == null) {
        setState(() {
          _loading = false;
          _failed = const [DataExportSection.profile];
        });
        return;
      }

      final appointments = context.read<AppointmentProvider>();
      final favorites = context.read<FavoritesProvider>();

      // `force`: the account as it is now, not the list this session read
      // first. Neither load throws — each sets its list and its `error`
      // together, so `error == null` means the list is a real answer.
      await Future.wait([
        appointments.loadAppointments(),
        favorites.loadFavorites(user.id, force: true),
      ]);

      if (!mounted) return;

      final failed = [
        if (appointments.error != null) DataExportSection.appointments,
        if (favorites.error != null) DataExportSection.favorites,
      ];
      if (failed.isNotEmpty) {
        setState(() {
          _loading = false;
          _failed = failed;
        });
        return;
      }

      // The salons as the favourites read hydrated them — a stopped one
      // included, which the discovery list leaves out.
      final names = [for (final p in favorites.favoriteProviders) p.name];

      setState(() {
        _appointmentCount = appointments.appointments.length;
        _favoriteCount = names.length;
        _export = buildUserDataExport(
          user: user,
          appointments: appointments.appointments,
          favoriteProviderNames: names,
        );
        _loading = false;
      });
    } catch (_) {
      // Neither load throws (see above): what throws here is the file being
      // made from answers that came. It used to name both reads.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _buildFailed = true;
      });
    }
  }

  Future<void> _copy() async {
    final export = _export;
    if (export == null) return;
    final json = const JsonEncoder.withIndent('  ').convert(export);
    try {
      await Clipboard.setData(ClipboardData(text: json));
    } on PlatformException {
      if (!mounted) return;
      AppSnackBar.show(context, kDataExportCopyFailed, kind: SnackKind.error);
      return;
    }
    if (!mounted) return;
    AppSnackBar.show(
      context,
      'Données copiées dans le presse-papiers',
      kind: SnackKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Mes données')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() => AppAsyncView<Map<String, dynamic>>(
    isLoading: _loading,
    error: _buildFailed
        ? kDataExportBuildFailed
        : _failed.isNotEmpty
        ? dataExportFailureMessage(_failed)
        : null,
    data: _export,
    isEmpty: (_) => false,
    loading: const SkeletonDetail(sections: 2),
    empty: const SizedBox.shrink(),
    onRetry: _load,
    builder: (context, export) => _ready(export),
  );

  Widget _ready(Map<String, dynamic> export) {
    final profile = export['profile'] as Map<String, dynamic>;
    final user = context.read<AuthProvider>().user;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        Text(
          'Généré le ${Formatters.formatDate(DateTime.parse(export['generatedAt'] as String))}',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        _SectionCard(
          label: 'Profil',
          child: Text(
            [
              (profile['name'] as String?) ?? 'Utilisateur',
              // The web's « Profil » line. The phone is optional since the
              // auth overhaul: an `as String` here threw for every account
              // signed in by email that had not saved one yet.
              ?((profile['email'] as String?) ??
                  (profile['phoneNumber'] as String?)),
              if (user != null)
                'membre depuis ${Formatters.formatDate(user.createdAt)}',
            ].join(' · '),
            style: AppTextStyles.bodyMedium,
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                value: _appointmentCount,
                label: 'Rendez-vous',
              ),
            ),
            const SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: _MetricCard(value: _favoriteCount, label: 'Favoris'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingM),
        Text(
          'Ces données vous appartiennent. Vous pouvez les copier au format JSON pour les conserver.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingL),
        AppButton(
          text: 'Copier mes données (JSON)',
          icon: Icons.copy,
          onPressed: _copy,
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String label;
  final Widget child;

  const _SectionCard({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXS),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final int value;
  final String label;

  const _MetricCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
