import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/appointment.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/booking/compact_appointment_tile.dart';
import '../../widgets/common/commune_picker_sheet.dart';
import '../../widgets/common/commune_pill.dart';
import '../../widgets/home/announcement_stories.dart';
import '../../widgets/home/category_chips.dart';
import '../../widgets/home/search_bar.dart';
import '../../widgets/provider/provider_card.dart';

extension _FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ProviderProvider>(context, listen: false);
      provider.loadFeaturedProviders();
      provider.restoreSelectedCommune().whenComplete(provider.loadProviders);

      // Load favorites if user is authenticated
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.user != null) {
        final favoritesProvider =
            Provider.of<FavoritesProvider>(context, listen: false);
        favoritesProvider.loadFavorites(authProvider.user!.id);

        // Load appointments for “Derniers rendez-vous”
        final appointmentProvider =
            Provider.of<AppointmentProvider>(context, listen: false);
        appointmentProvider.loadAppointments();
      }
    });
  }

  Future<void> _openCommunePicker(ProviderProvider provider) async {
    final choice = await showCommunePicker(
      context,
      selected: provider.selectedCommune,
    );
    if (choice == null) return;
    await provider.setCommune(choice.commune);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: BrandRefresh(
          onRefresh: () async {
            final provider =
                Provider.of<ProviderProvider>(context, listen: false);
            final futures = <Future>[
              provider.loadFeaturedProviders(),
              provider.loadProviders(),
            ];

            final authProvider =
                Provider.of<AuthProvider>(context, listen: false);
            if (authProvider.isAuthenticated) {
              final appointmentProvider =
                  Provider.of<AppointmentProvider>(context, listen: false);
              futures.add(appointmentProvider.loadAppointments());
            }

            await Future.wait(futures);
          },
          child: CustomScrollView(
            slivers: [
              // Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppSearchBar(
                          onTap: () => context.push('/providers'),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingS),
                      InkWell(
                        onTap: () => context.push('/profile'),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusPill),
                        child: Container(
                          width: 48, // §13.2 touch target
                          height: 48, // §13.2 touch target
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.secondary,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusPill),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(
                            Icons.person_outline,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Commune location pill
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacingM,
                    0,
                    AppTheme.spacingM,
                    AppTheme.spacingS,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Consumer<ProviderProvider>(
                      builder: (context, provider, _) => CommunePill(
                        commune: provider.selectedCommune,
                        onTap: () => _openCommunePicker(provider),
                      ),
                    ),
                  ),
                ),
              ),
              // Stories (announcements / promos)
              const SliverToBoxAdapter(
                child: AnnouncementStories(),
              ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: AppTheme.spacingM)),
              // Categories
              const SliverToBoxAdapter(
                child: CategoryChips(),
              ),
              // Featured Section
              Consumer<ProviderProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading &&
                      provider.featuredProviders.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(AppTheme.spacingL),
                        child: Center(child: LoadingIndicator()),
                      ),
                    );
                  }

                  if (provider.featuredProviders.isEmpty) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }

                  return SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacingM,
                            vertical: AppTheme.spacingS,
                          ),
                          child: Text(
                            'À la une',
                            style: AppTextStyles.titleLarge.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 280,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacingM,
                            ),
                            itemCount: provider.featuredProviders.length,
                            itemBuilder: (context, index) {
                              final p = provider.featuredProviders[index];
                              return Padding(
                                padding: const EdgeInsets.only(
                                    right: AppTheme.spacingM),
                                child: ProviderCard(
                                  provider: p,
                                  isGrid: true,
                                  onTap: () =>
                                      context.push('/provider/${p.id}'),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Recent bookings (only when authenticated) — placed AFTER “À la une”
              SliverToBoxAdapter(
                child: Consumer3<AuthProvider, AppointmentProvider,
                    ProviderProvider>(
                  builder: (context, authProvider, appointmentProvider,
                      providerProvider, _) {
                    if (!authProvider.isAuthenticated) {
                      return const SizedBox.shrink();
                    }

                    final recent = appointmentProvider.appointments
                        .where((a) => a.status != AppointmentStatus.cancelled)
                        .toList()
                      ..sort((a, b) =>
                          b.appointmentDate.compareTo(a.appointmentDate));

                    if (recent.isEmpty) return const SizedBox.shrink();

                    final top = recent.take(3).toList();

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacingM,
                        AppTheme.spacingM,
                        AppTheme.spacingM,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Derniers rendez-vous',
                                style: AppTextStyles.titleLarge.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              TextButton(
                                onPressed: () => context.push('/bookings'),
                                child: const Text('Voir tout'),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.spacingS),
                          SizedBox(
                            height: 92,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: top.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: AppTheme.spacingS),
                              itemBuilder: (context, i) {
                                final a = top[i];
                                final p = providerProvider.providers
                                    .where((p) => p.id == a.providerId)
                                    .firstOrNull;
                                final providerName = p?.name ?? 'Salon';
                                final providerImageUrl =
                                    (p != null && p.imageUrls.isNotEmpty)
                                        ? p.imageUrls.first
                                        : null;

                                final w = MediaQuery.of(context).size.width;
                                final cardWidth =
                                    (w * 0.86).clamp(280.0, 360.0);

                                return SizedBox(
                                  width: cardWidth,
                                  child: CompactAppointmentTile(
                                    appointment: a,
                                    providerName: providerName,
                                    providerImageUrl: providerImageUrl,
                                    onTap: () =>
                                        context.push('/appointment/${a.id}'),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SliverToBoxAdapter(
                  child: SizedBox(height: AppTheme.spacingM)),
              // Favorites Section
              Consumer3<FavoritesProvider, AuthProvider, ProviderProvider>(
                builder: (context, favoritesProvider, authProvider,
                    providerProvider, _) {
                  if (!authProvider.isAuthenticated ||
                      authProvider.user == null) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }

                  final favoriteProviders =
                      favoritesProvider.getFavoriteProviders(
                    providerProvider.providers,
                  );

                  if (favoriteProviders.isEmpty) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }

                  return SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacingM,
                            vertical: AppTheme.spacingS,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Mes favoris',
                                style: AppTextStyles.titleLarge.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              TextButton(
                                onPressed: () => context.push('/favorites'),
                                child: const Text('Voir la carte'),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 280,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacingM,
                            ),
                            itemCount: favoriteProviders.length,
                            itemBuilder: (context, index) {
                              final p = favoriteProviders[index];
                              return Padding(
                                padding: const EdgeInsets.only(
                                    right: AppTheme.spacingM),
                                child: ProviderCard(
                                  provider: p,
                                  isGrid: true,
                                  onTap: () =>
                                      context.push('/provider/${p.id}'),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Nearby Section
              Consumer<ProviderProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading && provider.providers.isEmpty) {
                    return const SliverFillRemaining(
                      child: Center(child: LoadingIndicator()),
                    );
                  }

                  if (provider.providers.isEmpty) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'Aucun salon trouvé',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.all(AppTheme.spacingM),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(
                                  bottom: AppTheme.spacingM),
                              child: Text(
                                'Près de vous',
                                style: AppTextStyles.titleLarge.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            );
                          }
                          final p = provider.providers[index - 1];
                          return Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppTheme.spacingM),
                            child: ProviderCard(
                              provider: p,
                              isGrid: false,
                              onTap: () => context.push('/provider/${p.id}'),
                            ),
                          );
                        },
                        childCount: provider.providers.length + 1,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 1) context.push('/favorites');
          if (index == 2) context.push('/bookings');
          if (index == 3) context.push('/notifications');
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Carte',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Rendez-vous',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            label: 'Actu',
          ),
        ],
      ),
    );
  }
}
