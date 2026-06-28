import type { Appointment } from '../account/appointments';
import type { Provider } from './providers';

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

// --- M8.3: review + favorites -----------------------------------------------

export async function submitReview(
  appointmentId: string,
  input: { rating: number; text?: string },
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await fetch(`/api/appointments/${appointmentId}/review`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(input),
  });
  if (res.ok) return { ok: true, status: res.status };
  const b = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: b.error };
}

export async function getFavorites(): Promise<{
  status: number;
  favorites: Provider[];
}> {
  const res = await fetch('/api/me/favorites');
  if (!res.ok) return { status: res.status, favorites: [] };
  const b = (await res.json().catch(() => ({}))) as { favorites?: Provider[] };
  return { status: 200, favorites: b.favorites ?? [] };
}

export async function addFavorite(
  providerId: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await fetch(`/api/me/favorites/${providerId}`, { method: 'POST' });
  return { ok: res.ok, status: res.status };
}

export async function removeFavorite(
  providerId: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await fetch(`/api/me/favorites/${providerId}`, {
    method: 'DELETE',
  });
  return { ok: res.ok, status: res.status };
}

export async function logout(): Promise<void> {
  await fetch('/api/auth/logout', { method: 'POST' });
}
