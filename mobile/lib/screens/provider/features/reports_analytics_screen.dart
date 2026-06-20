import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/app_theme.dart';

class ReportsAnalyticsScreen extends StatelessWidget {
  const ReportsAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rapports et analyses'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Découvrez quels services et employés sont les plus populaires. Utilisez les données pour éviter les problèmes de trésorerie et planifier votre budget.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            // Revenue Chart
            Container(
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
                    'Revenus ce mois',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: CustomPaint(
                      painter: _LineChartPainter(),
                      child: Container(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('Lun', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
                      Text('Mar', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
                      Text('Mer', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
                      Text('Jeu', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
                      Text('Ven', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
                      Text('Sam', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
                      Text('Dim', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Popular Services
            Text(
              'Services les plus populaires',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _PopularItem(
              name: 'Coupe + Coloration',
              count: 45,
              revenue: '675,000 FCFA',
              percentage: 0.85,
            ),
            const SizedBox(height: 8),
            _PopularItem(
              name: 'Manucure',
              count: 32,
              revenue: '480,000 FCFA',
              percentage: 0.65,
            ),
            const SizedBox(height: 8),
            _PopularItem(
              name: 'Massage',
              count: 28,
              revenue: '560,000 FCFA',
              percentage: 0.55,
            ),
            const SizedBox(height: 24),
            // Popular Employees
            Text(
              'Employés les plus performants',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _EmployeeStatCard(
              name: 'Kouassi Jean',
              appointments: 52,
              revenue: '780,000 FCFA',
              rating: 4.8,
            ),
            const SizedBox(height: 8),
            _EmployeeStatCard(
              name: 'Marie Kouassi',
              appointments: 48,
              revenue: '720,000 FCFA',
              rating: 4.9,
            ),
            const SizedBox(height: 8),
            _EmployeeStatCard(
              name: 'Fatou Diallo',
              appointments: 41,
              revenue: '615,000 FCFA',
              rating: 4.7,
            ),
            const SizedBox(height: 24),
            // Cash Flow Indicator
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.trending_up, color: Colors.green, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trésorerie saine',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: Colors.green.shade700,
                          ),
                        ),
                        Text(
                          'Aucun problème de trésorerie prévu ce mois',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularItem extends StatelessWidget {
  final String name;
  final int count;
  final String revenue;
  final double percentage;

  const _PopularItem({
    required this.name,
    required this.count,
    required this.revenue,
    required this.percentage,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                revenue,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  child: LinearProgressIndicator(
                    value: percentage,
                    backgroundColor: AppColors.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$count réservations',
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

class _EmployeeStatCard extends StatelessWidget {
  final String name;
  final int appointments;
  final String revenue;
  final double rating;

  const _EmployeeStatCard({
    required this.name,
    required this.appointments,
    required this.revenue,
    required this.rating,
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
                Text(
                  name,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.star, size: 14, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      rating.toStringAsFixed(1),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$appointments rendez-vous',
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
            revenue,
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final path = Path();
    final points = [
      Offset(size.width * 0.1, size.height * 0.7),
      Offset(size.width * 0.2, size.height * 0.5),
      Offset(size.width * 0.3, size.height * 0.6),
      Offset(size.width * 0.4, size.height * 0.4),
      Offset(size.width * 0.5, size.height * 0.55),
      Offset(size.width * 0.6, size.height * 0.35),
      Offset(size.width * 0.7, size.height * 0.3),
    ];

    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      final controlPoint1 = Offset(
        (points[i - 1].dx + points[i].dx) / 2,
        points[i - 1].dy,
      );
      final controlPoint2 = Offset(
        (points[i - 1].dx + points[i].dx) / 2,
        points[i].dy,
      );
      path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, points[i].dx, points[i].dy);
    }

    // Create fill path by copying the path and closing it
    final fillPath = Path()
      ..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      final controlPoint1 = Offset(
        (points[i - 1].dx + points[i].dx) / 2,
        points[i - 1].dy,
      );
      final controlPoint2 = Offset(
        (points[i - 1].dx + points[i].dx) / 2,
        points[i].dy,
      );
      fillPath.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, points[i].dx, points[i].dy);
    }
    fillPath.lineTo(size.width * 0.7, size.height);
    fillPath.lineTo(size.width * 0.1, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw dots
    final dotPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
