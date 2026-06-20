import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';

class BookingConfirmationScreen extends StatefulWidget {
  final String providerId;
  final List<String> serviceIds;
  final DateTime appointmentDateTime;
  final String? artistId;

  const BookingConfirmationScreen({
    super.key,
    required this.providerId,
    required this.serviceIds,
    required this.appointmentDateTime,
    this.artistId,
  });

  @override
  State<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen> {
  final _notesController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Check if user is authenticated, if not redirect to login
      if (!authProvider.isAuthenticated) {
        // Build return URL with booking details
        final returnUrl = Uri(
          path: '/booking/confirm',
          queryParameters: {
            'providerId': widget.providerId,
            'serviceIds': widget.serviceIds.join(','),
            'dateTime': widget.appointmentDateTime.toIso8601String(),
            if (widget.artistId != null) 'artistId': widget.artistId!,
          },
        );

        // Show a message that they need to sign in
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Veuillez vous connecter pour confirmer votre réservation'),
              duration: Duration(seconds: 2),
            ),
          );
        });

        context
            .go('/login?returnTo=${Uri.encodeComponent(returnUrl.toString())}');
        return;
      }

      final provider = Provider.of<ProviderProvider>(context, listen: false);
      provider.loadProviderById(widget.providerId);
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    setState(() => _isLoading = true);

    final appointmentProvider =
        Provider.of<AppointmentProvider>(context, listen: false);
    final success = await appointmentProvider.bookAppointment(
      providerId: widget.providerId,
      serviceIds: widget.serviceIds,
      appointmentDateTime: widget.appointmentDateTime,
      artistId: widget.artistId,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      context.go('/bookings');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rendez-vous réservé avec succès'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              appointmentProvider.error ?? 'Erreur lors de la réservation'),
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
        title: const Text('Confirmer'),
      ),
      body: Consumer<ProviderProvider>(
        builder: (context, provider, _) {
          final p = provider.selectedProvider;
          if (p == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final selectedServices = p.services
              .where((s) => widget.serviceIds.contains(s.id))
              .toList();
          final total = selectedServices.fold(0.0, (sum, s) => sum + s.price);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Card
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
                      // Provider
                      Row(
                        children: [
                          const Icon(Icons.store,
                              color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.name,
                              style: AppTextStyles.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // Services
                      ...selectedServices.map((service) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    service.name,
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                ),
                                Text(
                                  Formatters.formatCurrency(service.price),
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )),
                      // Artist
                      if (widget.artistId != null) ...[
                        const Divider(height: 24),
                        Builder(
                          builder: (context) {
                            final artist = p.artists.firstWhere(
                              (a) => a.id == widget.artistId,
                              orElse: () => p.artists.first, // Fallback
                            );
                            return Row(
                              children: [
                                const Icon(Icons.person,
                                    size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    artist.name,
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      const Divider(height: 24),
                      // Date & Time
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            Formatters.formatDateShort(
                                widget.appointmentDateTime),
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            Formatters.formatTime(widget.appointmentDateTime),
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // Total
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total:',
                            style: AppTextStyles.titleMedium,
                          ),
                          Text(
                            Formatters.formatCurrency(total),
                            style: AppTextStyles.titleLarge.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Notes
                AppTextField(
                  label: 'Notes (optionnel)',
                  hint: 'Ajoutez des instructions ou demandes spéciales',
                  controller: _notesController,
                  maxLines: 4,
                ),
                const SizedBox(height: 24),
                AppButton(
                  text: 'Confirmer la réservation',
                  onPressed: _isLoading ? null : _handleConfirm,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 16),
                Text(
                  'En confirmant, vous acceptez nos conditions d\'utilisation',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
