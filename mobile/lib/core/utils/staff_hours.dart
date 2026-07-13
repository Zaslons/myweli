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
    // Same zone flag as [start] — never mix a naive-local range with salon
    // (UTC-flagged) slot instants (salon_time.dart).
    final slotStart = _at(start, slot.startTime.hour, slot.startTime.minute);
    final slotEnd = _at(start, slot.endTime.hour, slot.endTime.minute);
    if (!start.isBefore(slotStart) && !end.isAfter(slotEnd)) return true;
  }
  return false;
}

DateTime _at(DateTime day, int hour, int minute) => day.isUtc
    ? DateTime.utc(day.year, day.month, day.day, hour, minute)
    : DateTime(day.year, day.month, day.day, hour, minute);
