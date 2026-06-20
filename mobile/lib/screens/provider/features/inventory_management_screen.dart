import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';

class InventoryManagementScreen extends StatelessWidget {
  const InventoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gestion des stocks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gérez les stocks de produits et consommables 10 fois plus rapidement. Vous ne manquerez pas le moment d\'acheter le nécessaire. Les pertes et surconsommation seront réduites.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            // Summary Cards
            const Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'Produits',
                    value: '24',
                    subtitle: 'En stock',
                    color: Colors.blue,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'Alertes',
                    value: '3',
                    subtitle: 'Stock faible',
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Search Bar
            TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher un produit...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                ),
                filled: true,
                fillColor: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 16),
            // Product List
            const _ProductItem(
              name: 'Shampooing Professionnel',
              category: 'Produit capillaire',
              stock: 15,
              minStock: 10,
              unit: 'bouteilles',
              status: StockStatus.normal,
            ),
            const SizedBox(height: 8),
            const _ProductItem(
              name: 'Vernis à ongles',
              category: 'Manucure',
              stock: 5,
              minStock: 10,
              unit: 'bouteilles',
              status: StockStatus.low,
            ),
            const SizedBox(height: 8),
            const _ProductItem(
              name: 'Cire épilatoire',
              category: 'Épilation',
              stock: 8,
              minStock: 10,
              unit: 'pots',
              status: StockStatus.low,
            ),
            const SizedBox(height: 8),
            const _ProductItem(
              name: 'Serviettes',
              category: 'Consommable',
              stock: 45,
              minStock: 20,
              unit: 'pièces',
              status: StockStatus.normal,
            ),
            const SizedBox(height: 8),
            const _ProductItem(
              name: 'Masque facial',
              category: 'Soin',
              stock: 2,
              minStock: 10,
              unit: 'tubes',
              status: StockStatus.critical,
            ),
          ],
        ),
      ),
    );
  }
}

enum StockStatus { normal, low, critical }

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            title,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.headlineSmall.copyWith(
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductItem extends StatelessWidget {
  final String name;
  final String category;
  final int stock;
  final int minStock;
  final String unit;
  final StockStatus status;

  const _ProductItem({
    required this.name,
    required this.category,
    required this.stock,
    required this.minStock,
    required this.unit,
    required this.status,
  });

  Color get _statusColor {
    switch (status) {
      case StockStatus.normal:
        return Colors.green;
      case StockStatus.low:
        return Colors.orange;
      case StockStatus.critical:
        return Colors.red;
    }
  }

  String get _statusText {
    switch (status) {
      case StockStatus.normal:
        return 'Stock normal';
      case StockStatus.low:
        return 'Stock faible';
      case StockStatus.critical:
        return 'Stock critique';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: AppTheme.elevation1,
        border: Border.all(
          color: _statusColor.withValues(alpha: 0.3),
          width: status != StockStatus.normal ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(
              Icons.inventory_2,
              color: _statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  category,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.warning, size: 14, color: _statusColor),
                    const SizedBox(width: 4),
                    Text(
                      _statusText,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: _statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$stock $unit',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Min: $minStock',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
