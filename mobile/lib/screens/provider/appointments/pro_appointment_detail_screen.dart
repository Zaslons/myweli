import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/status_colors.dart';
import '../../../models/api_response.dart';
import '../../../models/appointment.dart';
import '../../../providers/pro_appointment_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/timed_cached_image.dart';

class ProAppointmentDetailScreen extends StatefulWidget {
  final String appointmentId;

  const ProAppointmentDetailScreen({
    super.key,
    required this.appointmentId,
  });

  @override
  State<ProAppointmentDetailScreen> createState() =>
      _ProAppointmentDetailScreenState();
}

class _ProAppointmentDetailScreenState
    extends State<ProAppointmentDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.provider != null) {
        final appointmentProvider =
            Provider.of<ProAppointmentProvider>(context, listen: false);
        appointmentProvider.loadAppointments(authProvider.provider!.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Détails du rendez-vous'),
      ),
      body: Consumer2<ProAuthProvider, ProAppointmentProvider>(
        builder: (context, authProvider, appointmentProvider, _) {
          final appointment = appointmentProvider.appointments.firstWhere(
            (a) => a.id == widget.appointmentId,
            orElse: () => Appointment(
              id: widget.appointmentId,
              userId: '',
              providerId: '',
              serviceIds: const [],
              appointmentDate: DateTime.now(),
              status: AppointmentStatus.pending,
              totalPrice: 0,
              createdAt: DateTime.now(),
            ),
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingM),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Module clients C1c: who's coming — with the no-show
                        // badge at the accept moment (story #5) + card link.
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                appointment.clientName ?? 'Client',
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if ((appointment.clientNoShowCount ?? 0) >= 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: ((appointment.clientNoShowCount ??
                                              0) >=
                                          2)
                                      ? AppColors.error.withValues(alpha: 0.1)
                                      : AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusSmall,
                                  ),
                                ),
                                child: Text(
                                  appointment.clientNoShowCount == 1
                                      ? '1 absence'
                                      : '${appointment.clientNoShowCount} absences',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color:
                                        ((appointment.clientNoShowCount ?? 0) >=
                                                2)
                                            ? AppColors.error
                                            : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (appointment.salonClientId != null)
                          GestureDetector(
                            onTap: () => context.push(
                              '/pro/clients/${appointment.salonClientId}',
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Voir la fiche client',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textTertiary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'Date et heure',
                          style: AppTextStyles.titleMedium
                              .copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Formatters.formatDateTime(
                              appointment.appointmentDate),
                          style: AppTextStyles.bodyLarge
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Statut',
                          style: AppTextStyles.titleMedium
                              .copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Chip(
                          label: Text(_getStatusText(appointment.status)),
                          backgroundColor: _getStatusColor(appointment.status),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Prix total',
                          style: AppTextStyles.titleMedium
                              .copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Formatters.formatCurrency(appointment.totalPrice),
                          style: AppTextStyles.headlineSmall
                              .copyWith(color: AppColors.primary),
                        ),
                        if (appointment.depositAmount > 0) ...[
                          const Divider(height: 24),
                          Row(
                            children: [
                              const Icon(Icons.savings_outlined,
                                  size: 18, color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Acompte annoncé : '
                                  '${Formatters.formatCurrency(appointment.depositAmount)}',
                                  style: AppTextStyles.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Confirmez le rendez-vous une fois l\'acompte reçu '
                            'sur votre compte Mobile Money.',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.textTertiary),
                          ),
                          const SizedBox(height: 8),
                          _DepositProof(
                            appointmentId: appointment.id,
                            hasProof: appointment.depositScreenshotUrl != null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (appointment.status == AppointmentStatus.pending) ...[
                  AppButton(
                    text: 'Accepter',
                    onPressed: () async {
                      final success = await appointmentProvider
                          .acceptAppointment(appointment.id);
                      if (success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Rendez-vous accepté')),
                        );
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    text: 'Rejeter',
                    type: AppButtonType.secondary,
                    onPressed: () async {
                      final success = await appointmentProvider
                          .rejectAppointment(appointment.id, null);
                      if (success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Rendez-vous rejeté')),
                        );
                        Navigator.pop(context);
                      }
                    },
                  ),
                ] else if (appointment.status ==
                    AppointmentStatus.confirmed) ...[
                  AppButton(
                    text: 'Marquer comme terminé',
                    onPressed: () async {
                      final success = await appointmentProvider
                          .markComplete(appointment.id);
                      if (success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Rendez-vous terminé')),
                        );
                        Navigator.pop(context);
                      }
                    },
                  ),
                  if (!appointment.appointmentDate.isAfter(DateTime.now())) ...[
                    const SizedBox(height: 12),
                    AppButton(
                      text: 'Marquer comme absent',
                      type: AppButtonType.secondary,
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Client absent ?'),
                            content: const Text(
                              'Le client ne s\'est pas présenté. L\'acompte '
                              'est conservé selon votre politique d\'annulation.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Annuler'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Confirmer'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !context.mounted) return;
                        final success = await appointmentProvider
                            .markNoShow(appointment.id);
                        if (success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Marqué comme absent')),
                          );
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Color _getStatusColor(AppointmentStatus status) =>
      appointmentStatusColor(status);

  String _getStatusText(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return 'En attente';
      case AppointmentStatus.confirmed:
        return 'Confirmé';
      case AppointmentStatus.completed:
        return 'Terminé';
      case AppointmentStatus.cancelled:
        return 'Annulé';
      case AppointmentStatus.noShow:
        return 'Absent';
    }
  }
}

/// Salon-side view of the consumer's deposit screenshot. The image is private;
/// it's fetched via a short-lived **signed URL** (the key on the appointment is
/// opaque and never rendered directly). Tap to enlarge.
class _DepositProof extends StatefulWidget {
  final String appointmentId;
  final bool hasProof;

  const _DepositProof({required this.appointmentId, required this.hasProof});

  @override
  State<_DepositProof> createState() => _DepositProofState();
}

class _DepositProofState extends State<_DepositProof> {
  late Future<ApiResponse<String>> _url;

  @override
  void initState() {
    super.initState();
    if (widget.hasProof) {
      _url = serviceLocator.proService.depositScreenshotUrl(
        widget.appointmentId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasProof) {
      return Text(
        'Aucune capture jointe pour le moment.',
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
      );
    }
    return FutureBuilder<ApiResponse<String>>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 140,
            child: Center(child: LoadingIndicator()),
          );
        }
        final res = snapshot.data;
        if (res == null || !res.success || res.data == null) {
          return Text(
            'Capture indisponible. Réessayez plus tard.',
            style:
                AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
          );
        }
        final url = res.data!;
        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              child: InteractiveViewer(
                child: TimedCachedImage(imageUrl: url, fit: BoxFit.contain),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            child: TimedCachedImage(
              imageUrl: url,
              height: 140,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}
