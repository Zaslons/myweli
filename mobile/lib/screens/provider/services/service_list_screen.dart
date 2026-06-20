import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../models/service.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../providers/pro_service_provider.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../widgets/common/app_button.dart';

class ServiceListScreen extends StatefulWidget {
  const ServiceListScreen({super.key});

  @override
  State<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends State<ServiceListScreen> {
  String _resolvedProviderId(BuildContext context) {
    final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
    return authProvider.provider?.providerId ?? authProvider.provider?.id ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<ProAuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.provider != null) {
        final serviceProvider = Provider.of<ProServiceProvider>(context, listen: false);
        serviceProvider.loadServices(_resolvedProviderId(context));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Services'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/pro/service/new'),
        child: const Icon(Icons.add),
      ),
      body: Consumer2<ProAuthProvider, ProServiceProvider>(
        builder: (context, authProvider, serviceProvider, _) {
          if (!authProvider.isAuthenticated) {
            return const Center(child: Text('Veuillez vous connecter'));
          }

          if (serviceProvider.isLoading && serviceProvider.services.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final services = serviceProvider.services;
          if (services.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.build, size: 64, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    Text(
                      'Aucun service pour le moment',
                      style: AppTextStyles.titleLarge.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ajoutez vos services pour que les clients puissent réserver.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      text: 'Ajouter un service',
                      onPressed: () => context.push('/pro/service/new'),
                      isFullWidth: false,
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              if (authProvider.provider != null) {
                await serviceProvider.loadServices(_resolvedProviderId(context));
              }
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.spacingL),
              itemCount: services.length,
              itemBuilder: (context, index) {
                final service = services[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacingM),
                  child: _ServiceCard(
                    service: service,
                    onTap: () => context.push('/pro/service/${service.id}/edit'),
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

class _ServiceCard extends StatelessWidget {
  final Service service;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.service,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service.name,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  Formatters.formatCurrency(service.price),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '• ${Formatters.formatDuration(service.durationMinutes)}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            if (service.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                service.description,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
