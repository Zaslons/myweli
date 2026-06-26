import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/utils/category_colors.dart';

void main() {
  test('maps known categories to their muted accent tokens', () {
    expect(categoryColor('spa'), AppColors.categorySpa);
    expect(categoryColor('barber'), AppColors.categoryBarber);
    expect(categoryColor('salon'), AppColors.categorySalon);
  });

  test('falls back to primary for unknown categories', () {
    expect(categoryColor('unknown'), AppColors.primary);
    expect(categoryColor(''), AppColors.primary);
  });
}
