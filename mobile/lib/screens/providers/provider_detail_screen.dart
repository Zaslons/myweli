import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/helpers.dart';
import '../../models/appointment.dart';
import '../../models/availability.dart';
import '../../models/service.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/booking/compact_appointment_tile.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/timed_cached_image.dart';
import '../../widgets/providers/before_after_section.dart';
import '../../widgets/review/review_tile.dart';
import '../../widgets/review/submit_review_sheet.dart';

class ProviderDetailScreen extends StatefulWidget {
  final String providerId;

  /// Owner preview (docs/design/pro-salon-lifecycle.md B5): renders the
  /// LOGGED-OUT client view of the salon — no consumer session providers are
  /// read (the pro app registers only ProviderProvider), the booking CTA is
  /// disabled and an « Aperçu » banner tops the page.
  final bool preview;

  const ProviderDetailScreen({
    super.key,
    required this.providerId,
    this.preview = false,
  });

  @override
  State<ProviderDetailScreen> createState() => _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends State<ProviderDetailScreen> {
  bool _servicesExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ProviderProvider>(context, listen: false);
      provider.loadProviderById(widget.providerId);
      if (widget.preview) return; // owner preview: no consumer session

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.user != null) {
        final favoritesProvider =
            Provider.of<FavoritesProvider>(context, listen: false);
        favoritesProvider.loadFavorites(authProvider.user!.id);
        final appointmentProvider =
            Provider.of<AppointmentProvider>(context, listen: false);
        appointmentProvider.loadAppointments();
      }
    });
  }

  void _showFullScreenPhoto(
    BuildContext context,
    List<String> imageUrls,
    int initialIndex,
  ) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _FullScreenPhotoGallery(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  List<String> _formatWorkingHours(Availability availability) {
    const dayNames = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
    final lines = <String>[];
    for (var day = 0; day < 7; day++) {
      final slots = availability.weeklySchedule[day] ?? [];
      final available = slots.where((s) => s.isAvailable).toList();
      if (available.isEmpty) {
        lines.add('${dayNames[day]}: Fermé');
      } else {
        final first = available.first.startTime;
        final last = available.last.endTime;
        lines.add(
            '${dayNames[day]}: ${Formatters.formatTimeShort(first)}-${Formatters.formatTimeShort(last)}');
      }
    }
    return lines;
  }

  /// « Signaler » (FR-REV-005, parity 2.14): optional reason → POST report.
  Future<void> _reportReview(String reviewId) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connectez-vous pour signaler un avis.'),
        ),
      );
      return;
    }
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Signaler cet avis ?'),
        content: TextField(
          controller: reasonController,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Raison (optionnel)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Signaler'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await Provider.of<ProviderProvider>(context, listen: false)
        .reportReview(reviewId, reason: reasonController.text);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Merci. Notre équipe va examiner cet avis.'
              : 'Le signalement a échoué. Réessayez.',
        ),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<ProviderProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.selectedProvider == null) {
            return const LoadingIndicator();
          }

          final p = provider.selectedProvider;
          if (p == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: AppTheme.iconXL, color: AppColors.error),
                  const SizedBox(height: AppTheme.spacingM),
                  Text(
                    provider.error ?? 'Salon introuvable',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  AppButton(
                    text: 'Retour',
                    onPressed: () => context.pop(),
                    isFullWidth: false,
                  ),
                ],
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 160,
                pinned: true,
                actions: [
                  if (!widget.preview)
                    Consumer2<FavoritesProvider, AuthProvider>(
                      builder: (context, favoritesProvider, authProvider, _) {
                        final isFavorite = authProvider.isAuthenticated
                            ? favoritesProvider.isFavorite(widget.providerId)
                            : false;
                        final userId = authProvider.user?.id ?? '';

                        return IconButton(
                          icon: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: isFavorite
                                ? AppColors.favorite
                                : AppColors.secondary,
                          ),
                          onPressed: () async {
                            if (!authProvider.isAuthenticated) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Connectez-vous pour ajouter aux favoris'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              final currentPath =
                                  GoRouterState.of(context).uri.toString();
                              context.go(
                                  '/login?returnTo=${Uri.encodeComponent(currentPath)}');
                              return;
                            }
                            await favoritesProvider.toggleFavorite(
                                userId, widget.providerId);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isFavorite
                                        ? 'Retiré des favoris'
                                        : 'Ajouté aux favoris',
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    color: AppColors.secondary,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.spacingL,
                          AppTheme.spacingM,
                          AppTheme.spacingL,
                          AppTheme.spacingM,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SalonLogo(logoUrl: p.logoUrl),
                            const SizedBox(width: AppTheme.spacingM),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          p.name,
                                          style: AppTextStyles.headlineMedium
                                              .copyWith(
                                            color: AppColors.textPrimary,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (p.verified) ...[
                                        const SizedBox(
                                            width: AppTheme.spacingS),
                                        const Padding(
                                          padding: EdgeInsets.only(
                                              top: AppTheme.spacingXS),
                                          child: Icon(
                                            Icons.verified,
                                            size: AppTheme.iconS,
                                            color: AppColors.info,
                                            semanticLabel: 'Salon vérifié',
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: AppTheme.spacingS),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined,
                                          size: AppTheme.iconXS,
                                          color: AppColors.textTertiary),
                                      const SizedBox(width: AppTheme.spacingXS),
                                      Expanded(
                                        child: Text(
                                          p.city ?? p.address,
                                          style:
                                              AppTextStyles.bodySmall.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppTheme.spacingXS),
                                  Row(
                                    children: [
                                      const Icon(Icons.star,
                                          size: AppTheme.iconXS,
                                          color: AppColors.starRating),
                                      const SizedBox(width: AppTheme.spacingXS),
                                      Text(
                                        p.rating.toStringAsFixed(1),
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: AppTheme.spacingS),
                                      Text(
                                        '${p.reviewCount} avis',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacingL,
                    AppTheme.spacingM,
                    AppTheme.spacingL,
                    AppTheme.spacingL,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section: Vos rendez-vous ici
                      _SectionCard(
                        title: 'Vos rendez-vous ici',
                        trailing: widget.preview
                            ? null
                            : TextButton(
                                onPressed: () => context.push('/bookings'),
                                child: const Text('Voir tout'),
                              ),
                        child: widget.preview
                            // The logged-out client rendering, verbatim — no
                            // consumer providers exist in the pro app.
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppTheme.spacingS),
                                child: Text(
                                  'Connectez-vous pour voir vos rendez-vous.',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              )
                            : Consumer2<AuthProvider, AppointmentProvider>(
                                builder: (context, authProvider,
                                    appointmentProvider, _) {
                                  if (!authProvider.isAuthenticated) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: AppTheme.spacingS),
                                      child: Text(
                                        'Connectez-vous pour voir vos rendez-vous.',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    );
                                  }
                                  final atThisSalon = appointmentProvider
                                      .appointments
                                      .where((a) =>
                                          a.providerId == widget.providerId)
                                      .toList()
                                    ..sort((a, b) => b.appointmentDate
                                        .compareTo(a.appointmentDate));
                                  if (atThisSalon.isEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: AppTheme.spacingS),
                                      child: Text(
                                        'Aucun rendez-vous dans ce salon.',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    );
                                  }
                                  final top = atThisSalon.take(5).toList();
                                  return SizedBox(
                                    height: 100,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: top.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(
                                              width: AppTheme.spacingS),
                                      itemBuilder: (context, i) {
                                        final a = top[i];
                                        final w =
                                            MediaQuery.of(context).size.width;
                                        final cardWidth =
                                            (w * 0.75).clamp(260.0, 340.0);
                                        final isPast = a.status ==
                                                AppointmentStatus.completed ||
                                            a.status ==
                                                AppointmentStatus.cancelled ||
                                            a.appointmentDate
                                                .isBefore(DateTime.now());
                                        return SizedBox(
                                          width: cardWidth,
                                          child: CompactAppointmentTile(
                                            appointment: a,
                                            providerName: p.name,
                                            providerImageUrl:
                                                p.imageUrls.isNotEmpty
                                                    ? p.imageUrls.first
                                                    : null,
                                            hint: isPast
                                                ? 'Réserver à nouveau'
                                                : null,
                                            onTap: () {
                                              if (isPast) {
                                                // Past appointment → rebook the same
                                                // services/stylist.
                                                final uri = Uri(
                                                  path: '/booking',
                                                  queryParameters: {
                                                    'providerId':
                                                        widget.providerId,
                                                    if (a.serviceIds.isNotEmpty)
                                                      'serviceIds': a.serviceIds
                                                          .join(','),
                                                    if (a.artistId != null)
                                                      'artistId': a.artistId!,
                                                  },
                                                );
                                                context.push(uri.toString());
                                              } else {
                                                context.push(
                                                    '/appointment/${a.id}');
                                              }
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),

                      // Section: Services (expandable)
                      _SectionCard(
                        title: 'Services',
                        trailing: Icon(
                          _servicesExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: AppColors.textSecondary,
                        ),
                        onHeaderTap: () {
                          setState(
                              () => _servicesExpanded = !_servicesExpanded);
                        },
                        child: AnimatedCrossFade(
                          duration: const Duration(milliseconds: 200),
                          crossFadeState: _servicesExpanded
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          firstChild: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (p.services.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppTheme.spacingM),
                                  child: Text(
                                    'Aucun service pour le moment.',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                )
                              else
                                ...p.services.map(
                                  (service) => _ServiceTile(service: service),
                                ),
                            ],
                          ),
                          secondChild: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppTheme.spacingS),
                            child: Text(
                              '${p.services.length} service${p.services.length > 1 ? 's' : ''} • Voir les tarifs',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Section: Contact
                      _SectionCard(
                        title: 'Contact',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Address + map
                            InkWell(
                              onTap: () {
                                if (p.latitude == null || p.longitude == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Localisation non disponible'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  return;
                                }
                                context.push('/favorites?providerId=${p.id}');
                              },
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLarge),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppTheme.spacingS),
                                child: Row(
                                  children: [
                                    const Icon(Icons.map_outlined,
                                        size: AppTheme.iconS,
                                        color: AppColors.textTertiary),
                                    const SizedBox(width: AppTheme.spacingSM),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.address,
                                            style: AppTextStyles.bodyMedium
                                                .copyWith(
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            'Voir sur la carte',
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (p.latitude != null &&
                                        p.longitude != null)
                                      IconButton(
                                        icon: const Icon(Icons.directions,
                                            color: AppColors.primary),
                                        onPressed: () {
                                          Helpers.launchNavigation(
                                            latitude: p.latitude!,
                                            longitude: p.longitude!,
                                            label: p.name,
                                            context: context,
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const _Divider(),
                            // Phone
                            InkWell(
                              onTap: () async {
                                final uri = Uri.parse(
                                    'tel:${p.phoneNumber.replaceAll(RegExp(r'\s'), '')}');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                }
                              },
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLarge),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppTheme.spacingS),
                                child: Row(
                                  children: [
                                    const Icon(Icons.phone_outlined,
                                        size: AppTheme.iconS,
                                        color: AppColors.textTertiary),
                                    const SizedBox(width: AppTheme.spacingSM),
                                    Text(
                                      Formatters.formatPhoneNumber(
                                          p.phoneNumber),
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (p.whatsapp != null &&
                                p.whatsapp!.isNotEmpty) ...[
                              const _Divider(),
                              InkWell(
                                onTap: () async {
                                  final digits = p.whatsapp!
                                      .replaceAll(RegExp(r'[^0-9]'), '');
                                  final uri =
                                      Uri.parse('https://wa.me/$digits');
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri,
                                        mode: LaunchMode.externalApplication);
                                  }
                                },
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusLarge),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppTheme.spacingS),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.chat_outlined,
                                          size: AppTheme.iconS,
                                          color: AppColors.textTertiary),
                                      const SizedBox(width: AppTheme.spacingSM),
                                      Text(
                                        'WhatsApp',
                                        style:
                                            AppTextStyles.bodyMedium.copyWith(
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            // Working hours
                            const _Divider(),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppTheme.spacingXS),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.schedule_outlined,
                                      size: AppTheme.iconS,
                                      color: AppColors.textTertiary),
                                  const SizedBox(width: AppTheme.spacingSM),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: _formatWorkingHours(
                                              p.availability)
                                          .map((line) => Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: AppTheme.spacingXS),
                                                child: Text(
                                                  line,
                                                  style: AppTextStyles.bodySmall
                                                      .copyWith(
                                                    color:
                                                        AppColors.textSecondary,
                                                  ),
                                                ),
                                              ))
                                          .toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Section: Photos (always shown, even with one picture)
                      _SectionCard(
                        title: 'Photos',
                        child: p.imageUrls.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppTheme.spacingS),
                                child: Text(
                                  'Aucune photo pour le moment.',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              )
                            : SizedBox(
                                height: 120,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: p.imageUrls.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: AppTheme.spacingS),
                                  itemBuilder: (context, i) {
                                    return GestureDetector(
                                      onTap: () => _showFullScreenPhoto(
                                        context,
                                        p.imageUrls,
                                        i,
                                      ),
                                      child: SizedBox(
                                        width: 160,
                                        height: 120,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                              AppTheme.radiusLarge),
                                          child: TimedCachedImage(
                                            imageUrl: p.imageUrls[i],
                                            width: 160,
                                            height: 120,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),

                      // Section: Avant / Après (only when the salon has pairs)
                      if (p.beforeAfters.isNotEmpty)
                        _SectionCard(
                          title: 'Avant / Après',
                          child: BeforeAfterSection(pairs: p.beforeAfters),
                        ),

                      // Section: Avis (rating summary + reviews list + conditional CTA)
                      _SectionCard(
                        title: 'Avis',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.star,
                                    size: AppTheme.iconL,
                                    color: AppColors.starRating),
                                const SizedBox(width: AppTheme.spacingSM),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.rating.toStringAsFixed(1),
                                      style: AppTextStyles.titleLarge.copyWith(
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${p.reviewCount} avis',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (p.reviews.isNotEmpty) ...[
                              const SizedBox(height: AppTheme.spacingM),
                              ...p.reviews.take(5).map(
                                    (review) => Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: AppTheme.spacingS),
                                      child: ReviewTile(
                                        review: review,
                                        onReport: () =>
                                            _reportReview(review.id),
                                      ),
                                    ),
                                  ),
                            ],
                            if (!widget.preview)
                              Consumer2<AuthProvider, AppointmentProvider>(
                                builder: (context, authProvider,
                                    appointmentProvider, _) {
                                  final isAuthenticated =
                                      authProvider.isAuthenticated &&
                                          authProvider.user != null;
                                  final reviewableApptId = isAuthenticated
                                      ? appointmentProvider
                                          .latestCompletedAppointmentId(
                                          widget.providerId,
                                          authProvider.user!.id,
                                        )
                                      : null;
                                  if (reviewableApptId == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        top: AppTheme.spacingM),
                                    child: InkWell(
                                      onTap: () {
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          builder: (ctx) => Padding(
                                            padding: EdgeInsets.only(
                                              bottom: MediaQuery.of(ctx)
                                                  .viewInsets
                                                  .bottom,
                                            ),
                                            child: SubmitReviewSheet(
                                              providerId: widget.providerId,
                                              appointmentId: reviewableApptId,
                                            ),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(
                                          AppTheme.radiusLarge),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: AppTheme.spacingM,
                                          horizontal: AppTheme.spacingS,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius: BorderRadius.circular(
                                              AppTheme.radiusLarge),
                                          border: Border.all(
                                              color: AppColors.border),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.star_border,
                                              size: AppTheme.iconL,
                                              color: AppColors.textTertiary,
                                            ),
                                            const SizedBox(
                                                width: AppTheme.spacingSM),
                                            Text(
                                              'Donner mon avis',
                                              style: AppTextStyles.titleSmall
                                                  .copyWith(
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),

                      // Description
                      if (p.description.isNotEmpty)
                        _SectionCard(
                          title: 'À propos',
                          child: Text(
                            p.description,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),

                      // Fixed scroll-bottom clearance for the sticky reserve CTA
                      // — §5 governs grid gaps, not overlay clearance.
                      const SizedBox(height: 100), // ds-ignore
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Consumer<ProviderProvider>(
        builder: (context, provider, _) {
          final p = provider.selectedProvider;
          if (p == null) return const SizedBox.shrink();

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingM,
                AppTheme.spacingS,
                AppTheme.spacingM,
                AppTheme.spacingM,
              ),
              child: widget.preview
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Aperçu — voici ce que verront vos clients.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingS),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.calendar_today,
                                size: AppTheme.iconS),
                            label: const Text(
                              'Réserver (après la mise en ligne)',
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppTheme.spacingM),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(
                                  'tel:${p.phoneNumber.replaceAll(RegExp(r'\s'), '')}');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                            icon: const Icon(Icons.phone_outlined,
                                size: AppTheme.iconS),
                            label: const Text('Appeler'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(
                                  color: AppColors.borderStrong),
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppTheme.spacingM),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingSM),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                context.push('/booking?providerId=${p.id}'),
                            icon: const Icon(Icons.calendar_today,
                                size: AppTheme.iconS),
                            label: const Text('Réserver'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.secondary,
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppTheme.spacingM),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _FullScreenPhotoGallery extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final VoidCallback onClose;

  const _FullScreenPhotoGallery({
    required this.imageUrls,
    required this.initialIndex,
    required this.onClose,
  });

  @override
  State<_FullScreenPhotoGallery> createState() =>
      _FullScreenPhotoGalleryState();
}

class _FullScreenPhotoGalleryState extends State<_FullScreenPhotoGallery> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: widget.onClose,
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Center(
                    child: TimedCachedImage(
                      imageUrl: widget.imageUrls[index],
                      fit: BoxFit.cover,
                      width: size.width,
                      height: size.height,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close,
                  color: Colors.white, size: AppTheme.iconL),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
              ),
            ),
          ),
          if (widget.imageUrls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: PageViewIndicator(
                pageController: _pageController,
                itemCount: widget.imageUrls.length,
              ),
            ),
        ],
      ),
    );
  }
}

class PageViewIndicator extends StatelessWidget {
  final PageController pageController;
  final int itemCount;

  const PageViewIndicator({
    super.key,
    required this.pageController,
    required this.itemCount,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        final page = pageController.hasClients && pageController.page != null
            ? pageController.page!.round().clamp(0, itemCount - 1)
            : 0;
        return Text(
          '${page + 1} / $itemCount',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white,
            shadows: const [
              Shadow(
                  color: Colors.black54, offset: Offset(0, 1), blurRadius: 2),
            ],
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onHeaderTap;

  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
    this.onHeaderTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: AppTheme.elevation1,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onHeaderTap,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (trailing != null) ...[
                      const Spacer(),
                      trailing!,
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            child,
          ],
        ),
      ),
    );
  }
}

class _SalonLogo extends StatelessWidget {
  final String? logoUrl;

  const _SalonLogo({this.logoUrl});

  @override
  Widget build(BuildContext context) {
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return ClipOval(
        child: TimedCachedImage(
          imageUrl: logoUrl!,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.store_outlined,
          size: AppTheme.iconL, color: AppColors.textTertiary),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      color: AppColors.divider,
      indent: 0,
      endIndent: 0,
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final Service service;

  const _ServiceTile({required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingS),
      padding: const EdgeInsets.symmetric(
          vertical: AppTheme.spacingS, horizontal: AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  Formatters.formatDuration(service.durationMinutes),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                if (service.durationVariants.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(
                    [
                      if (service.durationVariants.court != null)
                        'Court ${Formatters.formatDuration(service.durationVariants.court!)}',
                      if (service.durationVariants.moyen != null)
                        'Moyen ${Formatters.formatDuration(service.durationVariants.moyen!)}',
                      if (service.durationVariants.long != null)
                        'Long ${Formatters.formatDuration(service.durationVariants.long!)}',
                    ].join(' · '),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacingS),
          Flexible(
            child: Text(
              Formatters.formatPriceRange(service.price, service.priceMax,
                  currency: context
                      .read<ProviderProvider>()
                      .selectedProvider
                      ?.currency),
              textAlign: TextAlign.end,
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
