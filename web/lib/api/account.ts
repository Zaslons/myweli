import type { Appointment } from '../account/appointments';
import type {
  AppNotification,
  NotificationPrefs,
} from '../account/notifications';
import { readJson, send } from './network';
import type { Provider } from './providers';

/// Browser → BFF (`/api/*`) wrappers for the consumer account. Session lives in
/// httpOnly cookies (no tokens here). A 401 means "not signed in" → the caller
/// redirects to /connexion.
///
/// **None of them throws** (docs/design/web-consumer-network-failure.md §2): a
/// call that never got a usable answer is **status 0** (`ok: false` for a
/// write), through `send()` / `readJson()` (`./network`). Every export is held
/// by `tests/consumer-api-network.test.ts` — a new wrapper joins its table.

export type Me = {
  id: string;
  name?: string | null;
  phoneNumber?: string | null;
  phoneVerified?: boolean;
  email?: string | null;
  authProvider?: 'google' | 'apple' | 'email' | 'phone' | null;
};

export async function getMe(): Promise<{ status: number; user?: Me }> {
  const res = await send('/api/me');
  if (!res.ok) return { status: res.status };
  const user = await readJson<Me>(res);
  return user ? { status: 200, user } : { status: 0 };
}

export async function listAppointments(): Promise<{
  status: number;
  items: Appointment[];
}> {
  const res = await send('/api/appointments');
  if (!res.ok) return { status: res.status, items: [] };
  const body = await readJson<{ items?: Appointment[] }>(res);
  return body ? { status: 200, items: body.items ?? [] } : { status: 0, items: [] };
}

export async function getAppointment(
  id: string,
): Promise<{ status: number; appt?: Appointment }> {
  const res = await send(`/api/appointments/${id}`);
  if (!res.ok) return { status: res.status };
  const appt = await readJson<Appointment>(res);
  return appt ? { status: 200, appt } : { status: 0 };
}

export async function cancelAppointment(
  id: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await send(`/api/appointments/${id}/cancel`, { method: 'POST' });
  if (res.ok) return { ok: true, status: res.status };
  const body = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: body.error };
}

/// Move a booking (« Reporter » — parity 1.1). 409 = slot taken.
export async function rescheduleAppointment(
  id: string,
  newDateTime: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await send(`/api/appointments/${id}/reschedule`, {
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
  const res = await send(`/api/appointments/${appointmentId}/review`, {
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
  const res = await send('/api/me/favorites');
  if (!res.ok) return { status: res.status, favorites: [] };
  const b = await readJson<{ favorites?: Provider[] }>(res);
  return b ? { status: 200, favorites: b.favorites ?? [] } : { status: 0, favorites: [] };
}

export async function addFavorite(
  providerId: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await send(`/api/me/favorites/${providerId}`, { method: 'POST' });
  return { ok: res.ok, status: res.status };
}

export async function removeFavorite(
  providerId: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await send(`/api/me/favorites/${providerId}`, {
    method: 'DELETE',
  });
  return { ok: res.ok, status: res.status };
}

/// Update the display name (parity 11.3 — PATCH /me accepts it).
export async function updateName(
  name: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await send('/api/me', {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name }),
  });
  return { ok: res.ok, status: res.status };
}

/// Delete the account (parity 11.1 — definitive; the BFF ends the session).
export async function deleteAccount(): Promise<{
  ok: boolean;
  status: number;
  error?: string;
}> {
  const res = await send('/api/me', { method: 'DELETE' });
  if (res.ok) return { ok: true, status: res.status };
  // L2: 409 `future_bookings` is the one failure here a user can resolve, so
  // the code has to reach the UI. The pro twin (`lib/pro/account.ts`) has read
  // the body for exactly this reason since audit 11.5; the consumer one threw
  // it away and rendered « La suppression a échoué. Réessayez. » — advice that
  // is wrong, because retrying will fail identically until the booking is
  // cancelled.
  const body = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: body.error };
}

// --- notifications (parity 5.1/5.2) -----------------------------------------

export async function getNotifications(): Promise<{
  status: number;
  items: AppNotification[];
}> {
  const res = await send('/api/me/notifications');
  if (!res.ok) return { status: res.status, items: [] };
  const body = await readJson<{ items?: AppNotification[] }>(res);
  return body ? { status: 200, items: body.items ?? [] } : { status: 0, items: [] };
}

/// Both carry their status: the caller puts the notification back to unread
/// and tells « no network » from a refusal
/// (docs/design/web-consumer-optimistic-revert.md §3.3).
export async function markNotificationRead(
  id: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await send(`/api/me/notifications/${id}/read`, {
    method: 'POST',
  });
  return { ok: res.ok, status: res.status };
}

export async function markAllNotificationsRead(): Promise<{
  ok: boolean;
  status: number;
}> {
  const res = await send('/api/me/notifications/read-all', {
    method: 'POST',
  });
  return { ok: res.ok, status: res.status };
}

export async function getNotificationPrefs(): Promise<{
  status: number;
  prefs?: NotificationPrefs;
}> {
  const res = await send('/api/me/notification-preferences');
  if (!res.ok) return { status: res.status };
  const prefs = await readJson<NotificationPrefs>(res);
  return prefs ? { status: 200, prefs } : { status: 0 };
}

export async function updateNotificationPrefs(
  patch: Partial<NotificationPrefs>,
): Promise<{ ok: boolean; prefs?: NotificationPrefs }> {
  const res = await send('/api/me/notification-preferences', {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(patch),
  });
  if (!res.ok) return { ok: false };
  // A lost body keeps the toggle the person chose; the server has it.
  return { ok: true, prefs: await readJson<NotificationPrefs>(res) };
}

/// What a logout call came to — the pro `LogoutOutcome`. The session is
/// httpOnly cookies that only the BFF's RESPONSE can clear, so a caller treats
/// the session as ended on `'ok'` alone: `'offline'` (no answer) and
/// `'failed'` (an error status) both leave the cookies — and the session —
/// alive. It used to return nothing, and « Se déconnecter » went home without
/// looking: a signed-out-looking page over a live session, on a shared phone
/// or a cybercafé computer.
export type LogoutOutcome = 'ok' | 'offline' | 'failed';

export async function logout(): Promise<LogoutOutcome> {
  const res = await send('/api/auth/logout', { method: 'POST' });
  if (res.ok) return 'ok';
  return res.status === 0 ? 'offline' : 'failed';
}
