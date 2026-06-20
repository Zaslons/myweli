import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/provider_provider.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/provider/provider_card.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_indicator.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // Check if user is authenticated
      if (!authProvider.isAuthenticated || authProvider.user == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Veuillez vous connecter pour voir vos favoris'),
              duration: Duration(seconds: 2),
            ),
          );
          context.go('/login?returnTo=${Uri.encodeComponent('/favorites')}');
        });
        return;
      }

      // Load favorites and providers
      final favoritesProvider = Provider.of<FavoritesProvider>(context, listen: false);
      final providerProvider = Provider.of<ProviderProvider>(context, listen: false);
      
      favoritesProvider.loadFavorites(authProvider.user!.id);
      providerProvider.loadProviders();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mes favoris'),
      ),
      body: Consumer3<FavoritesProvider, AuthProvider, ProviderProvider>(
        builder: (context, favoritesProvider, authProvider, providerProvider, _) {
          // Check authentication
          if (!authProvider.isAuthenticated || authProvider.user == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite_border, size: 64, color: AppColors.textTertiary),
                  const SizedBox(height: 16),
                  Text(
                    'Connectez-vous pour voir vos favoris',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      context.go('/login?returnTo=${Uri.encodeComponent('/favorites')}');
                    },
                    child: const Text('Se connecter'),
                  ),
                ],
              ),
            );
          }

          // Loading state
          if (favoritesProvider.isLoading && favoritesProvider.favoriteProviderIds.isEmpty) {
            return const LoadingIndicator();
          }

          // Get favorite providers
          final favoriteProviders = favoritesProvider.getFavoriteProviders(
            providerProvider.providers,
          );

          // Empty state
          if (favoriteProviders.isEmpty) {
            return const EmptyState(
              icon: Icons.favorite_border,
              title: 'Aucun favori',
              description: 'Ajoutez des salons à vos favoris pour les retrouver facilement',
            );
          }

          // List of favorites
          return RefreshIndicator(
            onRefresh: () async {
              final userId = authProvider.user!.id;
              await Future.wait([
                favoritesProvider.loadFavorites(userId),
                providerProvider.loadProviders(),
              ]);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              itemCount: favoriteProviders.length,
              itemBuilder: (context, index) {
                final provider = favoriteProviders[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacingM),
                  child: ProviderCard(
                    provider: provider,
                    isGrid: false,
                    onTap: () => context.push('/provider/${provider.id}'),
                  ),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) context.go('/home');
          if (index == 2) context.push('/bookings');
          if (index == 3) context.push('/profile');
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'Favoris',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Rendez-vous',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
