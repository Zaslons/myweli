import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:myweli/widgets/common/loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../models/artist.dart';
import '../../../providers/pro_artist_provider.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';

class ArtistListScreen extends StatefulWidget {
  const ArtistListScreen({super.key});

  @override
  State<ArtistListScreen> createState() => _ArtistListScreenState();
}

class _ArtistListScreenState extends State<ArtistListScreen> {
  String _resolvedProviderId(BuildContext context) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    return authProvider.activeSalonId ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.provider != null) {
        final artistProvider =
            Provider.of<ProArtistProvider>(context, listen: false);
        artistProvider.loadArtists(_resolvedProviderId(context));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Employés'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/pro/artist/new'),
        child: const Icon(Icons.add),
      ),
      body: Consumer2<ProAuthProvider, ProArtistProvider>(
        builder: (context, authProvider, artistProvider, _) {
          if (!authProvider.isAuthenticated) {
            return const Center(child: Text('Veuillez vous connecter'));
          }

          if (artistProvider.isLoading && artistProvider.artists.isEmpty) {
            return const Center(child: LoadingIndicator());
          }

          final artists = artistProvider.artists;
          if (artists.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.people_outline,
                        size: AppTheme.iconXL, color: AppColors.textSecondary),
                    const SizedBox(height: AppTheme.spacingM),
                    Text(
                      'Aucun employé',
                      style: AppTextStyles.titleLarge.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacingS),
                    Text(
                      'Ajoutez vos employés pour qu\'ils apparaissent dans le flux de réservation.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacingL),
                    AppButton(
                      text: 'Ajouter un employé',
                      onPressed: () => context.push('/pro/artist/new'),
                      isFullWidth: false,
                    ),
                  ],
                ),
              ),
            );
          }

          return BrandRefresh(
            onRefresh: () async {
              if (authProvider.provider != null) {
                await artistProvider.loadArtists(_resolvedProviderId(context));
              }
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.spacingL),
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacingM),
                  child: _ArtistCard(
                    artist: artist,
                    onTap: () => context.push('/pro/artist/${artist.id}/edit'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final Artist artist;
  final VoidCallback onTap;

  const _ArtistCard({
    required this.artist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusXL),
          boxShadow: AppTheme.elevation1,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
              backgroundImage: artist.imageUrl != null
                  ? NetworkImage(artist.imageUrl!)
                  : null,
              child: artist.imageUrl == null
                  ? Text(
                      artist.name.isNotEmpty
                          ? artist.name[0].toUpperCase()
                          : '?',
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.primary),
                    )
                  : null,
            ),
            const SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (artist.specialization != null &&
                      artist.specialization!.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(
                      artist.specialization!,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
