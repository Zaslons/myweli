import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../providers/provider_provider.dart';
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
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingM,
        AppTheme.spacingM,
        AppTheme.spacingM,
        AppTheme.spacingS,
      ),
      child: Row(
        children: [
          CommunePill(
            commune: provider.selectedCommune,
            onTap: () => _openCommunePicker(provider),
          ),
          const Spacer(),
          if (!provider.isLoading && provider.providers.isNotEmpty)
            Text(
              _countLabel(provider),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
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
      return RefreshIndicator(
        onRefresh: () => provider.loadProviders(category: widget.category),
        child: GridView.builder(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: AppTheme.spacingM,
            mainAxisSpacing: AppTheme.spacingM,
            childAspectRatio: 0.75,
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

    return RefreshIndicator(
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
