import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_loader.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/artist.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';

class ArtistSelectionScreen extends StatefulWidget {
  final String providerId;
  final List<String> serviceIds;
  final bool returnToHub;
  final String? initialArtistId;
  final DateTime? initialDateTime;
  final int? durationMinutes;

  const ArtistSelectionScreen({
    super.key,
    required this.providerId,
    required this.serviceIds,
    this.returnToHub = false,
    this.initialArtistId,
    this.initialDateTime,
    this.durationMinutes,
  });

  @override
  State<ArtistSelectionScreen> createState() => _ArtistSelectionScreenState();
}

class _ArtistSelectionScreenState extends State<ArtistSelectionScreen> {
  String? _selectedArtistId;
  bool _loadingTimeFilter = false;
  Set<String>? _artistIdsAvailableForSelectedTime;

  @override
  void initState() {
    super.initState();
    _selectedArtistId = widget.initialArtistId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ProviderProvider>(context, listen: false);
      provider.loadProviderById(widget.providerId);
    });
  }

  // Get available artists for the selected services
  List<Artist> _getAvailableArtists() {
    final provider = Provider.of<ProviderProvider>(context);
    final p = provider.selectedProvider;
    if (p == null || p.artists.isEmpty) return [];

    // Get all services that are selected
    final selectedServices =
        p.services.where((s) => widget.serviceIds.contains(s.id)).toList();

    // If no services chosen yet, show all artists (user can pick artist first).
    if (selectedServices.isEmpty) return p.artists;

    // If any service has no artistIds (empty list), all artists are available
    final hasUnrestrictedService =
        selectedServices.any((s) => s.artistIds.isEmpty);

    if (hasUnrestrictedService) {
      // All artists are available
      return p.artists;
    }

    // Find artists that can perform ALL selected services
    // An artist is available if they are in the artistIds list of ALL selected services
    final availableArtistIds = <String>{};

    // Start with artists from the first service
    if (selectedServices.isNotEmpty) {
      availableArtistIds.addAll(selectedServices.first.artistIds);
    }

    // Keep only artists that are in ALL services' artistIds
    for (final service in selectedServices.skip(1)) {
      if (service.artistIds.isEmpty) {
        // If a service has no restrictions, all artists are available
        return p.artists;
      }
      availableArtistIds
          .removeWhere((artistId) => !service.artistIds.contains(artistId));
    }

    // Return only the artists that are available for all services
    return p.artists
        .where((artist) => availableArtistIds.contains(artist.id))
        .toList();
  }

  Future<void> _loadArtistsAvailableForSelectedTime(
      List<Artist> candidates) async {
    final selected = widget.initialDateTime;
    if (selected == null) return;
    if (_artistIdsAvailableForSelectedTime != null || _loadingTimeFilter) {
      return;
    }

    setState(() => _loadingTimeFilter = true);
    final apptProvider =
        Provider.of<AppointmentProvider>(context, listen: false);
    final duration = widget.durationMinutes ?? 30;
    final day = DateTime(selected.year, selected.month, selected.day);

    final available = <String>{};
    for (final artist in candidates) {
      final slots = await apptProvider.getAvailableTimeSlots(
        providerId: widget.providerId,
        date: day,
        serviceIds: widget.serviceIds.isEmpty ? null : widget.serviceIds,
        artistId: artist.id,
        durationMinutes: duration,
      );
      final has = slots.any((dt) =>
          dt.year == selected.year &&
          dt.month == selected.month &&
          dt.day == selected.day &&
          dt.hour == selected.hour &&
          dt.minute == selected.minute);
      if (has) available.add(artist.id);
    }

    if (!mounted) return;
    setState(() {
      _artistIdsAvailableForSelectedTime = available;
      _loadingTimeFilter = false;
    });
  }

  void _handleContinue() {
    if (widget.returnToHub) {
      context.pop<String?>(_selectedArtistId);
      return;
    }

    final serviceIds = widget.serviceIds.join(',');
    final artistParam =
        _selectedArtistId != null ? '&artistId=$_selectedArtistId' : '';
    context.push(
        '/booking/date-time?providerId=${widget.providerId}&serviceIds=$serviceIds$artistParam');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Choisir un artiste'),
      ),
      body: Consumer<ProviderProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.selectedProvider == null) {
            return const LoadingIndicator();
          }

          final p = provider.selectedProvider;
          if (p == null) {
            return const Center(child: Text('Provider non trouvé'));
          }

          final availableArtists = _getAvailableArtists();
          if (widget.initialDateTime != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _loadArtistsAvailableForSelectedTime(availableArtists);
            });
          }

          final filteredArtists = (_artistIdsAvailableForSelectedTime == null)
              ? availableArtists
              : availableArtists
                  .where(
                      (a) => _artistIdsAvailableForSelectedTime!.contains(a.id))
                  .toList();

          if (availableArtists.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.person_off,
                      size: 64,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(height: AppTheme.spacingM),
                    Text(
                      'Aucun artiste disponible',
                      style: AppTextStyles.titleLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacingS),
                    Text(
                      'Aucun artiste ne peut effectuer tous les services sélectionnés. Veuillez modifier votre sélection.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacingL),
                    AppButton(
                      text: 'Retour',
                      onPressed: () => context.pop(),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  children: [
                    // Info Card
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacingM),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusLarge),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: AppTheme.spacingSM),
                          Expanded(
                            child: Text(
                              'Sélectionnez l\'artiste qui effectuera vos services',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingM),
                    if (_loadingTimeFilter)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppTheme.spacingM),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: BrandLoader(size: 20, fast: true),
                            ),
                            const SizedBox(width: AppTheme.spacingSM),
                            Expanded(
                              child: Text(
                                'Vérification des disponibilités…',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _ArtistCard(
                      artist: const Artist(
                        id: '',
                        name: 'Pas de préférence',
                        providerId: '',
                      ),
                      isSelected: _selectedArtistId == null,
                      onTap: () => setState(() => _selectedArtistId = null),
                      isNoPreference: true,
                    ),
                    // Artists List
                    ...filteredArtists.map((artist) {
                      final isSelected = _selectedArtistId == artist.id;
                      return _ArtistCard(
                        artist: artist,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedArtistId = artist.id;
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              // Continue Button
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  boxShadow: AppTheme.elevation3,
                ),
                child: AppButton(
                  text: 'Continuer',
                  onPressed: _handleContinue,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final Artist artist;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isNoPreference;

  const _ArtistCard({
    required this.artist,
    required this.isSelected,
    required this.onTap,
    this.isNoPreference = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderStrong,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Artist Image
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: isNoPreference
                  ? Container(
                      width: 60,
                      height: 60,
                      color: AppColors.surface,
                      child: const Icon(Icons.shuffle,
                          size: 26, color: AppColors.textTertiary),
                    )
                  : artist.imageUrl != null && artist.imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: artist.imageUrl!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 60,
                            height: 60,
                            color: AppColors.surface,
                            child: const Center(child: LoadingIndicator()),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 60,
                            height: 60,
                            color: AppColors.surface,
                            child: const Icon(Icons.person, size: 30),
                          ),
                        )
                      : Container(
                          width: 60,
                          height: 60,
                          color: AppColors.surface,
                          child: const Icon(Icons.person, size: 30),
                        ),
            ),
            const SizedBox(width: AppTheme.spacingSM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    style: AppTextStyles.titleMedium,
                  ),
                  if (!isNoPreference && artist.specialization != null) ...[
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(
                      artist.specialization!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (!isNoPreference && artist.rating != null) ...[
                    const SizedBox(height: AppTheme.spacingXS),
                    Row(
                      children: [
                        const Icon(Icons.star,
                            size: 14, color: AppColors.starRating),
                        const SizedBox(width: AppTheme.spacingXS),
                        Text(
                          artist.rating!.toStringAsFixed(1),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (artist.reviewCount != null) ...[
                          const SizedBox(width: AppTheme.spacingXS),
                          Text(
                            '(${artist.reviewCount})',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? AppColors.primary : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
