/// Browser → BFF (`/api/*`) wrappers for the booking funnel. Same-origin; the
/// session lives in httpOnly cookies set by the BFF (no tokens here). None of
/// them throws (docs/design/web-consumer-network-failure.md §2).

import { readJson, send, sendIdempotent } from '../api/network';
import {
  DEFAULT_HORIZON_DAYS,
  DEFAULT_NOTICE_MINUTES,
} from './window';

export async function requestOtp(
  phoneNumber: string,
): Promise<{ ok: boolean; devCode?: string; error?: string }> {
  const res = await send('/api/auth/request-otp', {
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
  const res = await send('/api/auth/verify', {
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

/// Books under [key] (docs/design/write-idempotency.md §4): one key per
/// submission, reused on « Réessayer ». A lost answer is asked again once
/// with it, at once — the server replays the booking it made, so the screen
/// gets « Réservation envoyée » WITH the deposit block instead of a 409 on
/// the person's own slot. `lost`: nothing answered, twice.
export async function createBooking(
  payload: {
    providerId: string;
    serviceIds: string[];
    appointmentDateTime: string;
    artistId: string | null;
    notes?: string;
  },
  key: string,
  opts: { wait?: (ms: number) => Promise<void> } = {},
): Promise<{ ok: boolean; appointment?: CreatedBooking; error?: string; lost?: boolean }> {
  const r = await sendIdempotent<{ appointment?: Partial<CreatedBooking> }>(
    '/api/bookings',
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    },
    key,
    { complete: (b) => Boolean(b?.appointment?.id), ...opts },
  );
  if (r.status === 0) return { ok: false, lost: true };
  if (r.status < 200 || r.status >= 300) return { ok: false, error: r.error };
  // Still without its body after asking again: the booking exists (the
  // server answered 2xx) — « Réservation envoyée », without the deposit
  // block, which the detail page offers (K2).
  const appointment = r.body?.appointment;
  return {
    ok: true,
    appointment: appointment?.id ? (appointment as CreatedBooking) : undefined,
  };
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
export type SlotsResult = {
  ok: boolean;
  slots: string[];
  /// The salon is not there any more (Decision C: `/availability` 404s a salon
  /// that is `draft` or `suspended`). Distinct from `!ok` because the two need
  /// OPPOSITE controls: a dropped connection is exactly where « Réessayer »
  /// belongs, and this is exactly where it cannot succeed. Collapsing them is
  /// what made the funnel blame the connection for a salon-state problem.
  gone?: boolean;
};

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
  const res = await send(`/api/availability?${qs.toString()}`);
  // A network-layer failure is status 0 — `ok: false`, never `gone`.
  if (res.status === 0) return { ok: false, slots: [] };
  // The BFF preserves the upstream status, so the information was always
  // here — only this function threw it away.
  if (!res.ok) return { ok: false, slots: [], gone: res.status === 404 };
  // A lost body is « we could not ask », not « no opening that day ».
  const body = await readJson<{ slots?: string[] }>(res);
  if (!body) return { ok: false, slots: [] };
  return { ok: true, slots: body.slots ?? [] };
}


