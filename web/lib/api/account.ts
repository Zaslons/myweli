import type { Appointment } from '../account/appointments';
import type {
  AppNotification,
  NotificationPrefs,
} from '../account/notifications';
import type { Provider } from './providers';

/// Browser → BFF (`/api/*`) wrappers for the consumer account. Session lives in
/// httpOnly cookies (no tokens here). A 401 means "not signed in" → the caller
/// redirects to /connexion.

export type Me = {
  id: string;
  name?: string | null;
  phoneNumber?: string | null;
  phoneVerified?: boolean;
  email?: string | null;
  authProvider?: 'google' | 'apple' | 'email' | 'phone' | null;
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

/// Move a booking (« Reporter » — parity 1.1). 409 = slot taken.
export async function rescheduleAppointment(
  id: string,
  newDateTime: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await fetch(`/api/appointments/${id}/reschedule`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ newDateTime }),
  });
  if (res.ok) return { ok: true, status: res.status };
  const body = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: body.error };
}

// --- M8.3: review + favorites -----------------------------------------------

export async function submitReview(
  appointmentId: string,
  input: { rating: number; text?: string; photoUrls?: string[] },
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

/// Update the display name (parity 11.3 — PATCH /me accepts it).
export async function updateName(
  name: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await fetch('/api/me', {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name }),
  });
  return { ok: res.ok, status: res.status };
}

/// Delete the account (parity 11.1 — definitive; the BFF ends the session).
export async function deleteAccount(): Promise<{ ok: boolean; status: number }> {
  const res = await fetch('/api/me', { method: 'DELETE' });
  return { ok: res.ok, status: res.status };
}

// --- notifications (parity 5.1/5.2) -----------------------------------------

export async function getNotifications(): Promise<{
  status: number;
  items: AppNotification[];
}> {
  const res = await fetch('/api/me/notifications');
  if (!res.ok) return { status: res.status, items: [] };
  const body = (await res.json()) as { items?: AppNotification[] };
  return { status: 200, items: body.items ?? [] };
}

export async function markNotificationRead(
  id: string,
): Promise<{ ok: boolean }> {
  const res = await fetch(`/api/me/notifications/${id}/read`, {
    method: 'POST',
  });
  return { ok: res.ok };
}

export async function markAllNotificationsRead(): Promise<{ ok: boolean }> {
  const res = await fetch('/api/me/notifications/read-all', {
    method: 'POST',
  });
  return { ok: res.ok };
}

export async function getNotificationPrefs(): Promise<{
  status: number;
  prefs?: NotificationPrefs;
}> {
  const res = await fetch('/api/me/notification-preferences');
  if (!res.ok) return { status: res.status };
  return { status: 200, prefs: (await res.json()) as NotificationPrefs };
}

export async function updateNotificationPrefs(
  patch: Partial<NotificationPrefs>,
): Promise<{ ok: boolean; prefs?: NotificationPrefs }> {
  const res = await fetch('/api/me/notification-preferences', {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(patch),
  });
  if (!res.ok) return { ok: false };
  return { ok: true, prefs: (await res.json()) as NotificationPrefs };
}

export async function logout(): Promise<void> {
  await fetch('/api/auth/logout', { method: 'POST' });
}
