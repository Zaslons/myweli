import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart' as provider_package;

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/salon_time.dart';
import '../../core/utils/status_labels.dart';
import '../../models/appointment.dart';
import '../../models/artist.dart';
import '../../models/provider.dart' as models;
import '../../models/service.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../common/label_value_row.dart';
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
                          // A12 — **the crush, third widget.** This is the same
                          // shape `ReviewTile` fixed in A11 C5 and
                          // `CompactAppointmentTile` fixed earlier in A12: a
                          // name flexed against an unflexed status pill. The
                          // earlier commit called it "one shape, two widgets";
                          // it is three, and this one is on « Mes rendez-vous ».
                          //
                          // It was **not** a prediction — the repo's own
                          // committed reference picture,
                          // `consumer_my_bookings_w360_x2.png`, shows « Salo… »
                          // and « Bea… ». The name box measures 88.8dp and
                          // 79.2dp at 360×2×: four characters and three, of the
                          // only thing that says which booking this is.
                          //
                          // `Wrap`, so the pill drops to its own line rather
                          // than eating the name. The `SizedBox` is
                          // load-bearing at all three call sites — a `Wrap`
                          // shrink-wraps, so `spaceBetween` inside one has no
                          // free space to distribute.
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: AppTheme.spacingS,
                              runSpacing: AppTheme.spacingXS,
                              children: [
                                Text(
                                  provider?.name ?? 'Salon',
                                  style: AppTextStyles.titleMedium.copyWith(
                                    color: AppColors.textPrimary,
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
                                    StatusLabels.of(appointment.status),
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color:
                                          _getStatusColor(appointment.status),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (provider != null && provider.city != null) ...[
                            const SizedBox(height: AppTheme.spacingXS),
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                  minHeight: 48), // §13.2 touch target
                              child: Semantics(
                                button: true,
                                label: 'Voir sur la carte',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    if (provider == null ||
                                        provider.latitude == null ||
                                        provider.longitude == null) {
                                      AppSnackBar.show(
                                        context,
                                        'Localisation non disponible pour ce salon',
                                        kind: SnackKind.error,
                                      );
                                      return;
                                    }
                                    context.push(
                                        '/favorites?providerId=${provider.id}');
                                  },
                                  child: Center(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.location_on,
                                            size: AppTheme.iconXS,
                                            color: AppColors.textTertiary),
                                        const SizedBox(
                                            width: AppTheme.spacingXS),
                                        Expanded(
                                          child: Text(
                                            provider.city ?? provider.address,
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
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
                                ),
                              ),
                            ),
                            if (provider.latitude != null &&
                                provider.longitude != null) ...[
                              const SizedBox(height: AppTheme.spacingS),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                    minHeight: 48), // §13.2 touch target
                                child: Semantics(
                                  button: true,
                                  label: 'Itinéraire',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      Helpers.launchNavigation(
                                        latitude: provider!.latitude!,
                                        longitude: provider.longitude!,
                                        label: provider.name,
                                        context: context,
                                      );
                                    },
                                    child: Center(
                                      child: Row(
                                        children: [
                                          const Icon(Icons.directions,
                                              size: AppTheme.iconXS,
                                              color: AppColors.primary),
                                          const SizedBox(
                                              width: AppTheme.spacingXS),
                                          Text(
                                            'Itinéraire',
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
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
                    spacing: AppTheme.spacingS,
                    runSpacing: AppTheme.spacingS,
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
                // Date and time.
                //
                // **A `Wrap`, not a `Row` of two `Expanded`s** (A11 C8, §13.3).
                // Halving the width forced the date into ~half a card, and at
                // 200% text `13/03/2026` did not fit — so Flutter broke it
                // INSIDE the token and rendered « 13/03/20 » / « 26 ». That is
                // not a wrap, it is a date cut in half, and nothing caught it:
                // the truncation walk permits wrapping by design and no overflow
                // fires, because wrapping is how the layout succeeds. Found by
                // C7's first 2× golden.
                //
                // Each half now takes its intrinsic width and the pair wraps as
                // two whole tokens when they stop fitting side by side.
                Wrap(
                  spacing: AppTheme.spacingM,
                  runSpacing: AppTheme.spacingS,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today,
                            size: AppTheme.iconXS,
                            color: AppColors.textTertiary),
                        const SizedBox(width: AppTheme.spacingS),
                        Text(
                          Formatters.formatDateShort(toSalonTime(
                              appointment.appointmentDate,
                              tz: appointment.providerTimezone)),
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time,
                            size: AppTheme.iconXS,
                            color: AppColors.textTertiary),
                        const SizedBox(width: AppTheme.spacingS),
                        Text(
                          Formatters.formatTime(toSalonTime(
                              appointment.appointmentDate,
                              tz: appointment.providerTimezone)),
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingS),
                LabelValueRow(
                  label: 'Total:',
                  value: Formatters.formatCurrency(appointment.totalPrice,
                      currency: appointment.currency ??
                          appointment.providerCurrency ??
                          'XOF'),
                  labelStyle: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  valueStyle: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
