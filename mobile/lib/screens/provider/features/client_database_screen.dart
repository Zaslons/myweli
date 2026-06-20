import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';

class ClientDatabaseScreen extends StatelessWidget {
  const ClientDatabaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Base de données clients'),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher un client...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                ),
                filled: true,
                fillColor: AppColors.secondary,
              ),
            ),
          ),
          // Info Text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
            child: Text(
              'Enregistrez tout sur les clients : historique des visites, préférences, nombre de bonus. Ils apprécieront cette attention. Segmentez la base et envoyez des offres personnalisées.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Filter Chips
          const SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
            child: Row(
              children: [
                _FilterChip('Tous', isSelected: true),
                SizedBox(width: 8),
                _FilterChip('VIP'),
                SizedBox(width: 8),
                _FilterChip('Nouveaux'),
                SizedBox(width: 8),
                _FilterChip('Inactifs'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Client List
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
              children: const [
                _ClientCard(
                  name: 'Marie Kouassi',
                  phone: '+225 07 12 34 56 78',
                  visits: 12,
                  bonus: 450,
                  lastVisit: 'Il y a 3 jours',
                ),
                SizedBox(height: 12),
                _ClientCard(
                  name: 'Aminata Diallo',
                  phone: '+225 05 98 76 54 32',
                  visits: 8,
                  bonus: 280,
                  lastVisit: 'Il y a 1 semaine',
                ),
                SizedBox(height: 12),
                _ClientCard(
                  name: 'Sophie Traoré',
                  phone: '+225 01 23 45 67 89',
                  visits: 25,
                  bonus: 1200,
                  lastVisit: 'Hier',
                  isVip: true,
                ),
                SizedBox(height: 12),
                _ClientCard(
                  name: 'Fatou Camara',
                  phone: '+225 07 88 99 00 11',
                  visits: 3,
                  bonus: 90,
                  lastVisit: 'Il y a 2 semaines',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;

  const _FilterChip(this.label, {this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {},
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      checkmarkColor: AppColors.primary,
    );
  }
}

class _ClientCard extends StatelessWidget {
  final String name;
  final String phone;
  final int visits;
  final int bonus;
  final String lastVisit;
  final bool isVip;

  const _ClientCard({
    required this.name,
    required this.phone,
    required this.visits,
    required this.bonus,
    required this.lastVisit,
    this.isVip = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: AppTheme.elevation1,
        border: isVip ? Border.all(color: Colors.amber, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Text(
                  name[0],
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (isVip) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {},
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  icon: Icons.event,
                  label: 'Visites',
                  value: visits.toString(),
                ),
              ),
              Expanded(
                child: _StatItem(
                  icon: Icons.card_giftcard,
                  label: 'Bonus',
                  value: bonus.toString(),
                ),
              ),
              Expanded(
                child: _StatItem(
                  icon: Icons.access_time,
                  label: 'Dernière visite',
                  value: lastVisit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.textTertiary),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
