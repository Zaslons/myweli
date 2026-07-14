import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../models/service.dart';
import '../../providers/provider_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';

class ServiceSelectionScreen extends StatefulWidget {
  final String providerId;
  final bool returnToHub;
  final List<String> initialSelectedServiceIds;
  final String? artistId;

  const ServiceSelectionScreen({
    super.key,
    required this.providerId,
    this.returnToHub = false,
    this.initialSelectedServiceIds = const <String>[],
    this.artistId,
  });

  @override
  State<ServiceSelectionScreen> createState() => _ServiceSelectionScreenState();
}

class _ServiceSelectionScreenState extends State<ServiceSelectionScreen> {
  late final Set<String> _selectedServiceIds;

  @override
  void initState() {
    super.initState();
    _selectedServiceIds = widget.initialSelectedServiceIds.toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ProviderProvider>(context, listen: false);
      provider.loadProviderById(widget.providerId);
    });
  }

  double _calculateTotal() {
    final provider = Provider.of<ProviderProvider>(context);
    final p = provider.selectedProvider;
    if (p == null) return 0.0;

    return p.services
        .where((s) => _selectedServiceIds.contains(s.id))
        .fold(0.0, (sum, s) => sum + s.price);
  }

  bool _hasRange() {
    final p =
        Provider.of<ProviderProvider>(context, listen: false).selectedProvider;
    if (p == null) return false;
    return p.services
        .where((s) => _selectedServiceIds.contains(s.id))
        .any((s) => s.priceMax != null);
  }

  void _handleContinue() {
    if (_selectedServiceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Veuillez sélectionner au moins un service')),
      );
      return;
    }

    if (widget.returnToHub) {
      context.pop<List<String>>(_selectedServiceIds.toList());
      return;
    }

    final serviceIds = _selectedServiceIds.toList().join(',');
    context.push(
        '/booking/artist?providerId=${widget.providerId}&serviceIds=$serviceIds');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Choisir un service'),
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

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  children: [
                    // Provider Header
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacingM),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusLarge),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: AppTextStyles.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  p.address,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Services List
                    ...p.services.map((service) {
                      final isSelected =
                          _selectedServiceIds.contains(service.id);
                      final disabled = widget.artistId != null &&
                          service.artistIds.isNotEmpty &&
                          !service.artistIds.contains(widget.artistId);
                      return _ServiceCard(
                        service: service,
                        isSelected: isSelected,
                        isDisabled: disabled,
                        onTap: () {
                          if (disabled) return;
                          setState(() {
                            if (isSelected) {
                              _selectedServiceIds.remove(service.id);
                            } else {
                              _selectedServiceIds.add(service.id);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              // Total & Continue Button
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  boxShadow: AppTheme.elevation3,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total:',
                          style: AppTextStyles.titleMedium,
                        ),
                        Text(
                          _hasRange()
                              ? 'À partir de ${Formatters.formatCurrency(_calculateTotal(), currency: p.currency)}'
                              : Formatters.formatCurrency(_calculateTotal(),
                                  currency: p.currency),
                          style: AppTextStyles.titleLarge.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      text: 'Continuer',
                      onPressed:
                          _selectedServiceIds.isEmpty ? null : _handleContinue,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final Service service;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.service,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: BoxDecoration(
          color: isDisabled ? AppColors.surface : AppColors.secondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderStrong,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: isDisabled ? null : (_) => onTap(),
              activeColor: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: isDisabled
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    service.description,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: isDisabled
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Formatters.formatDuration(service.durationMinutes),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                Formatters.formatPriceRange(service.price, service.priceMax,
                    currency: context
                        .read<ProviderProvider>()
                        .selectedProvider
                        ?.currency),
                textAlign: TextAlign.end,
                style: AppTextStyles.titleMedium.copyWith(
                  color:
                      isDisabled ? AppColors.textTertiary : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
