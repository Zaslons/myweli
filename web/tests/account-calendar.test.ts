import { describe, expect, it } from 'vitest';
import type { Appointment } from '../lib/account/appointments';
import {
  buildIcs,
  calendarTitle,
  googleCalendarUrl,
} from '../lib/account/calendar';

const appt: Appointment = {
  id: 'a1',
  status: 'confirmed',
  appointmentDate: '2026-08-01T09:00:00.000Z',
  durationMinutes: 90,
  providerId: 'p1',
  providerName: 'Beauté Divine',
  serviceNames: ['Tresses'],
};

describe('add-to-calendar (parity 1.2)', () => {
  it('builds the Google template URL with UTC stamps + duration end', () => {
    const url = googleCalendarUrl(appt);
    expect(url).toContain('calendar.google.com/calendar/render');
    expect(url).toContain('dates=20260801T090000Z%2F20260801T103000Z');
    // URLSearchParams encodes spaces as '+'.
    expect(url).toContain('text=Rendez-vous+%E2%80%94+Beaut%C3%A9+Divine');
    expect(calendarTitle(appt)).toBe('Rendez-vous — Beauté Divine');
  });

  it('builds a valid .ics with the event window', () => {
    const ics = buildIcs(appt);
    expect(ics).toContain('BEGIN:VCALENDAR');
    expect(ics).toContain('DTSTART:20260801T090000Z');
    expect(ics).toContain('DTEND:20260801T103000Z');
    expect(ics).toContain('SUMMARY:Rendez-vous — Beauté Divine');
    expect(ics).toContain('UID:myweli-a1');
  });

  it('defaults to 60 minutes without a duration', () => {
    const ics = buildIcs({ ...appt, durationMinutes: undefined });
    expect(ics).toContain('DTEND:20260801T100000Z');
  });
});
