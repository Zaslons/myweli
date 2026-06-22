import '../../models/artist.dart';

/// Whether [artist] works for the whole [start]–[end] window.
///
/// An artist with no [Artist.workingHours] follows the salon hours (always
/// true here — the salon schedule is enforced separately). Otherwise the
/// window must fall entirely within one of the artist's working ranges for
/// that weekday; a weekday with no range is a day off.
bool artistWorksDuring(Artist artist, DateTime start, DateTime end) {
  if (artist.workingHours.isEmpty) return true; // follows salon hours

  final daySlots = artist.workingHours[start.weekday - 1] ?? const [];
  if (daySlots.isEmpty) return false; // day off

  for (final slot in daySlots) {
    final slotStart = DateTime(start.year, start.month, start.day,
        slot.startTime.hour, slot.startTime.minute);
    final slotEnd = DateTime(start.year, start.month, start.day,
        slot.endTime.hour, slot.endTime.minute);
    if (!start.isBefore(slotStart) && !end.isAfter(slotEnd)) return true;
  }
  return false;
}
