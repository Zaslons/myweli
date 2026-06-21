import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/cancellation_policy.dart';

void main() {
  final appt = DateTime(2026, 6, 21, 18, 0);

  test('cancelling within the window forfeits a paid deposit', () {
    final o = cancellationOutcome(
      appointmentDate: appt,
      now: appt.subtract(const Duration(hours: 5)),
      windowHours: 24,
      depositAmount: 6000,
    );
    expect(o.isLate, isTrue);
    expect(o.depositForfeited, isTrue);
  });

  test('cancelling outside the window keeps the deposit refundable', () {
    final o = cancellationOutcome(
      appointmentDate: appt,
      now: appt.subtract(const Duration(hours: 30)),
      windowHours: 24,
      depositAmount: 6000,
    );
    expect(o.isLate, isFalse);
    expect(o.depositForfeited, isFalse);
  });

  test('no deposit is never forfeited, even when late', () {
    final o = cancellationOutcome(
      appointmentDate: appt,
      now: appt.subtract(const Duration(hours: 1)),
      windowHours: 24,
      depositAmount: 0,
    );
    expect(o.isLate, isTrue);
    expect(o.depositForfeited, isFalse);
  });

  test('exactly at the cutoff counts as late', () {
    final o = cancellationOutcome(
      appointmentDate: appt,
      now: appt.subtract(const Duration(hours: 24)),
      windowHours: 24,
      depositAmount: 6000,
    );
    expect(o.isLate, isTrue);
    expect(o.depositForfeited, isTrue);
  });
}
