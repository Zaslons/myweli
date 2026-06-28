/// Pure helpers for the pro "Aujourd'hui" view. Unit-tested.

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
};

export function todayKey(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}

/// Today's bookings (UTC day, matching the API), sorted by time.
export function todaysAppointments(
  items: ProAppointment[],
  now: Date = new Date(),
): ProAppointment[] {
  const k = todayKey(now);
  return items
    .filter((a) => a.appointmentDate.slice(0, 10) === k)
    .sort((a, b) => a.appointmentDate.localeCompare(b.appointmentDate));
}

export function todayCounts(
  items: ProAppointment[],
  now: Date = new Date(),
): { total: number; pending: number; confirmed: number } {
  const t = todaysAppointments(items, now);
  return {
    total: t.length,
    pending: t.filter((a) => a.status === 'pending').length,
    confirmed: t.filter((a) => a.status === 'confirmed').length,
  };
}
