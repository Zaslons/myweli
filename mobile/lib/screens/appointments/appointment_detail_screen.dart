import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../models/appointment.dart';
import '../../providers/appointment_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';

class AppointmentDetailScreen extends StatefulWidget {
  final String appointmentId;

  const AppointmentDetailScreen({
    super.key,
    required this.appointmentId,
  });

  @override
  State<AppointmentDetailScreen> createState() =>
      _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppointmentProvider>(context, listen: false);
      provider.loadAppointmentById(widget.appointmentId);
    });
  }

  Future<void> _handleCancel() async {
    final provider = Provider.of<AppointmentProvider>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler le rendez-vous'),
        content:
            const Text('Êtes-vous sûr de vouloir annuler ce rendez-vous ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oui'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await provider.cancelAppointment(widget.appointmentId);

    if (!mounted) return;

    if (success) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rendez-vous annulé'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Erreur lors de l\'annulation'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Détails'),
      ),
      body: Consumer<AppointmentProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.selectedAppointment == null) {
            return const LoadingIndicator();
          }

          final appointment = provider.selectedAppointment;
          if (appointment == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 64, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text(
                    provider.error ?? 'Rendez-vous non trouvé',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Appointment Info Card
                Container(
                  padding: const EdgeInsets.all(AppTheme.spacingL),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                    boxShadow: AppTheme.elevation1,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Informations du rendez-vous',
                        style: AppTextStyles.titleLarge,
                      ),
                      const Divider(height: 24),
                      _InfoRow(
                        icon: Icons.calendar_today,
                        label: 'Date',
                        value:
                            Formatters.formatDate(appointment.appointmentDate),
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.access_time,
                        label: 'Heure',
                        value:
                            Formatters.formatTime(appointment.appointmentDate),
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.attach_money,
                        label: 'Prix total',
                        value:
                            Formatters.formatCurrency(appointment.totalPrice),
                      ),
                      if (appointment.depositAmount > 0) ...[
                        const SizedBox(height: 16),
                        _InfoRow(
                          icon: Icons.check_circle_outline,
                          label: 'Acompte payé',
                          value: Formatters.formatCurrency(
                              appointment.depositAmount),
                        ),
                        const SizedBox(height: 16),
                        _InfoRow(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Solde à régler au salon',
                          value:
                              Formatters.formatCurrency(appointment.balanceDue),
                        ),
                      ],
                      if (appointment.notes != null &&
                          appointment.notes!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _InfoRow(
                          icon: Icons.note,
                          label: 'Notes',
                          value: appointment.notes!,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Action Buttons
                if (appointment.status != AppointmentStatus.cancelled &&
                    appointment.status != AppointmentStatus.completed)
                  AppButton(
                    text: 'Annuler le rendez-vous',
                    type: AppButtonType.secondary,
                    onPressed: _handleCancel,
                  ),
                const SizedBox(height: 8),
                AppButton(
                  text: 'Appeler',
                  icon: Icons.phone,
                  onPressed: () {
                    // Would open phone dialer in real app
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fonctionnalité à venir')),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTextStyles.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
