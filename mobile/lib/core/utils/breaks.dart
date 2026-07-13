import '../../models/availability.dart';

/// Whether the window [start]–[end] overlaps any break for that weekday.
/// A window that merely touches a break edge (ends exactly when the break
/// starts, or starts exactly when it ends) does not overlap.
bool overlapsBreak(
    Map<int, List<TimeSlot>> breaks, DateTime start, DateTime end) {
  final dayBreaks = breaks[start.weekday - 1] ?? const [];
  for (final b in dayBreaks) {
    // Rebase the break's wall-clock onto [start]'s day IN THE SAME zone flag
    // as [start] — mixing a naive-local window with salon (UTC-flagged) slot
    // instants would compare different instants (salon_time.dart).
    final bStart = _at(start, b.startTime.hour, b.startTime.minute);
    final bEnd = _at(start, b.endTime.hour, b.endTime.minute);
    if (start.isBefore(bEnd) && end.isAfter(bStart)) return true;
  }
  return false;
}

DateTime _at(DateTime day, int hour, int minute) => day.isUtc
    ? DateTime.utc(day.year, day.month, day.day, hour, minute)
    : DateTime(day.year, day.month, day.day, hour, minute);
