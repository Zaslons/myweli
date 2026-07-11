import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/data_export.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/loading_indicator.dart';

/// « Mes données » for salons (audit 11.5 — AUTH-005 for pros): assembles the
/// account, the listing, the catalogue and the salon's own records into one
/// JSON, copyable. Mirrors the consumer export screen. Design:
/// docs/design/pro-account-deletion-export.md.
class ProDataExportScreen extends StatefulWidget {
  const ProDataExportScreen({super.key});

  @override
  State<ProDataExportScreen> createState() => _ProDataExportScreenState();
}

class _ProDataExportScreenState extends State<ProDataExportScreen> {
  bool _loading = true;
  bool _failed = false;
  Map<String, dynamic>? _export;

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
      final auth = context.read<ProAuthProvider>();
      final account = auth.provider;
      final providerId = account?.providerId ?? account?.id;
      if (account == null || providerId == null) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }

      final salonRes =
          await serviceLocator.providerService.getProviderById(providerId);
      final services =
          await serviceLocator.proService.getProviderServices(providerId);
      final artists =
          await serviceLocator.proArtistService.getArtists(providerId);
      final appointments =
          await serviceLocator.proService.getProviderAppointments(providerId);
      final clients =
          await serviceLocator.proClientsService.listClients(providerId);

      final salon = salonRes.data;
      if (!mounted) return;
      if (salon == null) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }

      setState(() {
        _export = buildProviderDataExport(
          account: account,
          salon: salon,
          services: services.data ?? const [],
          artists: artists.data ?? const [],
          appointments: appointments.data ?? const [],
          clients: clients.data?.items ?? const [],
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
      body: _loading
          ? const LoadingIndicator()
          : _failed || _export == null
              ? EmptyState(
                  icon: Icons.wifi_off,
                  title: 'Chargement impossible',
                  description: 'Vérifiez votre connexion et réessayez.',
                  actionText: 'Réessayer',
                  onAction: _load,
                )
              : ListView(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  children: [
                    Text(
                      'Une copie des données de votre salon : compte, fiche, '
                      'catalogue, rendez-vous et fichier clients.',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: AppTheme.spacingM),
                    _CountRow(
                      label: 'Services',
                      count: (_export!['services'] as List).length,
                    ),
                    _CountRow(
                      label: 'Équipe',
                      count: (_export!['artists'] as List).length,
                    ),
                    _CountRow(
                      label: 'Rendez-vous',
                      count: (_export!['appointments'] as List).length,
                    ),
                    _CountRow(
                      label: 'Clients',
                      count: (_export!['clients'] as List).length,
                    ),
                    const SizedBox(height: AppTheme.spacingL),
                    AppButton(
                      text: 'Copier mes données (JSON)',
                      icon: Icons.copy_outlined,
                      onPressed: _copy,
                    ),
                  ],
                ),
    );
  }
}

class _CountRow extends StatelessWidget {
  final String label;
  final int count;

  const _CountRow({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium),
          Text(
            '$count',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
