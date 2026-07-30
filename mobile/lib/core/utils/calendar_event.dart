import 'package:add_2_calendar/add_2_calendar.dart';

import 'formatters.dart';

/// Plain, package-free description of a calendar entry built from an
/// appointment. Kept free of `add_2_calendar` types so the composition logic
/// stays unit-testable; [addAppointmentToCalendar] is the only platform shell.
/// Design: docs/design/appointment-calendar.md (FR-APPT-006).
class CalendarEventData {
  const CalendarEventData({
    required this.title,
    required this.description,
    required this.location,
    required this.start,
    required this.end,
  });

  final String title;
  final String description;
  final String location;
  final DateTime start;
  final DateTime end;
}

/// Pure: maps an appointment + its provider/services into a [CalendarEventData].
/// End = start + total service duration (floored at 30 min when unknown). The
/// description lists the services and, when a deposit applies, the
/// acompte/solde line — mirroring what the detail screen already shows.
CalendarEventData buildAppointmentCalendarEvent({
  required String providerName,
  String? providerAddress,
  required List<String> serviceNames,
  required DateTime start,
  required int totalDurationMinutes,
  double depositAmount = 0,
  double balanceDue = 0,
  String? currency,
}) {
  final minutes = totalDurationMinutes > 0 ? totalDurationMinutes : 30;
  final lines = <String>[
    if (serviceNames.isNotEmpty) serviceNames.join(', '),
    if (depositAmount > 0)
      'Acompte ${Formatters.formatCurrency(depositAmount, currency: currency)} · '
          'Solde ${Formatters.formatCurrency(balanceDue, currency: currency)}',
  ];
  return CalendarEventData(
    title: 'Rendez-vous — $providerName',
    description: lines.join('\n'),
    location: (providerAddress != null && providerAddress.trim().isNotEmpty)
        ? providerAddress
        : providerName,
    start: start,
    end: start.add(Duration(minutes: minutes)),
  );
}

/// Platform shell: opens the native "new event" sheet pre-filled. The user
/// confirms (saves) in their own calendar app — Myweli never writes the entry.
/// Returns the package result; best-effort (the caller shows feedback).
Future<bool> addAppointmentToCalendar(CalendarEventData d) {
  return Add2Calendar.addEvent2Cal(
    Event(
      title: d.title,
      description: d.description,
      location: d.location,
      startDate: d.start,
      endDate: d.end,
    ),
  );
}
