import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart' as provider_package;

import '../../core/constants/unnamed_salon.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/client_booking_rule.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/salon_place.dart';
import '../../core/utils/salon_time.dart';
import '../../models/appointment.dart';
import '../../models/artist.dart';
import '../../models/provider.dart' as models;
import '../../providers/provider_provider.dart';
import '../common/app_card.dart';
import '../common/app_chip.dart';
import '../common/label_value_row.dart';
import '../common/salon_photo_placeholder.dart';
import '../common/timed_cached_image.dart';

class AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback onTap;

  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.onTap,
  });

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

        // The booking's own facts first (consumer-app-truth.md §2.6): the
        // server sends the salon's name and the services' names on the
        // client's own bookings, and the discovery list only holds the page
        // that happens to be loaded — another commune, page two or a salon
        // that left the listing read « Salon » with no services.
        final salonName = salonNameOr(
          appointment.providerName ?? provider?.name,
          kUnnamedSalon,
        );
        final serviceNames = appointment.serviceNames.isNotEmpty
            ? appointment.serviceNames
            : [
                if (provider != null)
                  for (final s in provider.services)
                    if (appointment.serviceIds.contains(s.id)) s.name,
              ];

        // The place and the cover come off the booking first (A2,
        // appointment-detail-complete.md §2.9, decision 199), as the name did
        // in A1. The discovery list is only the fallback for an older server:
        // it holds the same salon's same facts, so it can lag the booking but
        // never contradict it.
        final photo = cardPhoto(
          appointment,
          listedPhoto: provider != null && provider.imageUrls.isNotEmpty
              ? provider.imageUrls.first
              : null,
        );
        final place = cardPlaceLine(
          appointment,
          listedCity: provider?.city,
          listedAddress: provider?.address,
        );
        final position = cardPosition(
          appointment,
          listedLat: provider?.latitude,
          listedLng: provider?.longitude,
        );

        return AppCard(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Provider Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    child: photo != null
                        ? TimedCachedImage(
                            imageUrl: photo,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          )
                        : const SalonPhotoPlaceholder(width: 80, height: 80),
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
                                salonName,
                                style: AppTextStyles.titleMedium.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              AppChip.status(
                                label: clientStatusLabel(
                                  appointment,
                                  AppClock.now(),
                                ),
                                tone: clientStatusTone(
                                  appointment,
                                  AppClock.now(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (place != null) ...[
                          const SizedBox(height: AppTheme.spacingXS),
                          // « Voir sur la carte » only with a position at a
                          // live salon: the map finds a salon through the
                          // public read, which 404s a stopped one, and would
                          // answer « Ce salon n’a pas pu être affiché sur la
                          // carte. » (§2.9). Otherwise the place is plain text.
                          if (position != null && appointment.salonIsLive)
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: 48,
                              ), // §13.2 touch target
                              child: Semantics(
                                button: true,
                                label: 'Voir sur la carte',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  // The map, on this salon. Was `/favorites`
                                  // — renamed `/carte` on 2026-08-22 (#491).
                                  onTap: () => context.push(
                                    '/carte?providerId=${appointment.providerId}',
                                  ),
                                  child: Center(
                                    child: _PlaceRow(place: place, onMap: true),
                                  ),
                                ),
                              ),
                            )
                          else
                            _PlaceRow(place: place, onMap: false),
                        ],
                        if (position case final pos?) ...[
                          const SizedBox(height: AppTheme.spacingS),
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 48,
                            ), // §13.2 touch target
                            child: Semantics(
                              button: true,
                              label: 'Itinéraire',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  Helpers.launchNavigation(
                                    latitude: pos.lat,
                                    longitude: pos.lng,
                                    label: salonName,
                                    context: context,
                                  );
                                },
                                child: Center(
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.directions,
                                        size: AppTheme.iconXS,
                                        color: AppColors.primary,
                                      ),
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
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingSM),
              // Auto-synced from the salon's manual booking (FR-APPT-008):
              // surfaced because it was made to this account's verified phone.
              // `userId == 'manual'`, the web's rule (A2 §1): the name is
              // what the salon typed, and it can be empty.
              if (appointment.isSalonEntered) ...[
                const AppChip.status(
                  label: 'Réservé par votre salon',
                  icon: Icons.store_mall_directory_outlined,
                  tone: AppChipTone.info,
                ),
                const SizedBox(height: AppTheme.spacingSM),
              ],
              // Services
              if (serviceNames.isNotEmpty) ...[
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
                  children: serviceNames.take(3).map((name) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingS,
                        vertical: AppTheme.spacingXS,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusSmall,
                        ),
                      ),
                      child: Text(
                        name,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (serviceNames.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTheme.spacingXS),
                    child: Text(
                      '+ ${Formatters.count(serviceNames.length - 3, 'autre', 'autres')}',
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
                        const Icon(
                          Icons.person,
                          size: AppTheme.iconXS,
                          color: AppColors.textTertiary,
                        ),
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
                      const Icon(
                        Icons.calendar_today,
                        size: AppTheme.iconXS,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: AppTheme.spacingS),
                      Text(
                        Formatters.formatDateShort(
                          toSalonTime(
                            appointment.appointmentDate,
                            tz: appointment.providerTimezone,
                          ),
                        ),
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: AppTheme.iconXS,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: AppTheme.spacingS),
                      Text(
                        Formatters.formatTime(
                          toSalonTime(
                            appointment.appointmentDate,
                            tz: appointment.providerTimezone,
                          ),
                        ),
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
                value: Formatters.formatCurrency(
                  appointment.totalPrice,
                  currency:
                      appointment.currency ??
                      appointment.providerCurrency ??
                      'XOF',
                ),
                labelStyle: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                valueStyle: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The card's place line: a pin, the place, and the map glyph when it opens
/// the map.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.onMap});

  final String place;
  final bool onMap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.location_on,
          size: AppTheme.iconXS,
          color: AppColors.textTertiary,
        ),
        const SizedBox(width: AppTheme.spacingXS),
        Expanded(
          child: Text(
            place,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onMap)
          const Icon(
            Icons.map,
            size: AppTheme.iconXS,
            color: AppColors.textTertiary,
          ),
      ],
    );
  }
}
