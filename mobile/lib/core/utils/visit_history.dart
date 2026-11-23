import '../../models/appointment.dart';
import 'salon_time.dart';

/// Total amount across the given visits (full service price, not just deposit).
///
/// « Passés » passes only the bookings the salon marked `completed`
/// (decision 167): a past booking nobody closed is not a visit we can count.
double totalSpent(List<Appointment> visits) {
  return visits.fold<double>(0, (sum, a) => sum + a.totalPrice);
}

/// A month bucket of visits for the grouped history view.
class VisitMonthGroup {
  /// First day of the month this group covers.
  final DateTime month;
  final List<Appointment> visits;

  const VisitMonthGroup({required this.month, required this.visits});
}

/// Group visits into months, newest month first and newest visit first within
/// each month.
///
/// **The month is the salon's** (decision 186,
/// docs/design/web-account-bookings-truth.md §11 Q5): the one the card's own
/// date line shows (`appointment_card.dart`, `toSalonTime` with the booking's
/// `providerTimezone`). The key used to be the instant's own fields — UTC, as
/// the API sends it — so at a salon in Libreville (UTC+1) a booking at 00:30
/// on 1 November sat under « octobre » beside a card dated 1 November. The
/// web's `groupByMonth` reads the same zone.
List<VisitMonthGroup> groupVisitsByMonth(List<Appointment> visits) {
  final byMonth = <String, List<Appointment>>{};
  final monthOf = <String, DateTime>{};
  for (final a in visits) {
    final s = toSalonTime(a.appointmentDate, tz: a.providerTimezone);
    final key = '${s.year}-${s.month}';
    byMonth.putIfAbsent(key, () => []).add(a);
    monthOf.putIfAbsent(key, () => DateTime(s.year, s.month));
  }

  final groups = byMonth.entries.map((e) {
    final sorted = [...e.value]
      ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));
    return VisitMonthGroup(month: monthOf[e.key]!, visits: sorted);
  }).toList()..sort((a, b) => b.month.compareTo(a.month));

  return groups;
}
