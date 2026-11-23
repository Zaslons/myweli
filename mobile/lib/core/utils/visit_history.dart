import '../../models/appointment.dart';

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
List<VisitMonthGroup> groupVisitsByMonth(List<Appointment> visits) {
  final byMonth = <String, List<Appointment>>{};
  for (final a in visits) {
    final key = '${a.appointmentDate.year}-${a.appointmentDate.month}';
    byMonth.putIfAbsent(key, () => []).add(a);
  }

  final groups = byMonth.values.map((items) {
    final sorted = [...items]
      ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));
    final first = sorted.first.appointmentDate;
    return VisitMonthGroup(
      month: DateTime(first.year, first.month),
      visits: sorted,
    );
  }).toList()..sort((a, b) => b.month.compareTo(a.month));

  return groups;
}
