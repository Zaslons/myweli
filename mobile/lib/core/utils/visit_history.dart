import '../../models/appointment.dart';

/// The status to *show* for an appointment, auto-synced from elapsed time.
///
/// A cancelled appointment stays cancelled; any other appointment whose date is
/// in the past is treated as completed ("Terminé") — a placeholder until the
/// backend sends real completion / no-show events. Future appointments keep
/// their stored status.
AppointmentStatus effectiveAppointmentStatus(Appointment a, DateTime now) {
  // Cancelled and no-show are terminal outcomes — never auto-completed.
  if (a.status == AppointmentStatus.cancelled ||
      a.status == AppointmentStatus.noShow) {
    return a.status;
  }
  if (a.appointmentDate.isBefore(now)) {
    return AppointmentStatus.completed;
  }
  return a.status;
}

/// Completed past visits (effective status), newest first.
List<Appointment> visitHistory(List<Appointment> appointments, DateTime now) {
  final visits = appointments
      .where((a) =>
          effectiveAppointmentStatus(a, now) == AppointmentStatus.completed)
      .toList()
    ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));
  return visits;
}

/// Total amount across the given visits (full service price, not just deposit).
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
  }).toList()
    ..sort((a, b) => b.month.compareTo(a.month));

  return groups;
}
