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
import '../../providers/provider_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_indicator.dart';

class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  bool _loading = true;
  bool _failed = false;
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
      _failed = false;
    });

    try {
      final user = context.read<AuthProvider>().user;
      if (user == null) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }

      final appointments = context.read<AppointmentProvider>();
      final favorites = context.read<FavoritesProvider>();
      final providers = context.read<ProviderProvider>();

      await Future.wait([
        appointments.loadAppointments(),
        favorites.loadFavorites(user.id),
        if (providers.providers.isEmpty) providers.loadProviders(),
      ]);

      if (!mounted) return;

      final names = favorites.favoriteProviderIds.map((id) {
        final match = providers.providers.where((p) => p.id == id);
        return match.isEmpty ? id : match.first.name;
      }).toList();

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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _copy() async {
    final export = _export;
    if (export == null) return;
    final json = const JsonEncoder.withIndent('  ').convert(export);
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Données copiées dans le presse-papiers'),
        backgroundColor: AppColors.success,
      ),
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

  Widget _buildBody() {
    if (_loading) {
      return const LoadingIndicator();
    }
    if (_failed || _export == null) {
      return EmptyState(
        icon: Icons.wifi_off,
        title: 'Chargement impossible',
        description: 'Vérifiez votre connexion et réessayez.',
        actionText: 'Réessayer',
        onAction: _load,
      );
    }

    final profile = _export!['profile'] as Map<String, dynamic>;
    final user = context.read<AuthProvider>().user;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        Text(
          'Généré le ${Formatters.formatDate(DateTime.parse(_export!['generatedAt'] as String))}',
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
              profile['phoneNumber'] as String,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
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
          const SizedBox(height: 2),
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
