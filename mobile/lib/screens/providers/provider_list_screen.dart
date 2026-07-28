import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/widgets/common/brand_refresh.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/provider_provider.dart';
import '../../services/interfaces/provider_service_interface.dart';
import '../../widgets/common/commune_picker_sheet.dart';
import '../../widgets/common/commune_pill.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/provider/provider_card.dart';

class ProviderListScreen extends StatefulWidget {
  final String? category;

  const ProviderListScreen({
    super.key,
    this.category,
  });

  @override
  State<ProviderListScreen> createState() => _ProviderListScreenState();
}

class _ProviderListScreenState extends State<ProviderListScreen> {
  bool _isGrid = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ProviderProvider>(context, listen: false);
      provider.loadProviders(category: widget.category);
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

  String _countLabel(ProviderProvider provider) {
    final n = provider.providers.length;
    final noun = n <= 1 ? 'salon' : 'salons';
    final commune = provider.selectedCommune;
    return commune != null ? '$n $noun à $commune' : '$n $noun';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Salons & Barbiers'),
        actions: [
          IconButton(
            tooltip: _isGrid ? 'Afficher en liste' : 'Afficher en grille',
            icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGrid = !_isGrid),
          ),
        ],
      ),
      body: Consumer<ProviderProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              _buildFilterBar(provider),
              Expanded(child: _buildResults(provider)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar(ProviderProvider provider) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
            // A12 — §21 row 68's finding #2, **device-confirmed**: this row
            // showed « RIGHT OVERFLOWED BY 122 PIXELS » on a 360×780pt iPhone
            // at ≈1.95×.
            //
            // The mechanism is worth naming because the pill looks safe:
            // `CommunePill` carries its own `Flexible` + `maxLines: 1` +
            // ellipsis (`commune_pill.dart:55`), and **none of it binds here**.
            // A `Row` hands a NON-flex child an unbounded width, so the pill
            // laid out at full intrinsic width — « Toutes les communes » at
            // 200% is ~286dp of glyphs plus 44 of icons in a 328dp budget —
            // and its ellipsis was dead code at this call site.
            //
            // `Flexible` here, and the `Spacer` goes: two flex children would
            // split the row in half and cap the pill even when there is room.
            // `spaceBetween` gives the leftover to the gap instead.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: CommunePill(
                    commune: provider.selectedCommune,
                    onTap: () => _openCommunePicker(provider),
                  ),
                ),
                if (!provider.isLoading && provider.providers.isNotEmpty)
                  Text(
                    _countLabel(provider),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
            child: Row(
              children: [
                _filterPill(
                  icon: Icons.swap_vert,
                  label: 'Trier',
                  active: provider.sort != ProviderSort.relevance,
                  onTap: () => _openSortSheet(provider),
                ),
                const SizedBox(width: AppTheme.spacingS),
                _filterPill(
                  icon: Icons.event_available,
                  label: 'Disponible aujourd’hui',
                  active: provider.availableToday,
                  onTap: () =>
                      provider.setAvailableToday(!provider.availableToday),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterPill({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final fg = active ? AppColors.secondary : AppColors.textPrimary;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48), // §13.2 touch target
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingM,
            vertical: AppTheme.spacingS,
          ),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(
                color: active ? AppColors.primary : AppColors.borderStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppTheme.iconXS, color: fg),
              const SizedBox(width: AppTheme.spacingS),
              Text(
                label,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSortSheet(ProviderProvider provider) async {
    final chosen = await showModalBottomSheet<ProviderSort>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.spacingL,
                  AppTheme.spacingL, AppTheme.spacingL, AppTheme.spacingS),
              child: Text('Trier par', style: AppTextStyles.titleMedium),
            ),
            for (final option in ProviderSort.values)
              ListTile(
                title: Text(option.label),
                trailing: provider.sort == option
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, option),
              ),
            const SizedBox(height: AppTheme.spacingS),
          ],
        ),
      ),
    );
    if (chosen != null) await provider.setSort(chosen);
  }

  Widget _buildResults(ProviderProvider provider) {
    if (provider.isLoading && provider.providers.isEmpty) {
      return const LoadingIndicator();
    }

    if (provider.error != null && provider.providers.isEmpty) {
      return EmptyState(
        icon: Icons.wifi_off,
        title: 'Connexion impossible',
        description: 'Vérifiez votre connexion et réessayez.',
        actionText: 'Réessayer',
        onAction: () => provider.loadProviders(category: widget.category),
      );
    }

    if (provider.providers.isEmpty) {
      final commune = provider.selectedCommune;
      return EmptyState(
        icon: Icons.search_off,
        title:
            commune != null ? 'Aucun salon à $commune' : 'Aucun salon trouvé',
        description: commune != null
            ? 'Essayez une autre commune ou élargissez la recherche.'
            : 'Essayez de modifier vos critères de recherche',
        actionText: commune != null ? 'Voir toutes les communes' : null,
        onAction: commune != null ? () => provider.setCommune(null) : null,
      );
    }

    final providers = provider.providers;
    if (_isGrid) {
      return BrandRefresh(
        onRefresh: () => provider.loadProviders(category: widget.category),
        child: GridView.builder(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          // A12: `childAspectRatio: 0.75` derived tile HEIGHT from tile WIDTH,
          // and width does not move with the OS text scale — so the card was
          // 208dp at 100% and 208dp at 200%, with the text block clipped. The
          // bound now comes from the card, which is the only thing that knows
          // its own chrome (the same reason `carouselHeight` lives there).
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: AppTheme.spacingM,
            mainAxisSpacing: AppTheme.spacingM,
            mainAxisExtent: ProviderCard.gridHeight(context),
          ),
          itemCount: providers.length,
          itemBuilder: (context, index) {
            final p = providers[index];
            return ProviderCard(
              provider: p,
              isGrid: true,
              onTap: () => context.push('/provider/${p.id}'),
            );
          },
        ),
      );
    }

    return BrandRefresh(
      onRefresh: () => provider.loadProviders(category: widget.category),
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        itemCount: providers.length,
        itemBuilder: (context, index) {
          final p = providers[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingM),
            child: ProviderCard(
              provider: p,
              isGrid: false,
              onTap: () => context.push('/provider/${p.id}'),
            ),
          );
        },
      ),
    );
  }
}
