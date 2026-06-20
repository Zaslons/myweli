import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Calendrier'),
      ),
      body: Center(
        child: Text(
          'Calendrier - À implémenter',
          style:
              AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
