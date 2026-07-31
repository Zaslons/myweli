/// Browser → BFF (`/api/*`) wrappers for the booking funnel. Same-origin; the
/// session lives in httpOnly cookies set by the BFF (no tokens here).

import {
  DEFAULT_HORIZON_DAYS,
  DEFAULT_NOTICE_MINUTES,
} from './window';

export async function requestOtp(
  phoneNumber: string,
): Promise<{ ok: boolean; devCode?: string; error?: string }> {
  const res = await fetch('/api/auth/request-otp', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber }),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok ? { ok: true, devCode: body.devCode } : { ok: false, error: body.error };
}

export async function verifyOtp(
  phoneNumber: string,
  code: string,
): Promise<{ ok: boolean; error?: string }> {
  const res = await fetch('/api/auth/verify', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber, code }),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok ? { ok: true } : { ok: false, error: body.error };
}

export type CreatedBooking = {
  id: string;
  status?: string;
  depositAmount?: number;
  balanceDue?: number;
  totalPrice?: number;
};

export async function createBooking(payload: {
  providerId: string;
  serviceIds: string[];
  appointmentDateTime: string;
  artistId: string | null;
  notes?: string;
}): Promise<{ ok: boolean; appointment?: CreatedBooking; error?: string }> {
  const res = await fetch('/api/bookings', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok
    ? { ok: true, appointment: body.appointment }
    : { ok: false, error: body.error };
}

/// The outcome of a slot query — `ok: false` means WE COULD NOT ASK, which is
/// not the same fact as « this day is free of openings » (A14d).
///
/// This used to be a bare `Promise<string[]>` with `if (!res.ok) return []`, so
/// a 500, a dead network and a genuinely quiet Saturday were one value, and
/// both consumer surfaces rendered « Aucun créneau disponible » for all three.
/// That is the same defect A14c fixed on mobile, where `SlotPicker`'s comment
/// still records it: telling a user the salon is full when the truth is that we
/// never reached it. Web had three states where mobile has four.
export type SlotsResult = { ok: boolean; slots: string[] };

export async function fetchSlots(params: {
  providerId: string;
  date: string;
  serviceIds: string[];
  durationMinutes: number;
  artistId?: string | null;
}): Promise<SlotsResult> {
  const qs = new URLSearchParams({
    providerId: params.providerId,
    date: params.date,
    serviceIds: params.serviceIds.join(','),
    durationMinutes: String(params.durationMinutes),
  });
  if (params.artistId) qs.set('artistId', params.artistId);
  try {
    const res = await fetch(`/api/availability?${qs.toString()}`);
    // The BFF preserves the upstream status, so the information was always
    // here — only this function threw it away.
    if (!res.ok) return { ok: false, slots: [] };
    const body = await res.json().catch(() => ({}));
    return { ok: true, slots: (body.slots as string[] | undefined) ?? [] };
  } catch {
    // A network-layer failure never reaches the `res.ok` branch at all.
    return { ok: false, slots: [] };
  }
}

/// The salon's bookable window, for a surface that holds only an appointment
/// (A14d).
///
/// The booking funnel server-renders its provider and needs nothing here; the
/// account reschedule screen has an `Appointment`, so it knows the salon's id
/// and not its window — and without the window it can only fall back to the
/// defaults and tell a client « aucun créneau » for a date the salon simply
/// does not accept. Mobile solves this the same way: `showRescheduleScreen`
/// requires a `models.Provider`, and its caller fetches one.
///
/// Falls back to the defaults on any failure rather than throwing: an
/// unreachable provider must degrade the EXPLANATION, never the screen.
export async function fetchBookingWindow(
  providerId: string,
): Promise<{ horizonDays: number; noticeMinutes: number }> {
  try {
    const res = await fetch(`/api/providers/${encodeURIComponent(providerId)}`);
    if (!res.ok) return fallbackWindow();
    const body = (await res.json().catch(() => ({}))) as {
      availability?: { bookingHorizonDays?: number; minimumNoticeMinutes?: number };
    };
    return {
      horizonDays: body.availability?.bookingHorizonDays ?? DEFAULT_HORIZON_DAYS,
      noticeMinutes:
        body.availability?.minimumNoticeMinutes ?? DEFAULT_NOTICE_MINUTES,
    };
  } catch {
    return fallbackWindow();
  }
}

function fallbackWindow() {
  return {
    horizonDays: DEFAULT_HORIZON_DAYS,
    noticeMinutes: DEFAULT_NOTICE_MINUTES,
  };
}
