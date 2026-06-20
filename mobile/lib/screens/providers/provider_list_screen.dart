import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../providers/provider_provider.dart';
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
          if (provider.isLoading && provider.providers.isEmpty) {
            return const LoadingIndicator();
          }

          if (provider.providers.isEmpty) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Aucun salon trouvé',
              description: 'Essayez de modifier vos critères de recherche',
            );
          }

          if (_isGrid) {
            return GridView.builder(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppTheme.spacingM,
                mainAxisSpacing: AppTheme.spacingM,
                childAspectRatio: 0.75,
              ),
              itemCount: provider.providers.length,
              itemBuilder: (context, index) {
                final p = provider.providers[index];
                return ProviderCard(
                  provider: p,
                  isGrid: true,
                  onTap: () => context.push('/provider/${p.id}'),
                );
              },
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await provider.loadProviders(category: widget.category);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              itemCount: provider.providers.length,
              itemBuilder: (context, index) {
                final p = provider.providers[index];
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
        },
      ),
    );
  }
}
