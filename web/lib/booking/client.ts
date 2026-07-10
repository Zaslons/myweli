/// Browser → BFF (`/api/*`) wrappers for the booking funnel. Same-origin; the
/// session lives in httpOnly cookies set by the BFF (no tokens here).

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

export async function fetchSlots(params: {
  providerId: string;
  date: string;
  serviceIds: string[];
  durationMinutes: number;
  artistId?: string | null;
}): Promise<string[]> {
  const qs = new URLSearchParams({
    providerId: params.providerId,
    date: params.date,
    serviceIds: params.serviceIds.join(','),
    durationMinutes: String(params.durationMinutes),
  });
  if (params.artistId) qs.set('artistId', params.artistId);
  const res = await fetch(`/api/availability?${qs.toString()}`);
  if (!res.ok) return [];
  const body = await res.json().catch(() => ({}));
  return (body.slots as string[] | undefined) ?? [];
}
