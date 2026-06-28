import type { ProAppointment } from '../pro/today';

/// Browser → pro BFF (`/api/pro/*`) wrappers. Pro session lives in the pro
/// httpOnly cookies; a 401 means "not signed in" → redirect to /pro/connexion.

export type ProProfile = {
  account: {
    id: string;
    businessName: string;
    phoneNumber: string;
    providerId?: string | null;
  };
  provider: {
    id: string;
    name: string;
    commune?: string;
    services?: { id: string; name: string }[];
  };
};

export async function requestOtpPro(
  phoneNumber: string,
): Promise<{ ok: boolean; devCode?: string; error?: string }> {
  const res = await fetch('/api/pro/auth/request-otp', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber }),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok ? { ok: true, devCode: body.devCode } : { ok: false, error: body.error };
}

export async function verifyOtpPro(
  phoneNumber: string,
  code: string,
): Promise<{ ok: boolean; error?: string }> {
  const res = await fetch('/api/pro/auth/verify', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber, code }),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok ? { ok: true } : { ok: false, error: body.error };
}

export async function getMyProvider(): Promise<{
  status: number;
  profile?: ProProfile;
}> {
  const res = await fetch('/api/pro/me');
  if (!res.ok) return { status: res.status };
  return { status: 200, profile: (await res.json()) as ProProfile };
}

export async function listProAppointments(): Promise<{
  status: number;
  items: ProAppointment[];
}> {
  const res = await fetch('/api/pro/appointments');
  if (!res.ok) return { status: res.status, items: [] };
  const body = (await res.json().catch(() => ({}))) as { items?: ProAppointment[] };
  return { status: 200, items: body.items ?? [] };
}

export async function logoutPro(): Promise<void> {
  await fetch('/api/pro/auth/logout', { method: 'POST' });
}
