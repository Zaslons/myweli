import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/core/utils/visit_history.dart';
import 'package:myweli/models/appointment.dart';

void main() {
  Appointment appt({
    required String id,
    required DateTime date,
    AppointmentStatus status = AppointmentStatus.confirmed,
    double total = 20000,
  }) => Appointment(
    id: id,
    userId: 'u1',
    providerId: SalonId('p1'),
    serviceIds: const ['s1'],
    appointmentDate: date,
    status: status,
    totalPrice: total,
    createdAt: DateTime(2026),
  );

  test('totalSpent sums the visits total price', () {
    final visits = [
      appt(id: 'a', date: DateTime(2026, 5, 1), total: 20000),
      appt(id: 'b', date: DateTime(2026, 6, 1), total: 15000),
    ];
    expect(totalSpent(visits), 35000);
  });

  test('groupVisitsByMonth groups and orders months newest first', () {
    final visits = [
      appt(id: 'jun1', date: DateTime(2026, 6, 14)),
      appt(id: 'jun2', date: DateTime(2026, 6, 2)),
      appt(id: 'may1', date: DateTime(2026, 5, 28)),
    ];

    final groups = groupVisitsByMonth(visits);
    expect(groups, hasLength(2));
    expect(groups.first.month, DateTime(2026, 6));
    expect(groups.first.visits.map((a) => a.id), ['jun1', 'jun2']);
    expect(groups[1].month, DateTime(2026, 5));
    expect(groups[1].visits.single.id, 'may1');
  });
}
