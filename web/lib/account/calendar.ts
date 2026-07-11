/// « Ajouter au calendrier » (parity 1.2 — the app's add_2_calendar, web
/// idiom): a Google-Calendar template URL + a client-built .ics. Pure;
/// unit-tested.

import type { Appointment } from './appointments';

/// 20260711T090000Z — the compact UTC stamp both formats want.
function stamp(iso: string): string {
  return new Date(iso)
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\.\d{3}/, '');
}

function endIso(a: Appointment): string {
  const ms = (a.durationMinutes ?? 60) * 60_000;
  return new Date(Date.parse(a.appointmentDate) + ms).toISOString();
}

export function calendarTitle(a: Appointment): string {
  return `Rendez-vous — ${a.providerName ?? 'MyWeli'}`;
}

export function googleCalendarUrl(a: Appointment): string {
  const qs = new URLSearchParams({
    action: 'TEMPLATE',
    text: calendarTitle(a),
    dates: `${stamp(a.appointmentDate)}/${stamp(endIso(a))}`,
    details: (a.serviceNames ?? []).join(', '),
  });
  return `https://calendar.google.com/calendar/render?${qs.toString()}`;
}

export function buildIcs(a: Appointment): string {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//MyWeli//FR',
    'BEGIN:VEVENT',
    `UID:myweli-${a.id}`,
    `DTSTAMP:${stamp(new Date().toISOString())}`,
    `DTSTART:${stamp(a.appointmentDate)}`,
    `DTEND:${stamp(endIso(a))}`,
    `SUMMARY:${calendarTitle(a)}`,
    `DESCRIPTION:${(a.serviceNames ?? []).join(', ')}`,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
}
