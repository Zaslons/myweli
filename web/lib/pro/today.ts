/// Pure helpers for the pro "Aujourd'hui" view. Unit-tested.

import { salonDayKey } from '../time';

export type ProAppointment = {
  id: string;
  status: string;
  appointmentDate: string;
  serviceIds?: string[];
  clientName?: string | null;
  clientPhone?: string | null;
  totalPrice?: number;
  depositAmount?: number;
  depositScreenshotUrl?: string | null;
  /// PROVIDER VIEW (module clients C1): links the booking to the client card.
  salonClientId?: string | null;
  /// PROVIDER VIEW: no-show count at this salon (badge: 1 neutral, ≥2 red).
  clientNoShowCount?: number | null;
  /// Journal grid (J1): assigned artist column, service duration, and the
  /// in-day « Client arrivé » stamp.
  artistId?: string | null;
  durationMinutes?: number;
  arrivedAt?: string | null;
};

export function todayKey(now: Date = new Date(), tz?: string): string {
  return salonDayKey(now, tz);
}

/// The SALON day an appointment falls on (multi-pays MP3: the instant's day
/// in the salon's zone — NOT the ISO string's UTC prefix, which is one day
/// off past midnight at UTC+1).
export function apptDayKey(a: ProAppointment, tz?: string): string {
  return salonDayKey(new Date(a.appointmentDate), tz);
}

/// Today's bookings (SALON day — lib/time.ts), sorted by time.
export function todaysAppointments(
  items: ProAppointment[],
  now: Date = new Date(),
  tz?: string,
): ProAppointment[] {
  const k = todayKey(now, tz);
  return items
    .filter((a) => apptDayKey(a, tz) === k)
    .sort((a, b) => a.appointmentDate.localeCompare(b.appointmentDate));
}

export function todayCounts(
  items: ProAppointment[],
  now: Date = new Date(),
  tz?: string,
): { total: number; pending: number; confirmed: number } {
  const t = todaysAppointments(items, now, tz);
  return {
    total: t.length,
    pending: t.filter((a) => a.status === 'pending').length,
    confirmed: t.filter((a) => a.status === 'confirmed').length,
  };
}
