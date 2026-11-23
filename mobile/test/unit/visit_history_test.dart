import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/core/utils/visit_history.dart';
import 'package:myweli/models/appointment.dart';

void main() {
  // UTC dates, as the API sends them (`DateTime.parse` of a `…Z` string): a
  // local DateTime would make the grouping depend on the test machine's zone.
  Appointment appt({
    required String id,
    required DateTime date,
    AppointmentStatus status = AppointmentStatus.confirmed,
    double total = 20000,
    String? tz,
  }) => Appointment(
    id: id,
    userId: 'u1',
    providerId: SalonId('p1'),
    serviceIds: const ['s1'],
    appointmentDate: date,
    status: status,
    totalPrice: total,
    createdAt: DateTime.utc(2026),
    providerTimezone: tz,
  );

  test('totalSpent sums the visits total price', () {
    final visits = [
      appt(id: 'a', date: DateTime.utc(2026, 5, 1), total: 20000),
      appt(id: 'b', date: DateTime.utc(2026, 6, 1), total: 15000),
    ];
    expect(totalSpent(visits), 35000);
  });

  test('groupVisitsByMonth groups and orders months newest first', () {
    final visits = [
      appt(id: 'jun1', date: DateTime.utc(2026, 6, 14)),
      appt(id: 'jun2', date: DateTime.utc(2026, 6, 2)),
      appt(id: 'may1', date: DateTime.utc(2026, 5, 28)),
    ];

    final groups = groupVisitsByMonth(visits);
    expect(groups, hasLength(2));
    expect(groups.first.month, DateTime(2026, 6));
    expect(groups.first.visits.map((a) => a.id), ['jun1', 'jun2']);
    expect(groups[1].month, DateTime(2026, 5));
    expect(groups[1].visits.single.id, 'may1');
  });

  // Decision 186 (web-account-bookings-truth.md §11 Q5): the month is the
  // salon's, the one the card's date line shows — as on the web.
  test('groupVisitsByMonth takes the month in the salon zone', () {
    // 23:30 UTC on 31 October is 00:30 on 1 November in Libreville (UTC+1).
    final instant = DateTime.utc(2026, 10, 31, 23, 30);
    final libreville = groupVisitsByMonth([
      appt(id: 'lbv', date: instant, tz: 'Africa/Libreville'),
    ]);
    expect(libreville.single.month, DateTime(2026, 11));
    // The control: the same instant in Abidjan (UTC+0, and the default when
    // a booking carries no zone) is still October, so the zone decided.
    final abidjan = groupVisitsByMonth([appt(id: 'abj', date: instant)]);
    expect(abidjan.single.month, DateTime(2026, 10));
  });

  test('two zones on one night split into their own salon months', () {
    final instant = DateTime.utc(2026, 10, 31, 23, 30);
    final groups = groupVisitsByMonth([
      appt(id: 'abj', date: instant),
      appt(id: 'lbv', date: instant, tz: 'Africa/Libreville'),
    ]);
    expect(groups.map((g) => g.month), [
      DateTime(2026, 11),
      DateTime(2026, 10),
    ]);
    expect(groups.first.visits.single.id, 'lbv');
    expect(groups.last.visits.single.id, 'abj');
  });
}
