import '../../models/availability.dart';

/// Whether the window [start]–[end] overlaps any break for that weekday.
/// A window that merely touches a break edge (ends exactly when the break
/// starts, or starts exactly when it ends) does not overlap.
bool overlapsBreak(
    Map<int, List<TimeSlot>> breaks, DateTime start, DateTime end) {
  final dayBreaks = breaks[start.weekday - 1] ?? const [];
  for (final b in dayBreaks) {
    final bStart = DateTime(start.year, start.month, start.day,
        b.startTime.hour, b.startTime.minute);
    final bEnd = DateTime(
        start.year, start.month, start.day, b.endTime.hour, b.endTime.minute);
    if (start.isBefore(bEnd) && end.isAfter(bStart)) return true;
  }
  return false;
}
