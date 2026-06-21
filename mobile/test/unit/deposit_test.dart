import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/deposit.dart';

void main() {
  group('computeDeposit', () {
    test('returns 0 when the provider requires no deposit', () {
      expect(
        computeDeposit(total: 20000, depositRequired: false, percentage: 0.30),
        0,
      );
    });

    test('computes a rounded percentage of the total', () {
      expect(
        computeDeposit(total: 20000, depositRequired: true, percentage: 0.30),
        6000,
      );
      expect(
        computeDeposit(total: 15000, depositRequired: true, percentage: 0.50),
        7500,
      );
    });

    test('returns 0 for a non-positive total', () {
      expect(
        computeDeposit(total: 0, depositRequired: true, percentage: 0.30),
        0,
      );
    });
  });
}
