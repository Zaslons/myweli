import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/external_link.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/helpers.dart';
import '../../models/appointment.dart';
import '../../models/availability.dart';
import '../../models/provider.dart' as models;
import '../../models/service.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/booking/compact_appointment_tile.dart';
import '../../widgets/common/app_rating.dart';
import '../../widgets/common/app_skeleton.dart';
import '../../widgets/common/app_snack_bar.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/salon_unavailable_view.dart';
import '../../widgets/common/section_heading.dart';
import '../../widgets/common/timed_cached_image.dart';
import '../../widgets/providers/before_after_section.dart';
import '../../widgets/providers/salon_location_preview.dart';
import '../../widgets/review/review_tile.dart';
import '../../widgets/review/submit_review_sheet.dart';

/// The salon page — `/provider/:id` in the consumer app and, with [preview],
/// « Aperçu de ma page » in the pro app.
///
/// Its header has two branches, chosen by whether the salon has a cover
/// (`imageUrls[0]`): see docs/design/salon-cover-photo.md. Its « Contact »
/// card opens on a map of the salon: docs/design/salon-location-map.md.
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

  /// This page's own copy of its salon — the last one it rendered from the
  /// shared slot (salon-location-map.md §2.7). Shown while another salon page
  /// holds the slot, and handed back to it by [_reclaimIfUncovered].
  models.Provider? _own;

  bool _reclaimScheduled = false;

  /// The salon this page shows — **its own, never another** (§2.7). The slot
  /// ([ProviderProvider.selectedProvider]) is one, shared by every salon page
  /// in the stack; the map's « Voir le salon » pushes a second one, whose read
  /// overwrites it, and this page used to render whatever it held.
  ///
  /// `null` = the loader, or — when the slot is this page's and its read is
  /// over ([_slotIsMine]) — the « salon indisponible » state.
  models.Provider? _salonOf(ProviderProvider providers) {
    final shared = providers.selectedProvider;
    if (widget.preview) return shared; // seeded, alone: nobody to share with
    if (shared != null && shared.id == widget.providerId) return _own = shared;
    // The slot is this page's — its read is out (the slot still holds the
    // previous salon) or it failed: never the copy, which would hide a
    // « no longer on MyWeli » behind a stale page.
    if (providers.selectedProviderId == widget.providerId) return null;
    // Another salon page has the slot.
    return _own;
  }

  /// Whether the slot's failure, if any, is this page's to show (§12).
  bool _slotIsMine(ProviderProvider providers) =>
      widget.preview || providers.selectedProviderId == widget.providerId;

  /// §2.7 — this page is the top route again (the map and the salon page it
  /// pushed are gone) and another salon page holds the slot: take it back,
  /// after this frame (notifying mid-build throws). With its copy,
  /// [ProviderProvider.restoreSalon] — no network, no loader: the page was
  /// already rendering that copy. Without one, a read.
  ///
  /// **Never while covered**: two salon pages taking the slot from each other
  /// would loop. Run by [_SlotKeeper] on every change of the slot or of
  /// whether this route is on top — not by the body, which would then rebuild
  /// whenever a sheet or a dialog opens over it.
  ///
  /// Frame 1 schedules one too (the slot is still the last page's), and it
  /// finds nothing to do: `initState`'s callback — registered before any
  /// build's — has already sent the first read, which claims the slot.
  void _reclaimIfUncovered(ProviderProvider providers, bool isCurrent) {
    if (widget.preview || !isCurrent || _reclaimScheduled) return;
    if (providers.selectedProviderId == widget.providerId) return;
    _reclaimScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reclaimScheduled = false;
      if (!mounted) return;
      final slot = context.read<ProviderProvider>();
      // Re-read: the first read, or a page above, may have settled it since.
      if (slot.selectedProviderId == widget.providerId) return;
      final own = _own;
      if (own != null) {
        slot.restoreSalon(own);
      } else {
        slot.loadProviderById(widget.providerId);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Frame 1 belongs to the loader, not the error state — the fetch below is
    // post-frame, so without this the first build renders « nothing loaded »
    // as a failure. Not for the preview, which is seeded and never fetches.
    if (!widget.preview) {
      context.read<ProviderProvider>().beginProviderLoad();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // **The owner preview does not fetch.** This line used to run before the
      // early-return below, so `preview` gated the RENDERING and never the
      // READ — the pro app asked the anonymous public route for the salon it
      // was already signed into, and would have 404'd its own draft the day
      // that route closes (T51; salon-state-and-refusals.md Decision C). The
      // pro-side `SalonPreviewScreen` fetches `GET /me/provider` and seeds the
      // notifier through `showPreloaded`, mirroring web's
      // `SalonPreviewClient` → `ProviderView` prop.
      if (widget.preview) return; // owner preview: seeded, no consumer session
      final provider = Provider.of<ProviderProvider>(context, listen: false);
      provider.loadProviderById(widget.providerId);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.user != null) {
        final favoritesProvider = Provider.of<FavoritesProvider>(
          context,
          listen: false,
        );
        favoritesProvider.loadFavorites(authProvider.user!.id);
        final appointmentProvider = Provider.of<AppointmentProvider>(
          context,
          listen: false,
        );
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
          '${dayNames[day]}: ${Formatters.formatTimeShort(first)}-${Formatters.formatTimeShort(last)}',
        );
      }
    }
    return lines;
  }

  /// « Signaler » (FR-REV-005, parity 2.14): optional reason → POST report.
  Future<void> _reportReview(String reviewId) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.isAuthenticated) {
      AppSnackBar.show(context, 'Connectez-vous pour signaler un avis.');
      return;
    }
    // The reason is optional, so `null` (cancel) is the only stop signal —
    // and the dialog owns its controller, which this one used to leak.
    final reason = await showInputDialog(
      context,
      title: 'Signaler cet avis ?',
      confirmLabel: 'Signaler',
      field: const ConfirmField(
        hint: 'Raison (optionnel)',
        isRequired: false,
        maxLength: 500,
      ),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await Provider.of<ProviderProvider>(
      context,
      listen: false,
    ).reportReview(reviewId, reason: reason);
    AppSnackBar.outcomeOn(
      messenger,
      ok: ok,
      success: 'Merci. Notre équipe va examiner cet avis.',
      error: 'Le signalement a échoué. Réessayez.',
    );
  }

  /// « Voir sur la carte » — the location preview and the address row
  /// (docs/design/salon-location-map.md §2.2).
  ///
  /// The consumer app opens its own map on this salon, its sheet up. The pro
  /// « Aperçu » has no map: `ProRouter` registers no `/carte`, so pushing it
  /// there is « Page Not Found » — it opens the map-app picker the
  /// « Itinéraire » icon opens. `/favorites`, this link's target until
  /// 2026-10-12, had been renamed `/carte` on 2026-08-22 (#491) and was dead
  /// in both apps; `route_literals_test.dart` now reads every push target.
  void _openOnMap(models.Provider p) {
    final lat = p.latitude;
    final lng = p.longitude;
    if (lat == null || lng == null) return;
    if (widget.preview) {
      Helpers.launchNavigation(
        latitude: lat,
        longitude: lng,
        label: p.name,
        context: context,
      );
      return;
    }
    context.push('/carte?providerId=${p.id}');
  }

  /// The cover photo, or null when the salon has none — `imageUrls[0]`, which
  /// the contract already names the listing cover (openapi.yaml, `imageUrls`).
  ///
  /// An empty string is « no cover », as it is on the website, where
  /// `provider.imageUrls?.[0]` is falsy and the Hero renders nothing.
  String? _coverUrl(models.Provider p) =>
      p.imageUrls.isNotEmpty && p.imageUrls.first.isNotEmpty
      ? p.imageUrls.first
      : null;

  /// The indices of `imageUrls` the « Photos » strip shows: all of them, minus
  /// the cover when there is one (it is already at the top of the page).
  List<int> _galleryIndices(models.Provider p) => [
    for (var i = _coverUrl(p) == null ? 0 : 1; i < p.imageUrls.length; i++) i,
  ];

  /// The favourite heart — the bar's only action, on both header branches.
  Widget _favoriteAction() => Consumer2<FavoritesProvider, AuthProvider>(
    builder: (context, favoritesProvider, authProvider, _) {
      final isFavorite = authProvider.isAuthenticated
          ? favoritesProvider.isFavorite(widget.providerId)
          : false;
      final userId = authProvider.user?.id ?? '';

      return IconButton(
        tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          // `textPrimary` when off. It was `secondary` — #FFFFFF on the white
          // header — so the heart was invisible until it turned red
          // (salon-cover-photo.md §1). Same pair as provider_card.dart.
          color: isFavorite ? AppColors.favorite : AppColors.textPrimary,
        ),
        onPressed: () async {
          if (!authProvider.isAuthenticated) {
            AppSnackBar.show(
              context,
              'Connectez-vous pour ajouter aux favoris',
            );
            final currentPath = GoRouterState.of(context).uri.toString();
            context.go('/login?returnTo=${Uri.encodeComponent(currentPath)}');
            return;
          }
          final messenger = ScaffoldMessenger.of(context);
          // The toggle can fail. Announcing success either way is a lie, and
          // « Annuler » on a failed toggle would PERFORM the action instead of
          // undoing it.
          final ok = await favoritesProvider.toggleFavorite(
            userId,
            widget.providerId,
          );
          AppSnackBar.outcomeOn(
            messenger,
            ok: ok,
            success: isFavorite ? 'Retiré des favoris' : 'Ajouté aux favoris',
            error:
                favoritesProvider.error ??
                'Une erreur est survenue. Réessayez.',
            action: !ok
                ? null
                : SnackAction(
                    label: 'Annuler',
                    onPressed: () => favoritesProvider.toggleFavorite(
                      userId,
                      widget.providerId,
                    ),
                    // §15 as amended by A6: the heart itself is a one-tap
                    // undo, so this keeps the kind's 3s instead of occluding
                    // the screen for 10.
                    isOnlyRouteBack: false,
                  ),
          );
        },
      );
    },
  );

  /// Branch A — the salon has a cover (salon-cover-photo.md §2.1).
  ///
  /// The bar's height is the photo's, a constant: only text scales, and the
  /// name, place and rating live in the sliver below at their intrinsic
  /// height. So this branch has no computed bound and no A13 stacking — the
  /// name no longer shares its row with a logo.
  Widget _coverAppBar(models.Provider p, String cover) => IconButtonTheme(
    // « Retour » and the heart on white pills over the photo — the idiom of
    // provider_card.dart. A THEME and not a `leading:`, so the AppBar still
    // decides whether there is a way back (`impliesAppBarDismissal`): it
    // re-reads this theme for its implied BackButton and for its actions, and
    // its `style?.copyWith(...)` keeps the background (app_bar.dart). M3's
    // IconButton paints a 40dp disc inside a 48dp target (§13.2).
    data: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: AppColors.secondary.withValues(alpha: 0.9),
        foregroundColor: AppColors.textPrimary,
      ),
    ),
    child: SliverAppBar(
      expandedHeight: _coverHeight,
      pinned: true,
      actions: [if (!widget.preview) _favoriteAction()],
      flexibleSpace: _SalonCover(
        imageUrl: cover,
        salonName: p.name,
        logoUrl: p.logoUrl,
        // The cover IS photo 1: the viewer opens on it, over the full list.
        onTap: () => _showFullScreenPhoto(context, p.imageUrls, 0),
      ),
    ),
  );

  /// Branch B — the salon has no photo: the header exactly as it was before
  /// the cover (salon-cover-photo.md §2.2), logo beside the name, A13 stacking
  /// and all.
  Widget _noPhotoAppBar(BuildContext context, models.Provider p) {
    final stacked = _headerStacked(context, verified: p.verified);
    return SliverAppBar(
      // §13.3 (A11 C5). `expandedHeight: 160` was a fixed height around text
      // and the header clipped by **92dp at 200%** — the same class as
      // `ProviderCard.carouselHeight`, and the same fix.
      //
      // The split is derived, not guessed: the overflow is 92dp at 360, 375
      // and 390 alike, so the block does not re-wrap and its growth is linear.
      // `chrome + text = 160` at 1× and `chrome + 2×text = 252` at 2× gives
      // text = 92, chrome = 68. `textScaledBound` floors at the 1× value, so
      // nothing moves below 100%.
      expandedHeight: AppTheme.textScaledBound(
        context,
        constant: stacked ? _headerChromeStacked : _headerChrome,
        text: _headerTextBlock,
      ),
      pinned: true,
      actions: [if (!widget.preview) _favoriteAction()],
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
              // A13, §21 row 62 — **the salon's name is its identity, and
              // « Salon Ex / cellence » is not a name.** §13.3 used to name "a
              // salon name" as a permitted mid-word break; A13 decides
              // otherwise and amends it.
              //
              // Beside a hard 72×72 logo the name gets 224dp at 360 while
              // « Excellence » wants 269.7 at 2×. Shrinking the logo cannot
              // reach the contract point — measured at 56/48/40dp it still
              // breaks, and **deleting it outright only just clears 2×** — so
              // the fix is the one §13.3 mandates and this file already uses
              // for « Appeler » further down: more width, by stacking. (The
              // cover branch needs none of this: its name has the full row.)
              child: Flex(
                direction: stacked ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SalonLogo(logoUrl: p.logoUrl),
                  SizedBox(
                    width: stacked ? 0 : AppTheme.spacingM,
                    height: stacked ? AppTheme.spacingS : 0,
                  ),
                  // Stacked, the Flex is vertical and an `Expanded` would
                  // fight the `SliverAppBar`'s bounded height; beside the logo
                  // it is what gives the name the rest of the row. So the
                  // wrapper differs by axis.
                  _HeaderTextBlock(
                    stacked: stacked,
                    // Two lines: this bar's height is a computed bound with
                    // zero slack at 2× (see `_headerChromeStacked`).
                    child: _SalonIdentity(salon: p, nameMaxLines: 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<ProviderProvider>(
        builder: (context, provider, _) {
          // This page's salon, never the slot's other one (§2.7). Nothing to
          // show: its read is out, or another page has the slot and this one
          // has no copy yet — the loader; its own read failed — §12.
          final p = _salonOf(provider);
          if (p == null && (provider.isLoading || !_slotIsMine(provider))) {
            // No AppBar on this branch: the page's header is a sliver.
            return const SafeArea(child: SkeletonDetail(block: true));
          }
          if (p == null) {
            // §12, shared with the booking hub and the confirmation screen.
            // « Retour » used to live here and is gone deliberately: this
            // branch renders no AppBar, and `context.pop()` on a screen
            // reached by a deep link or a `context.go` pops to nothing. The
            // way out now leads somewhere.
            return SalonUnavailableView(
              errorCode: provider.errorCode,
              message: provider.error,
              onRetry: () => provider.loadProviderById(widget.providerId),
            );
          }

          final gallery = _galleryIndices(p);
          return CustomScrollView(
            slivers: [
              // Two headers, chosen by whether the salon has a cover
              // (docs/design/salon-cover-photo.md §2): `imageUrls[0]` full-bleed
              // like the website's Hero, or — no photo at all — the header as
              // it always was.
              if (_coverUrl(p) case final cover?) ...[
                _coverAppBar(p, cover),
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: AppColors.secondary,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacingL,
                        AppTheme.spacingM,
                        AppTheme.spacingL,
                        AppTheme.spacingM,
                      ),
                      // Intrinsic height, full padded width (312dp at 360):
                      // nothing bounds the name, so nothing truncates it.
                      child: _SalonIdentity(salon: p),
                    ),
                  ),
                ),
              ] else
                _noPhotoAppBar(context, p),
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
                      // Section: Vos rendez-vous ici — rendered ONLY for a
                      // signed-in client with visits at this salon, the web's
                      // `SalonVisitsCard` rule (parity 2.7). It used to show a
                      // sign-in prompt to everyone, and the owner « Aperçu »
                      // copied it (docs/design/salon-rating-new-and-visits-card.md
                      // §2.3). No spinner: an optional card waits for its data.
                      if (!widget.preview)
                        Consumer2<AuthProvider, AppointmentProvider>(
                          builder: (context, authProvider, appointmentProvider, _) {
                            if (!authProvider.isAuthenticated) {
                              return const SizedBox.shrink();
                            }
                            final atThisSalon =
                                appointmentProvider.appointments
                                    .where(
                                      (a) => a.providerId == widget.providerId,
                                    )
                                    .toList()
                                  ..sort(
                                    (a, b) => b.appointmentDate.compareTo(
                                      a.appointmentDate,
                                    ),
                                  );
                            if (atThisSalon.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final top = atThisSalon.take(5).toList();
                            // At most 5 tiles — nothing to virtualise. The
                            // bound was the constant 100, and the tile with
                            // a hint measures 120 at 1× and 216 at 200%: it
                            // was clipping ALREADY, at the default scale.
                            // Growth is super-linear (the title wraps), so
                            // no computed bound is safe — an intrinsic strip
                            // needs none (§13.3).
                            return _SectionCard(
                              title: 'Vos rendez-vous ici',
                              trailing: TextButton(
                                onPressed: () => context.push('/bookings'),
                                child: const Text('Voir tout'),
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final (i, a) in top.indexed) ...[
                                        if (i > 0)
                                          const SizedBox(
                                            width: AppTheme.spacingS,
                                          ),
                                        Builder(
                                          builder: (context) {
                                            final w = MediaQuery.of(
                                              context,
                                            ).size.width;
                                            final cardWidth = (w * 0.75).clamp(
                                              260.0,
                                              340.0,
                                            );
                                            final isPast =
                                                a.status ==
                                                    AppointmentStatus
                                                        .completed ||
                                                a.status ==
                                                    AppointmentStatus
                                                        .cancelled ||
                                                a.appointmentDate.isBefore(
                                                  AppClock.now(),
                                                );
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
                                                        if (a
                                                            .serviceIds
                                                            .isNotEmpty)
                                                          'serviceIds': a
                                                              .serviceIds
                                                              .join(','),
                                                        if (a.artistId != null)
                                                          'artistId':
                                                              a.artistId!,
                                                      },
                                                    );
                                                    context.push(
                                                      uri.toString(),
                                                    );
                                                  } else {
                                                    context.push(
                                                      '/appointment/${a.id}',
                                                    );
                                                  }
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
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
                            () => _servicesExpanded = !_servicesExpanded,
                          );
                        },
                        child: AnimatedCrossFade(
                          duration: AppMotion.base,
                          crossFadeState: _servicesExpanded
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          firstChild: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (p.services.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppTheme.spacingM,
                                  ),
                                  child: Text(
                                    'Aucun service pour le moment.',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                )
                              else
                                ...p.services.map(
                                  (service) => _ServiceTile(
                                    service: service,
                                    currency: p.currency,
                                  ),
                                ),
                            ],
                          ),
                          secondChild: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppTheme.spacingS,
                            ),
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
                            // Where it is — the website's « Localisation »,
                            // only when there is a where to show
                            // (docs/design/salon-location-map.md §2.1).
                            if (p.latitude != null && p.longitude != null) ...[
                              SalonLocationPreview(
                                salonName: p.name,
                                category: p.category,
                                latitude: p.latitude!,
                                longitude: p.longitude!,
                                onOpen: () => _openOnMap(p),
                              ),
                              const SizedBox(height: AppTheme.spacingSM),
                            ],
                            // The address. A way onto the map only when the
                            // salon has coordinates — without them it is just
                            // the address, not a link to an error message.
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: 48,
                              ), // §13.2 touch target
                              child: InkWell(
                                onTap: p.latitude != null && p.longitude != null
                                    ? () => _openOnMap(p)
                                    : null,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusLarge,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppTheme.spacingS,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.map_outlined,
                                        size: AppTheme.iconS,
                                        color: AppColors.textTertiary,
                                      ),
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
                                                    color:
                                                        AppColors.textPrimary,
                                                  ),
                                            ),
                                            if (p.latitude != null &&
                                                p.longitude != null)
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
                                          tooltip: 'Itinéraire',
                                          icon: const Icon(
                                            Icons.directions,
                                            color: AppColors.primary,
                                          ),
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
                            ),
                            const _Divider(),
                            // Phone
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: 48,
                              ), // §13.2 touch target
                              child: InkWell(
                                onTap: () => callPhone(context, p.phoneNumber),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusLarge,
                                ),
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppTheme.spacingS,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.phone_outlined,
                                        size: AppTheme.iconS,
                                        color: AppColors.textTertiary,
                                      ),
                                      const SizedBox(width: AppTheme.spacingSM),
                                      Expanded(
                                        child: Text(
                                          Formatters.formatPhoneNumber(
                                            p.phoneNumber,
                                          ),
                                          style: AppTextStyles.bodyMedium
                                              .copyWith(
                                                color: AppColors.textPrimary,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (p.whatsapp != null &&
                                p.whatsapp!.isNotEmpty) ...[
                              const _Divider(),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ), // §13.2 touch target
                                child: InkWell(
                                  onTap: () async {
                                    final digits = p.whatsapp!.replaceAll(
                                      RegExp(r'[^0-9]'),
                                      '',
                                    );
                                    final uri = Uri.parse(
                                      'https://wa.me/$digits',
                                    );
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusLarge,
                                  ),
                                  child: Container(
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: AppTheme.spacingS,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.chat_outlined,
                                          size: AppTheme.iconS,
                                          color: AppColors.textTertiary,
                                        ),
                                        const SizedBox(
                                          width: AppTheme.spacingSM,
                                        ),
                                        Expanded(
                                          child: Text(
                                            'WhatsApp',
                                            style: AppTextStyles.bodyMedium
                                                .copyWith(
                                                  color: AppColors.textPrimary,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            // Working hours
                            const _Divider(),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppTheme.spacingXS,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.schedule_outlined,
                                    size: AppTheme.iconS,
                                    color: AppColors.textTertiary,
                                  ),
                                  const SizedBox(width: AppTheme.spacingSM),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children:
                                          _formatWorkingHours(p.availability)
                                              .map(
                                                (line) => Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom:
                                                            AppTheme.spacingXS,
                                                      ),
                                                  child: Text(
                                                    line,
                                                    style: AppTextStyles
                                                        .bodySmall
                                                        .copyWith(
                                                          color: AppColors
                                                              .textSecondary,
                                                        ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Section: Photos — every photo EXCEPT the cover, which
                      // is already on screen (the website's
                      // `Gallery images={imageUrls.slice(1)}`). Gone when the
                      // cover is the only photo: « Aucune photo pour le
                      // moment. » would be false, and « no other photo » is
                      // noise. Without any photo it says so, as it always did.
                      if (gallery.isNotEmpty || p.imageUrls.isEmpty)
                        _SectionCard(
                          title: 'Photos',
                          child: p.imageUrls.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppTheme.spacingS,
                                  ),
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
                                    itemCount: gallery.length,
                                    separatorBuilder: (_, _) => const SizedBox(
                                      width: AppTheme.spacingS,
                                    ),
                                    itemBuilder: (context, k) {
                                      // The TRUE index into `imageUrls`, so
                                      // the viewer opens on this photo and a
                                      // swipe back reaches the cover.
                                      final i = gallery[k];
                                      return Semantics(
                                        button: true,
                                        label:
                                            'Agrandir la photo ${i + 1} '
                                            'sur ${p.imageUrls.length}',
                                        child: GestureDetector(
                                          onTap: () => _showFullScreenPhoto(
                                            context,
                                            p.imageUrls,
                                            i,
                                          ),
                                          child: SizedBox(
                                            width: 160,
                                            height: 120,
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppTheme.radiusLarge,
                                                  ),
                                              child: TimedCachedImage(
                                                imageUrl: p.imageUrls[i],
                                                width: 160,
                                                height: 120,
                                                fit: BoxFit.cover,
                                              ),
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
                            AppRating(
                              rating: p.rating,
                              reviewCount: p.reviewCount,
                              size: AppRatingSize.large,
                            ),
                            // §2.2: at 0 reviews the pill alone says « new »;
                            // this line says what the section would hold.
                            // Both conditions: a review just submitted is in
                            // `reviews` before any reload (provider_provider's
                            // `addReviewLocally`). ExcludeSemantics: the pill's
                            // label already says « pas encore d’avis ».
                            if (p.reviewCount == 0 && p.reviews.isEmpty) ...[
                              const SizedBox(height: AppTheme.spacingS),
                              ExcludeSemantics(
                                child: Text(
                                  'Pas encore d’avis.',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                            if (p.reviews.isNotEmpty) ...[
                              const SizedBox(height: AppTheme.spacingM),
                              ...p.reviews
                                  .take(5)
                                  .map(
                                    (review) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppTheme.spacingS,
                                      ),
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
                                builder:
                                    (
                                      context,
                                      authProvider,
                                      appointmentProvider,
                                      _,
                                    ) {
                                      final isAuthenticated =
                                          authProvider.isAuthenticated &&
                                          authProvider.user != null;
                                      final reviewable = isAuthenticated
                                          ? appointmentProvider
                                                .latestCompletedAppointment(
                                                  widget.providerId,
                                                  authProvider.user!.id,
                                                )
                                          : null;
                                      if (reviewable == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          top: AppTheme.spacingM,
                                        ),
                                        child: InkWell(
                                          onTap: () {
                                            showModalBottomSheet(
                                              context: context,
                                              isScrollControlled: true,
                                              builder: (ctx) => Padding(
                                                padding: EdgeInsets.only(
                                                  bottom: MediaQuery.of(
                                                    ctx,
                                                  ).viewInsets.bottom,
                                                ),
                                                child: SubmitReviewSheet(
                                                  providerId: widget.providerId,
                                                  appointmentId: reviewable.id,
                                                  artistName:
                                                      reviewable.artistName,
                                                ),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(
                                            AppTheme.radiusLarge,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: AppTheme.spacingM,
                                              horizontal: AppTheme.spacingS,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.surface,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppTheme.radiusLarge,
                                                  ),
                                              border: Border.all(
                                                color: AppColors.border,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.star_border,
                                                  size: AppTheme.iconL,
                                                  color: AppColors.textTertiary,
                                                ),
                                                const SizedBox(
                                                  width: AppTheme.spacingSM,
                                                ),
                                                Text(
                                                  'Donner mon avis',
                                                  style: AppTextStyles
                                                      .titleSmall
                                                      .copyWith(
                                                        color: AppColors
                                                            .textPrimary,
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
                            // §4 (SYSTEM §21 row 27): the salon description is
                            // reading prose — bodyLarge, "Default reading text",
                            // not the 14px workhorse.
                            style: AppTextStyles.bodyLarge.copyWith(
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
          // The same salon as the body — « Réserver » under page A booked
          // salon B when the slot held B (§2.7).
          final p = _salonOf(provider);
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
                            icon: const Icon(
                              Icons.calendar_today,
                              size: AppTheme.iconS,
                            ),
                            label: const Text(
                              'Réserver (après la mise en ligne)',
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppTheme.spacingM,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Builder(
                      builder: (context) {
                        final call = OutlinedButton.icon(
                          onPressed: () => callPhone(context, p.phoneNumber),
                          icon: const Icon(
                            Icons.phone_outlined,
                            size: AppTheme.iconS,
                          ),
                          label: const Text('Appeler'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(
                              color: AppColors.borderStrong,
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: AppTheme.spacingM,
                            ),
                          ),
                        );
                        final book = ElevatedButton.icon(
                          onPressed: () =>
                              context.push('/booking?providerId=${p.id}'),
                          icon: const Icon(
                            Icons.calendar_today,
                            size: AppTheme.iconS,
                          ),
                          label: const Text('Réserver'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.secondary,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppTheme.spacingM,
                            ),
                          ),
                        );

                        // §13.3 (A11 C8): **a control's label may not break inside
                        // a word.** « Appeler » is one token, and a 1:2 split of a
                        // 328dp bar leaves it ~81dp while at 200% it wants ~105 —
                        // so Flutter broke the word and the button read
                        // « Appel » / « er ». A one-word label cannot wrap its way
                        // out of that; the only honest fix is more width, so above
                        // the threshold the bar stacks instead of splitting.
                        //
                        // The threshold is measured, not chosen: the break starts
                        // between 1.3× and 1.5×. Same shape as
                        // `ProviderCard._textBlockHeight` — a measured constant is
                        // fine when a gate holds it, and `layout_test`'s
                        // no-mid-word-break assertion is that gate.
                        //
                        // It is a TEXT-SCALE branch, not a width breakpoint (§10
                        // still has none): what changed is how much room a word
                        // needs, not how much room the screen has.
                        if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(width: double.infinity, child: book),
                              const SizedBox(height: AppTheme.spacingS),
                              SizedBox(width: double.infinity, child: call),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: call),
                            const SizedBox(width: AppTheme.spacingSM),
                            Expanded(flex: 2, child: book),
                          ],
                        );
                      },
                    ),
            ),
          );
        },
      ),
    );
    // The preview is one seeded page with nobody to share the slot with.
    return widget.preview
        ? page
        : _SlotKeeper(onChange: _reclaimIfUncovered, child: page);
  }
}

/// Watches what [_ProviderDetailScreenState._reclaimIfUncovered] needs — the
/// shared salon slot, and whether this route is on top — and nothing else: a
/// sheet or a dialog opening over the page rebuilds this, never [child], the
/// same instance between two builds of the page (salon-location-map.md §2.7).
class _SlotKeeper extends StatelessWidget {
  final void Function(ProviderProvider providers, bool isCurrent) onChange;
  final Widget child;

  const _SlotKeeper({required this.onChange, required this.child});

  @override
  Widget build(BuildContext context) {
    onChange(
      context.watch<ProviderProvider>(),
      ModalRoute.isCurrentOf(context) ?? true,
    );
    return child;
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
    // Light status-bar icons over the scrim — one of the three full-bleed
    // dark surfaces where the app-wide dark-icons default would render
    // time/battery invisible (see Info.plist, 2026-08-27).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Dialog(
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
                      // `contain`, EXPLICITLY — the widget's own default is
                      // `cover`, which at viewport size CROPS every photo whose
                      // aspect differs from the screen's: the owner opened a
                      // landscape shot on a portrait phone and saw a zoomed
                      // slice. This was the sole `cover` among the app's six
                      // lightboxes; review_tile.dart was already the model.
                      // The width/height pair is gone with it — it was the
                      // residue of the ContentWidthCap mis-size bug
                      // (content_width_cap.dart), and `contain` inside a
                      // full-screen Center needs no explicit size at any width.
                      child: TimedCachedImage(
                        imageUrl: widget.imageUrls[index],
                        fit: BoxFit.contain,
                        semanticLabel:
                            'Photo du salon '
                            '${index + 1} sur ${widget.imageUrls.length}',
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
                tooltip: 'Fermer',
                onPressed: widget.onClose,
                icon: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: AppTheme.iconL,
                ),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
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
                color: Colors.black54,
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The NO-PHOTO header's non-text chrome (logo, paddings) and its text block,
/// at 1×. Derived from the measured 92dp overflow at 200% — see
/// `_noPhotoAppBar`'s `expandedHeight`.
///
/// **Everything from here to `_headerStacked` governs that branch only**
/// (salon-cover-photo.md §2.2). Under a cover the name is not beside the logo:
/// it has the full padded row — 312dp at 360, 284 with the verified badge —
/// so « Excellence » (134.85dp at 1×) holds to 2.31× / 2.11×, past the 2×
/// contract, and that branch has no stacking and no computed bound.
const double _headerChrome = 68;
const double _headerTextBlock = 92;

/// Above this text scale the no-photo header **stacks** the logo above the
/// name (A13, §21 row 62).
///
/// **1.6, not the 1.3 this file already uses twelve hundred lines down.** The
/// action bar's threshold is 1.3 because « Appeler » crosses there; the salon
/// NAME crosses at **1.66× / 1.77× / 1.88×** on §10's three widths — the box is
/// `W − 24 − 72 (logo) − 16 − 24`, so 224dp at 360, and « Excellence » wants
/// 269.7 at 2×. The crossing therefore moves with the screen, which is the
/// situation `ProviderCard.minGridCellWidth` says makes a scale constant wrong.
///
/// We take the **worst case** rather than computing a width-dependent branch,
/// and the trade is stated instead of hidden: a 390dp phone stacks about 0.2×
/// earlier than it strictly must. That is one layout, slightly early, on the
/// widest supported phone — against a second bespoke width rule on a header
/// with one call site.
const double _headerStacksAbove = 1.6;

/// …and the threshold for a **verified** salon, which is lower (A13, found by
/// the adversarial review).
///
/// The verified badge is a SIBLING of the name's `Flexible` in the same `Row`,
/// and a `RenderFlex` lays its non-flex children out first — so `spacingS` (8)
/// plus `iconS` (20) come off the name's box before it gets anything.
/// **196dp at 360, not 224.** « Excellence » is 134.85dp at 1× (`letterSpacing`
/// is 0 on `headlineMedium`, so the width scales exactly linearly), which puts
/// the crossing at **1.453× / 1.565× / 1.676×** on §10's three widths.
///
/// 1.6 would therefore have left « Salon Ex / cellence » live from 1.45× to
/// 1.60× on a 360dp phone — the exact string row 62 exists to kill, on the
/// salons the marketplace most wants to promote. The first version of this
/// constant took the worst case of the wrong population.
const double _headerStacksAboveVerified = 1.45;

/// The stacked header's chrome — the logo and its gap move from *beside* the
/// text to *above* it, so they stop sharing the text's rows.
///
/// **Re-measured, not assumed, because there was no room to guess with.** At 2×
/// the un-stacked header's content is 144 (two name lines) + 8 + 32 + 4 + 32 +
/// 32 of padding = **252**, and `textScaledBound(68, 92)` at 2× is **252 exactly
/// — zero slack**. Adding the 72dp logo and its 8dp gap to a header with no
/// margin is what turns a mid-word break into a `RenderFlex` overflow, which is
/// why `maxLines: 3` was rejected outright.
const double _headerChromeStacked = _headerChrome + 72 + AppTheme.spacingS;

/// The header's text column, wrapped for whichever axis the [Flex] is on.
///
/// A `Flexible`/`Expanded` is legal in either direction, but it means different
/// things: horizontally it hands the name the rest of the row (which is the
/// point); vertically it would make the column fight the `SliverAppBar`'s
/// bounded height, and the header has **zero slack at 2×**. Stacked, the block
/// simply takes the full padded width — 312dp at 360 — which is what clears
/// « Excellence » to 2.31×.
class _HeaderTextBlock extends StatelessWidget {
  const _HeaderTextBlock({required this.stacked, required this.child});

  final bool stacked;
  final Widget child;

  @override
  Widget build(BuildContext context) => stacked
      ? SizedBox(width: double.infinity, child: child)
      : Expanded(child: child);
}

/// Whether the header stacks at the current OS text scale.
///
/// [verified] is not a detail: the badge costs the name 28dp, which moves the
/// crossing down by ~0.2×.
bool _headerStacked(BuildContext context, {required bool verified}) =>
    MediaQuery.textScalerOf(context).scale(1) >
    (verified ? _headerStacksAboveVerified : _headerStacksAbove);

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
            // A11 C5: this was the third copy of the heading row, and the one
            // outside every gate — `Spacer` instead of `spaceBetween`, and no
            // `Expanded` on the title, so « Vos rendez-vous ici » + « Voir tout »
            // overflowed by 112–142dp at 200% text and nothing measured it.
            SectionHeading(
              title: title,
              style: AppTextStyles.titleMedium,
              action: trailing,
              onTap: onHeaderTap,
            ),
            const SizedBox(height: AppTheme.spacingS),
            child,
          ],
        ),
      ),
    );
  }
}

/// The cover's height below the status bar — the website's `h-56` on phones
/// (`web/components/provider/Hero.tsx`).
///
/// Constant chrome: only text scales, and a photo is not text. A named
/// constant at the call site and not an `AppTheme` token, by SYSTEM.md §5
/// « What §5 does not govern »: there is no sizing scale, and an image's
/// height is a layout dimension like `ProviderCard._imageHeight`.
const double _coverHeight = 224;

/// The logo on the cover — the website's `h-16 w-16` circle and its
/// `border-2` white ring, bottom-left at `spacingM` (`bottom-m left-m`).
const double _coverLogoSize = 64;
const double _coverLogoRing = 2;

/// How much of the cover is showing, 1 → 0, from the bar's scroll position.
///
/// Fully opaque for the first half of the collapse, then a linear fade into
/// the bar. **One number drives both the fade and the status bar** (light
/// icons while this is ≥ 0.5), so the two cannot disagree.
double _coverVisibility(FlexibleSpaceBarSettings? settings) {
  if (settings == null) return 1;
  final range = settings.maxExtent - settings.minExtent;
  if (range <= 0) return 1;
  final collapsed = ((settings.maxExtent - settings.currentExtent) / range)
      .clamp(0.0, 1.0);
  return collapsed <= 0.5 ? 1 : (2 - 2 * collapsed).clamp(0.0, 1.0);
}

/// The cover — `imageUrls[0]` full-bleed under the status bar and the
/// toolbar, with the logo bottom-left (salon-cover-photo.md §2.1). It is the
/// `SliverAppBar`'s flexible space, so it reads the bar's extent from the
/// `FlexibleSpaceBarSettings` the bar provides.
///
/// **A failed photo keeps the band** (§2.4): `TimedCachedImage` paints its
/// neutral « image unavailable » surface in the same 224dp. Falling back to
/// the no-photo header instead would need a failure signal the widget does
/// not expose, and would move the page under the reader's thumb after the
/// fact.
class _SalonCover extends StatelessWidget {
  const _SalonCover({
    required this.imageUrl,
    required this.salonName,
    required this.logoUrl,
    required this.onTap,
  });

  final String imageUrl;
  final String salonName;
  final String? logoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final visibility = _coverVisibility(settings);
    final topInset = MediaQuery.paddingOf(context).top;
    // The photo keeps its full height and is anchored to the bar's bottom, so
    // it scrolls with the content (no parallax) and the bar clips its top.
    final photoHeight = settings?.maxExtent ?? topInset + _coverHeight;
    final logo = logoUrl;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light icons over the photo, the app's dark ones once it has faded.
      // Nested inside the AppBar's own region, and the deepest region wins:
      // `AnnotatedRegionLayer.findAnnotations` asks its children first.
      value: visibility >= 0.5
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: IgnorePointer(
        // Faded out, the cover is not there — a tap on the collapsed bar must
        // not open a photo nobody can see.
        ignoring: visibility == 0,
        child: Opacity(
          opacity: visibility,
          child: Semantics(
            container: true,
            button: true,
            label: 'Photo du salon $salonName',
            hint: 'Agrandir la photo',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: photoHeight,
                    // Decorative to the reader: the Semantics above names it.
                    child: TimedCachedImage(
                      imageUrl: imageUrl,
                      width: double.infinity,
                      height: photoHeight,
                    ),
                  ),
                  // The status bar and the toolbar sit on the photo; this is
                  // what keeps light icons legible on a white wall. §19's
                  // story scrim, same strength (`story_viewer.dart`, 0x99).
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: topInset + kToolbarHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (logo != null && logo.isNotEmpty)
                    Positioned(
                      left: AppTheme.spacingM,
                      bottom: AppTheme.spacingM,
                      child: _CoverLogo(logoUrl: logo),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The salon's logo on its cover, ringed in white so it reads on any photo.
///
/// Absent when the salon has no logo, as on the website — a generic « shop »
/// disc on a photo identifies nothing. Decorative: the name follows at once.
class _CoverLogo extends StatelessWidget {
  const _CoverLogo({required this.logoUrl});

  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    const inner = _coverLogoSize - 2 * _coverLogoRing;
    return Container(
      width: _coverLogoSize,
      height: _coverLogoSize,
      decoration: BoxDecoration(
        color: AppColors.secondary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.secondary, width: _coverLogoRing),
        boxShadow: AppTheme.elevation3,
      ),
      child: ClipOval(
        child: TimedCachedImage(imageUrl: logoUrl, width: inner, height: inner),
      ),
    );
  }
}

/// The salon's name (+ verified badge), place and rating — shared by both
/// header branches (salon-cover-photo.md §5).
///
/// [nameMaxLines] is the no-photo header's: its bar height is a computed bound
/// with zero slack at 2×, so the name stops at two lines there. Under the
/// cover the block sits in an ordinary sliver at its intrinsic height; nothing
/// bounds the name, so nothing truncates it (§13.3).
class _SalonIdentity extends StatelessWidget {
  const _SalonIdentity({required this.salon, this.nameMaxLines});

  final models.Provider salon;
  final int? nameMaxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                salon.name,
                style: AppTextStyles.headlineMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                maxLines: nameMaxLines,
                overflow: nameMaxLines == null ? null : TextOverflow.ellipsis,
              ),
            ),
            if (salon.verified) ...[
              const SizedBox(width: AppTheme.spacingS),
              const Padding(
                padding: EdgeInsets.only(top: AppTheme.spacingXS),
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
            const Icon(
              Icons.location_on_outlined,
              size: AppTheme.iconXS,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: AppTheme.spacingXS),
            Expanded(
              child: Text(
                salon.city ?? salon.address,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingXS),
        // « Nouveau » at 0 reviews, never « ★ 0.0 · 0 avis »
        // (docs/design/salon-rating-new-and-visits-card.md §2.1).
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppRating(
            rating: salon.rating,
            reviewCount: salon.reviewCount,
          ),
        ),
      ],
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
      child: const Icon(
        Icons.store_outlined,
        size: AppTheme.iconL,
        color: AppColors.textTertiary,
      ),
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

  /// The page's salon's — handed down, not read off the shared slot, which
  /// may hold another salon (salon-location-map.md §2.7).
  final String? currency;

  const _ServiceTile({required this.service, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingS),
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.spacingS,
        horizontal: AppTheme.spacingM,
      ),
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
              Formatters.formatPriceRange(
                service.price,
                service.priceMax,
                currency: currency,
              ),
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
