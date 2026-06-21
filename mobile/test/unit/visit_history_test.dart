import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/visit_history.dart';
import 'package:myweli/models/appointment.dart';

void main() {
  final now = DateTime(2026, 6, 22, 12);

  Appointment appt({
    required String id,
    required DateTime date,
    AppointmentStatus status = AppointmentStatus.confirmed,
    double total = 20000,
  }) =>
      Appointment(
        id: id,
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDate: date,
        status: status,
        totalPrice: total,
        createdAt: DateTime(2026),
      );

  group('effectiveAppointmentStatus', () {
    test('cancelled stays cancelled, even in the future', () {
      final a = appt(
        id: 'a',
        date: DateTime(2026, 7, 1),
        status: AppointmentStatus.cancelled,
      );
      expect(effectiveAppointmentStatus(a, now), AppointmentStatus.cancelled);
    });

    test('an elapsed, non-cancelled appointment becomes completed', () {
      final a = appt(id: 'a', date: DateTime(2026, 6, 1));
      expect(effectiveAppointmentStatus(a, now), AppointmentStatus.completed);
    });

    test('an elapsed pending appointment also becomes completed', () {
      final a = appt(
        id: 'a',
        date: DateTime(2026, 6, 1),
        status: AppointmentStatus.pending,
      );
      expect(effectiveAppointmentStatus(a, now), AppointmentStatus.completed);
    });

    test('a future appointment keeps its stored status', () {
      final a = appt(id: 'a', date: DateTime(2026, 7, 1));
      expect(effectiveAppointmentStatus(a, now), AppointmentStatus.confirmed);
    });
  });

  test('visitHistory keeps only past non-cancelled visits, newest first', () {
    final list = [
      appt(id: 'old', date: DateTime(2026, 5, 1)),
      appt(id: 'recent', date: DateTime(2026, 6, 10)),
      appt(id: 'future', date: DateTime(2026, 7, 1)),
      appt(
        id: 'cancelled',
        date: DateTime(2026, 5, 20),
        status: AppointmentStatus.cancelled,
      ),
    ];
    expect(visitHistory(list, now).map((a) => a.id), ['recent', 'old']);
  });

  test('totalSpent sums the visits total price', () {
    final visits = [
      appt(id: 'a', date: DateTime(2026, 5, 1), total: 20000),
      appt(id: 'b', date: DateTime(2026, 6, 1), total: 15000),
    ];
    expect(totalSpent(visits), 35000);
  });

  test('groupVisitsByMonth groups and orders months newest first', () {
    final visits = visitHistory([
      appt(id: 'jun1', date: DateTime(2026, 6, 14)),
      appt(id: 'jun2', date: DateTime(2026, 6, 2)),
      appt(id: 'may1', date: DateTime(2026, 5, 28)),
    ], now);

    final groups = groupVisitsByMonth(visits);
    expect(groups, hasLength(2));
    expect(groups.first.month, DateTime(2026, 6));
    expect(groups.first.visits.map((a) => a.id), ['jun1', 'jun2']);
    expect(groups[1].month, DateTime(2026, 5));
    expect(groups[1].visits.single.id, 'may1');
  });
}
