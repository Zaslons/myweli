import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/app_theme.dart';

class BookingJournalScreen extends StatelessWidget {
  const BookingJournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Journal de réservation'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Planning de tous les employés dans un calendrier unique. Accès rapide depuis le journal à toutes les pages nécessaires : fiche client, paiements, vente de produits et fidélité.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            // Calendar
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                boxShadow: AppTheme.elevation1,
              ),
              child: TableCalendar(
                firstDay: DateTime.now(),
                lastDay: DateTime.now().add(const Duration(days: 90)),
                focusedDay: DateTime.now(),
                calendarStyle: CalendarStyle(
                  selectedDecoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  todayDecoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  outsideDaysVisible: false,
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Accès rapide',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _QuickAccessCard(
                  title: 'Fiche client',
                  icon: Icons.person,
                  color: Colors.blue,
                ),
                _QuickAccessCard(
                  title: 'Paiements',
                  icon: Icons.payment,
                  color: Colors.green,
                ),
                _QuickAccessCard(
                  title: 'Vente de produits',
                  icon: Icons.shopping_bag,
                  color: Colors.orange,
                ),
                _QuickAccessCard(
                  title: 'Fidélité',
                  icon: Icons.card_giftcard,
                  color: Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Today's Appointments
            Text(
              'Rendez-vous d\'aujourd\'hui',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _AppointmentCard(
              clientName: 'Marie Kouassi',
              service: 'Coupe + Coloration',
              time: '10:00',
              artist: 'Kouassi Jean',
            ),
            const SizedBox(height: 8),
            _AppointmentCard(
              clientName: 'Aminata Diallo',
              service: 'Manucure',
              time: '14:30',
              artist: 'Fatou Diallo',
            ),
            const SizedBox(height: 8),
            _AppointmentCard(
              clientName: 'Sophie Traoré',
              service: 'Massage',
              time: '16:00',
              artist: 'Sophie Martin',
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _QuickAccessCard({
    required this.title,
    required this.icon,
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(
            title,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final String clientName;
  final String service;
  final String time;
  final String artist;

  const _AppointmentCard({
    required this.clientName,
    required this.service,
    required this.time,
    required this.artist,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        boxShadow: AppTheme.elevation1,
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clientName,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  service,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      artist,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            time,
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
