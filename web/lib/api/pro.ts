import type { Availability } from '../pro/availability';
import type { Artist, ArtistInput, Service, ServiceInput } from '../pro/catalogue';
import type { DepositPolicy } from '../pro/deposit';
import type { BeforeAfterPair } from '../pro/medias';
import type { Subscription } from '../pro/subscription-plans';
import type { ProAppointment } from '../pro/today';

export type DashboardStats = {
  todayAppointments?: number;
  pendingRequests?: number;
  todayRevenue?: number;
  weekRevenue?: number;
  monthRevenue?: number;
};

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
    description?: string;
    address?: string;
    commune?: string | null;
    city?: string | null;
    phoneNumber?: string;
    whatsapp?: string | null;
    services?: Service[];
    artists?: Artist[];
    availability?: Availability;
    imageUrls?: string[];
    beforeAfters?: BeforeAfterPair[];
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

/// Detail = find it in the provider list (GET /appointments/{id} is consumer-
/// scoped, so the salon's own list is the provider-scoped source).
export async function getProAppointment(
  id: string,
): Promise<{ status: number; appt?: ProAppointment }> {
  const r = await listProAppointments();
  if (r.status !== 200) return { status: r.status };
  const appt = r.items.find((a) => a.id === id);
  return appt ? { status: 200, appt } : { status: 404 };
}

export async function proAction(
  id: string,
  action: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await fetch(`/api/pro/appointments/${id}/${action}`, {
    method: 'POST',
  });
  if (res.ok) return { ok: true, status: res.status };
  const b = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: b.error };
}

export async function proDepositScreenshotUrl(id: string): Promise<string | null> {
  const res = await fetch(`/api/pro/appointments/${id}/deposit-screenshot`);
  if (!res.ok) return null;
  const b = (await res.json().catch(() => ({}))) as { url?: string };
  return b.url ?? null;
}

// --- catalogue: services (7.3a) ---------------------------------------------
// The client sends its own providerId; the backend enforces ownership.

type MutationResult = { ok: boolean; status: number; error?: string };

async function mutate(url: string, method: string, body?: unknown): Promise<MutationResult> {
  const res = await fetch(url, {
    method,
    headers: body ? { 'content-type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.ok) return { ok: true, status: res.status };
  const b = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: b.error };
}

export function createService(
  providerId: string,
  input: ServiceInput,
): Promise<MutationResult> {
  return mutate('/api/pro/catalogue/services', 'POST', { providerId, service: input });
}

export function updateService(
  providerId: string,
  serviceId: string,
  input: ServiceInput,
): Promise<MutationResult> {
  return mutate(`/api/pro/catalogue/services/${serviceId}`, 'PATCH', {
    providerId,
    service: input,
  });
}

export function deleteService(
  providerId: string,
  serviceId: string,
): Promise<MutationResult> {
  return mutate(
    `/api/pro/catalogue/services/${serviceId}?providerId=${encodeURIComponent(providerId)}`,
    'DELETE',
  );
}

// --- catalogue: artistes (7.3b) ---------------------------------------------

export function createArtist(
  providerId: string,
  input: ArtistInput,
): Promise<MutationResult> {
  return mutate('/api/pro/catalogue/artists', 'POST', { providerId, artist: input });
}

export function updateArtist(
  providerId: string,
  artistId: string,
  input: ArtistInput,
): Promise<MutationResult> {
  return mutate(`/api/pro/catalogue/artists/${artistId}`, 'PATCH', {
    providerId,
    artist: input,
  });
}

export function deleteArtist(
  providerId: string,
  artistId: string,
): Promise<MutationResult> {
  return mutate(
    `/api/pro/catalogue/artists/${artistId}?providerId=${encodeURIComponent(providerId)}`,
    'DELETE',
  );
}

// --- disponibilités (7.3c) ---------------------------------------------------

export function saveAvailability(
  providerId: string,
  availability: Availability,
): Promise<MutationResult> {
  return mutate('/api/pro/disponibilites', 'PUT', { providerId, availability });
}

// --- abonnement + tableau de bord (7.3d) ------------------------------------

export async function getSubscription(): Promise<{
  status: number;
  subscription?: Subscription;
}> {
  const res = await fetch('/api/pro/subscription');
  if (!res.ok) return { status: res.status };
  return { status: 200, subscription: (await res.json()) as Subscription };
}

export async function getDashboard(
  providerId: string,
): Promise<{ status: number; stats?: DashboardStats }> {
  const res = await fetch(
    `/api/pro/dashboard?providerId=${encodeURIComponent(providerId)}`,
  );
  if (!res.ok) return { status: res.status };
  return { status: 200, stats: (await res.json()) as DashboardStats };
}

// --- profil + acompte (7.3e-i) ----------------------------------------------

export function updateProviderProfile(
  providerId: string,
  fields: Record<string, unknown>,
): Promise<MutationResult> {
  return mutate('/api/pro/profil', 'PATCH', { providerId, profile: fields });
}

export async function getDepositPolicy(
  providerId: string,
): Promise<{ status: number; policy?: DepositPolicy }> {
  const res = await fetch(
    `/api/pro/acompte?providerId=${encodeURIComponent(providerId)}`,
  );
  if (!res.ok) return { status: res.status };
  return { status: 200, policy: (await res.json()) as DepositPolicy };
}

export function saveDepositPolicy(
  providerId: string,
  policy: DepositPolicy,
): Promise<MutationResult> {
  return mutate('/api/pro/acompte', 'PUT', { providerId, policy });
}

// --- médias (7.3e-ii) -------------------------------------------------------

export function saveGallery(
  providerId: string,
  imageUrls: string[],
): Promise<MutationResult> {
  return mutate('/api/pro/medias/gallery', 'PUT', { providerId, imageUrls });
}

export function saveBeforeAfters(
  providerId: string,
  beforeAfters: BeforeAfterPair[],
): Promise<MutationResult> {
  return mutate('/api/pro/medias/before-after', 'PUT', {
    providerId,
    beforeAfters,
  });
}

export async function logoutPro(): Promise<void> {
  await fetch('/api/pro/auth/logout', { method: 'POST' });
}
