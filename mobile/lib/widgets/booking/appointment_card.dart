import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart' as provider_package;

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/salon_time.dart';
import '../../models/appointment.dart';
import '../../models/artist.dart';
import '../../models/provider.dart' as models;
import '../../models/service.dart';
import '../../providers/provider_provider.dart';
import '../common/timed_cached_image.dart';

class AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback onTap;

  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.onTap,
  });

  Color _getStatusColor(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return AppColors.warning;
      case AppointmentStatus.confirmed:
        return AppColors.success;
      case AppointmentStatus.completed:
        return AppColors.info;
      case AppointmentStatus.cancelled:
        return AppColors.error;
      case AppointmentStatus.noShow:
        return AppColors.warning;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return provider_package.Consumer<ProviderProvider>(
      builder: (context, providerProvider, _) {
        // Find provider for this appointment
        models.Provider? provider;
        try {
          provider = providerProvider.providers.firstWhere(
            (p) => p.id == appointment.providerId,
          );
        } catch (e) {
          // Provider not found, will show placeholder
          provider = null;
        }

        // Get services for this appointment
        final services = provider != null
            ? provider.services
                .where((s) => appointment.serviceIds.contains(s.id))
                .toList()
            : <Service>[];

        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(AppTheme.radiusXL),
              boxShadow: AppTheme.elevation1,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Provider Image
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium),
                      child: provider != null && provider.imageUrls.isNotEmpty
                          ? TimedCachedImage(
                              imageUrl: provider.imageUrls.first,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 80,
                              height: 80,
                              color: AppColors.surface,
                              child: const Icon(Icons.store,
                                  size: AppTheme.iconL,
                                  color: AppColors.textTertiary),
                            ),
                    ),
                    const SizedBox(width: AppTheme.spacingM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  provider?.name ?? 'Salon',
                                  style: AppTextStyles.titleMedium.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppTheme.spacingS,
                                  vertical: AppTheme.spacingXS,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(appointment.status)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.radiusSmall),
                                ),
                                child: Text(
                                  _getStatusText(appointment.status),
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: _getStatusColor(appointment.status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (provider != null && provider.city != null) ...[
                            const SizedBox(height: AppTheme.spacingXS),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (provider == null ||
                                    provider.latitude == null ||
                                    provider.longitude == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Localisation non disponible pour ce salon'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  return;
                                }
                                context.push(
                                    '/favorites?providerId=${provider.id}');
                              },
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      size: AppTheme.iconXS,
                                      color: AppColors.textTertiary),
                                  const SizedBox(width: AppTheme.spacingXS),
                                  Expanded(
                                    child: Text(
                                      provider.city ?? provider.address,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.map,
                                      size: AppTheme.iconXS,
                                      color: AppColors.textTertiary),
                                ],
                              ),
                            ),
                            if (provider.latitude != null &&
                                provider.longitude != null) ...[
                              const SizedBox(height: AppTheme.spacingXS),
                              GestureDetector(
                                onTap: () {
                                  Helpers.launchNavigation(
                                    latitude: provider!.latitude!,
                                    longitude: provider.longitude!,
                                    label: provider.name,
                                    context: context,
                                  );
                                },
                                child: Row(
                                  children: [
                                    const Icon(Icons.directions,
                                        size: AppTheme.iconXS,
                                        color: AppColors.primary),
                                    const SizedBox(width: AppTheme.spacingXS),
                                    Text(
                                      'Itinéraire',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingSM),
                // Auto-synced from the salon's manual booking (FR-APPT-008):
                // surfaced because it was made to this account's verified phone.
                if (appointment.clientName != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingS,
                      vertical: AppTheme.spacingXS,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.store_mall_directory_outlined,
                            size: AppTheme.iconXS, color: AppColors.info),
                        const SizedBox(width: AppTheme.spacingXS),
                        Text(
                          'Réservé par votre salon',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSM),
                ],
                // Services
                if (services.isNotEmpty) ...[
                  Text(
                    'Services:',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingXS),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: services.take(3).map((service) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingS,
                          vertical: AppTheme.spacingXS,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSmall),
                        ),
                        child: Text(
                          service.name,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (services.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: AppTheme.spacingXS),
                      child: Text(
                        '+ ${services.length - 3} autre(s)',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppTheme.spacingSM),
                ],
                // Artist
                if (appointment.artistId != null && provider != null) ...[
                  Builder(
                    builder: (context) {
                      final artist = provider!.artists.firstWhere(
                        (a) => a.id == appointment.artistId,
                        orElse: () => provider!.artists.isNotEmpty
                            ? provider.artists.first
                            : Artist(
                                id: '',
                                name: 'Artiste',
                                providerId: provider.id,
                              ),
                      );
                      return Row(
                        children: [
                          const Icon(Icons.person,
                              size: AppTheme.iconXS,
                              color: AppColors.textTertiary),
                          const SizedBox(width: AppTheme.spacingS),
                          Expanded(
                            child: Text(
                              artist.name,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingSM),
                ],
                // Date, Time, and Price
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: AppTheme.iconXS,
                              color: AppColors.textTertiary),
                          const SizedBox(width: AppTheme.spacingS),
                          Flexible(
                            child: Text(
                              Formatters.formatDateShort(toSalonTime(
                                  appointment.appointmentDate,
                                  tz: appointment.providerTimezone)),
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: AppTheme.iconXS,
                              color: AppColors.textTertiary),
                          const SizedBox(width: AppTheme.spacingS),
                          Flexible(
                            child: Text(
                              Formatters.formatTime(toSalonTime(
                                  appointment.appointmentDate,
                                  tz: appointment.providerTimezone)),
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingS),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total:',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      Formatters.formatCurrency(appointment.totalPrice,
                          currency: appointment.currency ??
                              appointment.providerCurrency ??
                              'XOF'),
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
