import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/data_export.dart';
import '../../../models/api_response.dart';
import '../../../models/salon_client.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/empty_state.dart';
import '../../../widgets/common/label_value_row.dart';
import '../../../widgets/common/loading_indicator.dart';

/// « Mes données » for salons (audit 11.5 — AUTH-005 for pros): assembles the
/// account, the listing, the catalogue and the salon's own records into one
/// JSON, copyable. Mirrors the consumer export screen. Design:
/// docs/design/pro-account-deletion-export.md.
///
/// The export is whole or it is not offered: a read that fails, or a client
/// walk that does not add up, names the missing data and leaves nothing to
/// copy (docs/design/app-pro-export-completeness.md). A salon owner reads
/// `[]` as « no clients », not as « the read failed ».
class ProDataExportScreen extends StatefulWidget {
  const ProDataExportScreen({super.key});

  @override
  State<ProDataExportScreen> createState() => _ProDataExportScreenState();
}

class _ProDataExportScreenState extends State<ProDataExportScreen> {
  bool _loading = true;
  bool _failed = false;

  /// The sections whose read failed on the last attempt, named in the
  /// refusal. Empty while [_failed] = no session to read with.
  Set<ProExportSection> _failedSections = const {};
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
      _failedSections = const {};
    });
    final auth = context.read<ProAuthProvider>();
    final account = auth.provider;
    // The acting salon (R6), as on every pro screen: after a switch the
    // catalogue, team and clients are the switched-to salon's — like the
    // salon and bookings reads, which follow the session's selection.
    final salonId = auth.activeSalonId;
    if (account == null || salonId == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }

    // In parallel, each settled on its own: a failed read (an error answer
    // or a throw) is one missing section, never a rejected load. Concurrent
    // 401s share one refresh across the services (session-refresh.md). The
    // salon is read by account, not by public id (T51), so a draft salon
    // exports like a published one.
    final pro = serviceLocator.proService;
    final (info, services, artists, appointments, clients) = await (
      _read(() => pro.getMyProvider()),
      _read(() => pro.getProviderServices(salonId)),
      _read(() => serviceLocator.proArtistService.getArtists(salonId)),
      _read(() => pro.getProviderAppointments(salonId)),
      _walkClientBase(salonId),
    ).wait;
    if (!mounted) return;

    final salon = info?.salon;
    if (salon == null ||
        services == null ||
        artists == null ||
        appointments == null ||
        clients == null) {
      setState(() {
        _loading = false;
        _failed = true;
        _failedSections = {
          if (salon == null) ProExportSection.salon,
          if (services == null) ProExportSection.services,
          if (artists == null) ProExportSection.artists,
          if (appointments == null) ProExportSection.appointments,
          if (clients == null) ProExportSection.clients,
        };
      });
      return;
    }

    setState(() {
      _export = buildProviderDataExport(
        account: account,
        salon: salon,
        services: services,
        artists: artists,
        appointments: appointments,
        clients: clients,
      );
      _loading = false;
    });
  }

  Future<void> _copy() async {
    final export = _export;
    if (export == null) return;
    final json = const JsonEncoder.withIndent('  ').convert(export);
    await Clipboard.setData(ClipboardData(text: json));
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
      body: _loading
          ? const LoadingIndicator()
          : _failed || _export == null
          ? EmptyState(
              icon: Icons.wifi_off,
              title: 'Chargement impossible',
              description: _failedSections.isEmpty
                  ? 'Vérifiez votre connexion et réessayez.'
                  : proExportFailureMessage(_failedSections),
              actionText: 'Réessayer',
              onAction: _load,
            )
          : ListView(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              children: [
                Text(
                  'Une copie des données de votre salon : compte, fiche, '
                  'catalogue, rendez-vous et fichier clients.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
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
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
      child: LabelValueRow(
        label: label,
        value: '$count',
        valueStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// The page size of the export's client walk: the server's maximum
/// (`ClientsService.list` clamps to 50).
const int _clientWalkPageSize = 50;

/// One read's data, or null when it failed — an error answer or a throw.
Future<T?> _read<T>(Future<ApiResponse<T>> Function() read) async {
  try {
    final res = await read();
    return res.success ? res.data : null;
  } catch (_) {
    return null;
  }
}

/// Every client of the salon, page by page — or null when a page fails or
/// the walk does not add up ([wholeClientBase]). The pages go one after
/// another: page 1's `total` and `pageSize` decide how many there are.
Future<List<SalonClient>?> _walkClientBase(String salonId) async {
  final service = serviceLocator.proClientsService;
  final first = await _read(
    () => service.listClients(salonId, pageSize: _clientWalkPageSize),
  );
  if (first == null) return null;
  // The server's page size, not ours: it is the one its offsets used.
  final size = first.pageSize;
  if (size == null || size <= 0) return null;
  final pages = [first];
  final count = (first.total / size).ceil();
  for (var page = 2; page <= count; page++) {
    final next = await _read(
      () => service.listClients(salonId, page: page, pageSize: size),
    );
    if (next == null) return null;
    pages.add(next);
  }
  return wholeClientBase(pages);
}
