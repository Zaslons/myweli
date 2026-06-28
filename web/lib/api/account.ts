import type { Appointment } from '../account/appointments';

/// Browser → BFF (`/api/*`) wrappers for the consumer account. Session lives in
/// httpOnly cookies (no tokens here). A 401 means "not signed in" → the caller
/// redirects to /connexion.

export type Me = {
  id: string;
  name?: string | null;
  phoneNumber: string;
  email?: string | null;
};

export async function getMe(): Promise<{ status: number; user?: Me }> {
  const res = await fetch('/api/me');
  if (!res.ok) return { status: res.status };
  return { status: 200, user: (await res.json()) as Me };
}

export async function listAppointments(): Promise<{
  status: number;
  items: Appointment[];
}> {
  const res = await fetch('/api/appointments');
  if (!res.ok) return { status: res.status, items: [] };
  const body = (await res.json().catch(() => ({}))) as { items?: Appointment[] };
  return { status: 200, items: body.items ?? [] };
}

export async function getAppointment(
  id: string,
): Promise<{ status: number; appt?: Appointment }> {
  const res = await fetch(`/api/appointments/${id}`);
  if (!res.ok) return { status: res.status };
  return { status: 200, appt: (await res.json()) as Appointment };
}

export async function cancelAppointment(
  id: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await fetch(`/api/appointments/${id}/cancel`, { method: 'POST' });
  if (res.ok) return { ok: true, status: res.status };
  const body = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: body.error };
}

export async function logout(): Promise<void> {
  await fetch('/api/auth/logout', { method: 'POST' });
}
