import { readJson, send, sendIdempotent } from './network';
import type { Review } from './providers';
import type { KycStatus } from '../pro/kyc';
import type { Availability } from '../pro/availability';
import type {
  SalonClientCard,
  SalonClientList,
  SalonClientListItem,
  SalonClientNote,
} from '../pro/clients';
import type { Artist, ArtistInput, Service, ServiceInput } from '../pro/catalogue';
import type { DepositPolicy } from '../pro/deposit';
import type { BeforeAfterPair } from '../pro/medias';
import type { SalonOffer } from '../pro/subscription-plans';
import type {
  Membership,
  SalonMembership,
  TeamInvitation,
  TeamMember,
  TeamRoleInput,
} from '../pro/team';
import type { JournalDay } from '../pro/journal';
import type { ReviewSummary } from '../pro/reviews';
import type { ProAppointment } from '../pro/today';
import type { EarningsData } from '../pro/earnings';
import { wholeClientBase } from '../pro/export';
import type { AppNotification } from '../account/notifications';

export type DashboardStats = {
  todayAppointments?: number;
  pendingRequests?: number;
  todayRevenue?: number;
  weekRevenue?: number;
  monthRevenue?: number;
};

/// Browser → pro BFF (`/api/pro/*`) wrappers. Pro session lives in the pro
/// httpOnly cookies; a 401 means "not signed in" → redirect to /pro/connexion.
///
/// **None of them throws** (docs/design/web-pro-network-failure.md §2). A call
/// that never got a usable answer is **status 0** (`ok: false` for a write) —
/// and every page's « not 200 » branch is already its error state. Before,
/// a dropped connection rejected through the wrapper into a load that never
/// caught it, and the page stayed on its skeleton for ever. Every call goes
/// through the shared `send()` / `readJson()` of `./network`, as the consumer
/// wrappers do.

export type ProProfile = {
  account: {
    id: string;
    businessName: string;
    businessType?: string | null;
    phoneNumber: string;
    /// The signed-in identity (auth overhaul: verified email) — feeds the
    /// member identity block (team access R5b).
    email?: string | null;
    verificationStatus?: 'pending' | 'verified' | 'rejected';
    providerId?: string | null;
  };
  provider: {
    id: string;
    name: string;
    slug?: string;
    status?: 'draft' | 'active' | 'suspended';
    category?: string;
    latitude?: number | null;
    longitude?: number | null;
    description?: string;
    address?: string;
    commune?: string | null;
    city?: string | null;
    /// Multi-pays MP1 salon market fields (server-derived from the area —
    /// T57): the pro surfaces render THIS salon's clock + currency.
    areaId?: string | null;
    citySlug?: string | null;
    countryCode?: string | null;
    timezone?: string | null;
    currency?: string | null;
    phoneNumber?: string;
    whatsapp?: string | null;
    services?: Service[];
    artists?: Artist[];
    availability?: Availability;
    imageUrls?: string[];
    beforeAfters?: BeforeAfterPair[];
  };
  /// Team access R4a/R5: the caller's role + server-computed capabilities.
  membership?: Membership;
};

export async function requestOtpPro(
  phoneNumber: string,
): Promise<{ ok: boolean; devCode?: string; error?: string }> {
  const res = await send('/api/pro/auth/request-otp', {
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
  const res = await send('/api/pro/auth/verify', {
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
  /// Machine code on a non-2xx (team access R5b: `not_a_member` on a 403
  /// is the revoked-mid-session signal the membership probe acts on).
  error?: string;
}> {
  const res = await send('/api/pro/me');
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string };
    return { status: res.status, error: body.error };
  }
  const profile = await readJson<ProProfile>(res);
  return profile ? { status: 200, profile } : { status: 0 };
}

// --- « Mes salons » (module `access` R6) -----------------------------------

export async function getMySalons(): Promise<{
  status: number;
  items: SalonMembership[];
  canAddSalon: boolean;
}> {
  const res = await send('/api/pro/salons');
  if (!res.ok) return { status: res.status, items: [], canAddSalon: false };
  const body = await readJson<{
    items?: SalonMembership[];
    canAddSalon?: boolean;
  }>(res);
  if (!body) return { status: 0, items: [], canAddSalon: false };
  return {
    status: 200,
    items: body.items ?? [],
    canAddSalon: body.canAddSalon === true,
  };
}

/// « Ajouter un salon » — Réseau-gated server-side (403 `reseau_required`,
/// 409 `salon_limit`).
export async function addSalon(fields: {
  businessName: string;
  businessType: string;
  phoneNumber?: string;
  address?: string;
  /// Multi-pays MP3 — optional; the publish gate enforces (T57).
  areaId?: string | null;
}): Promise<{ ok: boolean; status: number; salon?: SalonMembership; error?: string }> {
  const res = await send('/api/pro/salons', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(fields),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok
    ? { ok: true, status: res.status, salon: body.salon as SalonMembership }
    : { ok: false, status: res.status, error: body.error };
}

/// Switch (or clear, with null) the acting salon. The BFF validates the
/// selection against the backend BEFORE setting the httpOnly cookie; a 200
/// returns the selected salon's /me/provider payload.
export async function selectSalon(salonId: string | null): Promise<{
  ok: boolean;
  status: number;
  profile?: ProProfile;
  error?: string;
}> {
  const res = await send('/api/pro/salons/select', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ salonId }),
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string };
    return { ok: false, status: res.status, error: body.error };
  }
  return {
    ok: true,
    status: res.status,
    profile: salonId === null ? undefined : await readJson<ProProfile>(res),
  };
}

/// The salon member's notification feed (docs/design/web-pro-notifications.md):
/// the consumer wrappers' shapes, on the pro session. Status 0 = no answer.
export async function getProNotifications(): Promise<{
  status: number;
  items: AppNotification[];
}> {
  const res = await send('/api/pro/notifications');
  if (!res.ok) return { status: res.status, items: [] };
  const body = await readJson<{ items?: AppNotification[] }>(res);
  return body ? { status: 200, items: body.items ?? [] } : { status: 0, items: [] };
}

/// Both carry their status: the caller puts the row back to unread and tells
/// « no network » from a refusal (web-consumer-optimistic-revert.md §3.3).
export async function markProNotificationRead(
  id: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await send(`/api/pro/notifications/${encodeURIComponent(id)}/read`, {
    method: 'POST',
  });
  return { ok: res.ok, status: res.status };
}

export async function markAllProNotificationsRead(): Promise<{
  ok: boolean;
  status: number;
}> {
  const res = await send('/api/pro/notifications/read-all', { method: 'POST' });
  return { ok: res.ok, status: res.status };
}

/// The member's « Alertes par e-mail » (docs/design/salon-email-alerts.md
/// §4) — the one preference web Pro shows. `emailAlerts` is absent when the
/// server does not send it (an API older than the switch): the page then
/// shows no switch rather than one that would save nothing. Status 0 = no
/// usable answer.
export type ProNotificationPrefs = { emailAlerts: boolean };

export async function getProNotificationPrefs(): Promise<{
  status: number;
  prefs?: ProNotificationPrefs;
}> {
  const res = await send('/api/pro/notification-preferences');
  if (!res.ok) return { status: res.status };
  const body = await readJson<{ emailAlerts?: unknown }>(res);
  if (!body) return { status: 0 };
  return typeof body.emailAlerts === 'boolean'
    ? { status: 200, prefs: { emailAlerts: body.emailAlerts } }
    : { status: 200 };
}

/// Carries its status: the switch goes back and tells « no network » from a
/// refusal. A lost 2xx body keeps the switch where the member put it.
export async function setProEmailAlerts(on: boolean): Promise<{
  ok: boolean;
  status: number;
  prefs?: ProNotificationPrefs;
}> {
  const res = await send('/api/pro/notification-preferences', {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ emailAlerts: on }),
  });
  if (!res.ok) return { ok: false, status: res.status };
  const body = await readJson<{ emailAlerts?: unknown }>(res);
  return typeof body?.emailAlerts === 'boolean'
    ? { ok: true, status: res.status, prefs: { emailAlerts: body.emailAlerts } }
    : { ok: true, status: res.status };
}

/// This browser's notification token on the member's Pro session
/// (docs/design/web-pro-browser-push.md §5) — the BFF says `web`.
export async function registerProDevice(token: string): Promise<{ ok: boolean; status: number }> {
  const res = await send('/api/pro/devices', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ token }),
  });
  return { ok: res.ok, status: res.status };
}

/// Forget this browser's token — the switch turned off, or a sign-out.
export async function unregisterProDevice(token: string): Promise<{ ok: boolean; status: number }> {
  const res = await send('/api/pro/devices', {
    method: 'DELETE',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ token }),
  });
  return { ok: res.ok, status: res.status };
}

export async function listProAppointments(): Promise<{
  status: number;
  items: ProAppointment[];
}> {
  const res = await send('/api/pro/appointments');
  if (!res.ok) return { status: res.status, items: [] };
  // The server always sends `items`: a 200 without the list is a failed read
  // (status 0) — the salon export refuses, « Aujourd'hui » and
  // « Rendez-vous » show their error — never « aucun rendez-vous » nobody sent
  // (docs/design/export-unreadable-200.md §2.2).
  const items = (await readJson<{ items?: unknown }>(res))?.items;
  return Array.isArray(items)
    ? { status: 200, items: items as ProAppointment[] }
    : { status: 0, items: [] };
}

/// Take the salon live (docs/design/pro-salon-lifecycle.md). 409 returns the
/// server's missing checklist keys.
export async function publishSalon(providerId: string): Promise<{
  ok: boolean;
  status: number;
  missing?: string[];
  /// The refusal's code — `demo_account_locked`, `provider_suspended` — so the
  /// card can name it (docs/design/web-pro-truthful-failure.md §2.3).
  error?: string;
}> {
  const res = await send('/api/pro/publish', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ providerId }),
  });
  if (res.ok) return { ok: true, status: res.status };
  const body = (await res.json().catch(() => ({}))) as {
    missing?: string[];
    error?: string;
  };
  return { ok: false, status: res.status, missing: body.missing, error: body.error };
}

/// The signed-in provider's KYC (docs/design/web-pro-kyc.md).
export async function getKycStatus(): Promise<{
  status: number;
  kyc?: KycStatus;
}> {
  const res = await send('/api/pro/kyc');
  if (!res.ok) return { status: res.status };
  const kyc = await readJson<KycStatus>(res);
  return kyc ? { status: 200, kyc } : { status: 0 };
}

export async function submitKyc(
  documents: { type: string; fileName?: string; key: string }[],
): Promise<{ status: number; kyc?: KycStatus }> {
  const res = await send('/api/pro/kyc', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ documents }),
  });
  if (!res.ok) return { status: res.status };
  return { status: 200, kyc: await readJson<KycStatus>(res) };
}

/// The salon's reviews page (« Avis » — docs/design/web-pro-reviews.md).
export async function listProviderReviews(
  providerId: string,
  page = 1,
): Promise<{
  status: number;
  items: Review[];
  total: number;
  pageSize: number;
  /// The whole salon's card (salon-reviews-summary.md); absent from a server
  /// older than it.
  summary?: ReviewSummary;
}> {
  // `providerId` is the R6 SELECTOR, not the authority: upstream resolves the
  // salon from the token and refuses a selection the caller is not a member of
  // (T55). It used to be the only thing naming the salon, on a public route.
  const res = await send(
    `/api/pro/reviews?salonId=${encodeURIComponent(providerId)}&page=${page}`,
  );
  if (!res.ok) return { status: res.status, items: [], total: 0, pageSize: 0 };
  const body = await readJson<{
    items?: Review[];
    total?: number;
    pageSize?: number;
    summary?: ReviewSummary;
  }>(res);
  if (!body) return { status: 0, items: [], total: 0, pageSize: 0 };
  return {
    status: 200,
    items: body.items ?? [],
    total: body.total ?? 0,
    pageSize: body.pageSize ?? 50,
    ...(body.summary ? { summary: body.summary } : {}),
  };
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
  const res = await send(`/api/pro/appointments/${id}/${action}`, {
    method: 'POST',
  });
  if (res.ok) return { ok: true, status: res.status };
  const b = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: b.error };
}

/// The salon reports a review of its own salon (B6.6 —
/// docs/design/backend-integrity-batch6.md §2.6): the same moderation queue
/// as a client's report, marked « Signalé par le salon ». Status 0 = no
/// answer (the wrapper never throws).
export async function reportSalonReview(
  reviewId: string,
  reason: string,
): Promise<{ ok: boolean; status: number }> {
  const res = await send(`/api/pro/reviews/${encodeURIComponent(reviewId)}/report`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(reason.trim() ? { reason: reason.trim() } : {}),
  });
  return { ok: res.ok, status: res.status };
}

/// The short-lived signed URL of a booking's deposit screenshot. A read like
/// the others (docs/design/web-pro-journal-panel-deposit.md §5): status 0 when
/// nothing usable came back — a 200 without a URL included — so the screen can
/// tell a cut connection from a refusal. It used to fold every failure into
/// `null`, and the detail page's button then did nothing at all.
export async function proDepositScreenshotUrl(
  id: string,
): Promise<{ status: number; url?: string }> {
  const res = await send(`/api/pro/appointments/${id}/deposit-screenshot`);
  if (!res.ok) return { status: res.status };
  const b = await readJson<{ url?: string }>(res);
  return b?.url ? { status: 200, url: b.url } : { status: 0 };
}

// --- catalogue: services (7.3a) ---------------------------------------------
// The client sends its own providerId; the backend enforces ownership.

type MutationResult = { ok: boolean; status: number; error?: string };

async function mutate(url: string, method: string, body?: unknown): Promise<MutationResult> {
  const res = await send(url, {
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

/// Team access R5a: create an employee fiche and get it back, for the invite
/// dialog's inline « Créer une fiche » (which must then select the new id).
export async function createArtistReturning(
  providerId: string,
  input: ArtistInput,
): Promise<{ ok: boolean; status: number; artist?: Artist; error?: string }> {
  const res = await send('/api/pro/catalogue/artists', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ providerId, artist: input }),
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string };
    return { ok: false, status: res.status, error: body.error };
  }
  return { ok: true, status: res.status, artist: await readJson<Artist>(res) };
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

/// The salon's offer state (team access R5a). 404 = the free SETUP state
/// (no offer chosen yet) — a valid state, not an error.
export async function getSalonSubscription(providerId: string): Promise<{
  status: number;
  offer?: SalonOffer;
}> {
  const res = await send(
    `/api/pro/salon-subscription?providerId=${encodeURIComponent(providerId)}`,
  );
  if (!res.ok) return { status: res.status };
  const offer = await readJson<SalonOffer>(res);
  return offer ? { status: 200, offer } : { status: 0 };
}

/// Pick/switch the offer (first choice starts the ONE 3-month trial;
/// switches keep the clock; 409 → `trial_used`).
export async function chooseOffer(
  providerId: string,
  tier: 'pro' | 'business' | 'reseau',
): Promise<{ ok: boolean; status: number; offer?: SalonOffer; error?: string }> {
  const res = await send('/api/pro/salon-subscription', {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ providerId, tier }),
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string };
    return { ok: false, status: res.status, error: body.error };
  }
  return { ok: true, status: res.status, offer: await readJson<SalonOffer>(res) };
}

export async function getDashboard(
  providerId: string,
): Promise<{ status: number; stats?: DashboardStats }> {
  const res = await send(
    `/api/pro/dashboard?providerId=${encodeURIComponent(providerId)}`,
  );
  if (!res.ok) return { status: res.status };
  const stats = await readJson<DashboardStats>(res);
  return stats ? { status: 200, stats } : { status: 0 };
}

// --- compte (audit 11.5) --------------------------------------------------------

/// Delete the provider account (AUTH-004 for pros). 409 `future_bookings`
/// when the agenda isn't settled; 403 `demo_account_locked` for the shared
/// store-review demo account (nothing is deleted, the session stays —
/// docs/design/demo-account-deletion-lock.md); success ends the pro session.
export async function deleteProAccount(): Promise<{
  ok: boolean;
  status: number;
  error?: string;
}> {
  const res = await send('/api/pro/account', { method: 'DELETE' });
  if (res.ok) return { ok: true, status: res.status };
  const body = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: body.error };
}

// --- revenus (parity 9.1) -----------------------------------------------------

export async function getEarnings(
  providerId: string,
  range: { startDate: string; endDate: string } | null,
): Promise<{ status: number; earnings?: EarningsData }> {
  const qs = new URLSearchParams({ providerId });
  if (range) {
    qs.set('startDate', range.startDate);
    qs.set('endDate', range.endDate);
  }
  const res = await send(`/api/pro/earnings?${qs.toString()}`);
  if (!res.ok) return { status: res.status };
  // The server always sends `totalEarnings` and the `transactions` list. A
  // 200 without them is a failed read (status 0), not « earnings »: `{}`
  // crashed the Revenus page and the export, `transactions: "x"` was
  // exported as one (docs/design/export-unreadable-200.md §2.2).
  const earnings = await readJson<Partial<EarningsData>>(res);
  return Array.isArray(earnings?.transactions) &&
    typeof earnings.totalEarnings === 'number'
    ? { status: 200, earnings: earnings as EarningsData }
    : { status: 0 };
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
  const res = await send(
    `/api/pro/acompte?providerId=${encodeURIComponent(providerId)}`,
  );
  if (!res.ok) return { status: res.status };
  const policy = await readJson<DepositPolicy>(res);
  return policy ? { status: 200, policy } : { status: 0 };
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

/// What a logout call came to. The session is two httpOnly cookies that only
/// the BFF's RESPONSE can clear, so a caller treats the session as ended on
/// `'ok'` alone: `'offline'` (the request never got an answer) and `'failed'`
/// (an error status) both leave the cookies — and the 30-day session — alive.
export type LogoutOutcome = 'ok' | 'offline' | 'failed';

export async function logoutPro(): Promise<LogoutOutcome> {
  try {
    const res = await fetch('/api/pro/auth/logout', { method: 'POST' });
    return res.ok ? 'ok' : 'failed';
  } catch {
    return 'offline';
  }
}

// --- Auth overhaul P4 (docs/design/pro-auth-social.md) -----------------------

export async function loginProWithGoogle(idToken: string): Promise<{
  ok: boolean;
  error?: string;
  /// Team access R5a: the 202 bridge — pending invitations, no session yet.
  invitations?: TeamInvitation[];
}> {
  const res = await send('/api/pro/auth/google', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ idToken }),
  });
  const body = await res.json().catch(() => ({}));
  if (res.status === 202 && Array.isArray(body.invitations)) {
    return { ok: false, invitations: body.invitations as TeamInvitation[] };
  }
  return res.ok ? { ok: true } : { ok: false, error: body.error };
}

/// Sign in with Apple (docs/design/web-pro-apple.md). No 202 bridge on the
/// Apple route (contract — the app notes it too), so no invitations here.
export async function loginProWithApple(identity: {
  identityToken: string;
  nonce: string;
  /// Apple's one-time code (B6.7 — docs/design/backend-integrity-batch6.md §13).
  authorizationCode?: string;
}): Promise<{ ok: boolean; error?: string }> {
  const res = await send('/api/pro/auth/apple', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      identityToken: identity.identityToken,
      nonce: identity.nonce,
      ...(identity.authorizationCode ? { authorizationCode: identity.authorizationCode } : {}),
    }),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok ? { ok: true } : { ok: false, error: body.error };
}

/// `status` 0 = no answer: the login says « Pas de connexion », never a
/// wrong e-mail or code it did not get to judge.
export async function requestEmailOtpPro(
  email: string,
): Promise<{ ok: boolean; status: number; devCode?: string; error?: string }> {
  const res = await send('/api/pro/auth/email/request', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email }),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok
    ? { ok: true, status: res.status, devCode: body.devCode }
    : { ok: false, status: res.status, error: body.error };
}

export async function verifyEmailOtpPro(
  email: string,
  code: string,
): Promise<{
  ok: boolean;
  status: number;
  error?: string;
  invitations?: TeamInvitation[];
}> {
  const res = await send('/api/pro/auth/email/verify', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, code }),
  });
  const body = await res.json().catch(() => ({}));
  if (res.status === 202 && Array.isArray(body.invitations)) {
    // The code stays UNCONSUMED server-side — the accept call reuses it.
    return {
      ok: false,
      status: res.status,
      invitations: body.invitations as TeamInvitation[],
    };
  }
  return res.ok
    ? { ok: true, status: res.status }
    : { ok: false, status: res.status, error: body.error };
}

// --- Team access R5a: the public (login-proof) invitation accept/decline ----

export async function acceptInvitationPublic(input: {
  invitationId: string;
  idToken?: string;
  email?: string;
  code?: string;
}): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await send('/api/pro/auth/invitations/accept', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(input),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok
    ? { ok: true, status: res.status }
    : { ok: false, status: res.status, error: body.error };
}

export async function declineInvitationPublic(input: {
  invitationId: string;
  idToken?: string;
  email?: string;
  code?: string;
}): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await send('/api/pro/auth/invitations/decline', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(input),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok
    ? { ok: true, status: res.status }
    : { ok: false, status: res.status, error: body.error };
}

// --- Team access R5a: the Équipe surface (owner) + authed invitations -------

export async function getTeamMembers(): Promise<{
  status: number;
  items: TeamMember[];
}> {
  const res = await send('/api/pro/members');
  if (!res.ok) return { status: res.status, items: [] };
  const body = await readJson<{ items?: TeamMember[] }>(res);
  return body ? { status: 200, items: body.items ?? [] } : { status: 0, items: [] };
}

type MemberResult = { ok: boolean; status: number; member?: TeamMember; error?: string };

/// A roster write's answer: the member row it returns, or the refusal's code.
async function memberResult(res: Response): Promise<MemberResult> {
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string };
    return { ok: false, status: res.status, error: body.error };
  }
  return { ok: true, status: res.status, member: await readJson<TeamMember>(res) };
}

/// Under [key], one per submission (docs/design/write-idempotency.md §4): a
/// lost answer is asked again once with it — the invitation and its e-mail
/// went once, and the replay is never `member_exists`.
export async function inviteMember(
  input: { email: string; role: TeamRoleInput; artistId?: string },
  key: string,
  opts: { wait?: (ms: number) => Promise<void> } = {},
): Promise<MemberResult> {
  const r = await sendIdempotent<TeamMember>(
    '/api/pro/members',
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(input),
    },
    key,
    { complete: (b) => Boolean(b?.id), ...opts },
  );
  if (r.status < 200 || r.status >= 300) {
    return { ok: false, status: r.status, error: r.error };
  }
  return { ok: true, status: r.status, member: r.body };
}

export async function changeMemberRole(
  memberId: string,
  input: { role: TeamRoleInput; artistId?: string },
): Promise<MemberResult> {
  return memberResult(
    await send(`/api/pro/members/${encodeURIComponent(memberId)}`, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(input),
    }),
  );
}

export async function revokeMember(memberId: string): Promise<MemberResult> {
  return memberResult(
    await send(`/api/pro/members/${encodeURIComponent(memberId)}/revoke`, {
      method: 'POST',
    }),
  );
}

export async function resendInvitation(memberId: string): Promise<MemberResult> {
  return memberResult(
    await send(`/api/pro/members/${encodeURIComponent(memberId)}/resend`, {
      method: 'POST',
    }),
  );
}

export async function getMyInvitations(): Promise<{
  status: number;
  invitations: TeamInvitation[];
}> {
  const res = await send('/api/pro/invitations');
  if (!res.ok) return { status: res.status, invitations: [] };
  const body = await readJson<{ invitations?: TeamInvitation[] }>(res);
  return body
    ? { status: 200, invitations: body.invitations ?? [] }
    : { status: 0, invitations: [] };
}

export async function acceptMyInvitation(
  invitationId: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await send(
    `/api/pro/invitations/${encodeURIComponent(invitationId)}/accept`,
    { method: 'POST' },
  );
  const body = await res.json().catch(() => ({}));
  return res.ok
    ? { ok: true, status: res.status }
    : { ok: false, status: res.status, error: body.error };
}

export async function declineMyInvitation(
  invitationId: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await send(
    `/api/pro/invitations/${encodeURIComponent(invitationId)}/decline`,
    { method: 'POST' },
  );
  const body = await res.json().catch(() => ({}));
  return res.ok
    ? { ok: true, status: res.status }
    : { ok: false, status: res.status, error: body.error };
}


// --- clients: the salon client base (module clients C1b) --------------------
// Reads are audited server-side; the backend enforces ownership (T45/T46).

export async function listClients(
  providerId: string,
  opts: { query?: string; tag?: string; page?: number; pageSize?: number } = {},
): Promise<{ status: number; list?: SalonClientList }> {
  const qs = new URLSearchParams({ providerId });
  if (opts.query) qs.set('query', opts.query);
  if (opts.tag) qs.set('tag', opts.tag);
  if (opts.page) qs.set('page', String(opts.page));
  if (opts.pageSize) qs.set('pageSize', String(opts.pageSize));
  const res = await send(`/api/pro/clients?${qs}`);
  if (!res.ok) return { status: res.status };
  const list = await readJson<SalonClientList>(res);
  return list ? { status: 200, list } : { status: 0 };
}

/// The server's largest page (`ClientsService.list` clamps to 50).
const CLIENT_WALK_PAGE_SIZE = 50;

/// EVERY client of the salon, for the data export
/// (docs/design/web-pro-export-completeness.md §5) — not the first page,
/// which is all `listClients` returns. Pages are read one after another.
/// `items` is set only when the walk is whole (`wholeClientBase`). A failed
/// page returns its status; a walk that does not add up returns 200 without
/// `items`.
export async function listAllClients(
  providerId: string,
): Promise<{ status: number; items?: SalonClientListItem[] }> {
  const first = await listClients(providerId, {
    page: 1,
    pageSize: CLIENT_WALK_PAGE_SIZE,
  });
  if (!first.list) return { status: first.status };
  const pages = [first.list];
  // The server's page size, not ours: it is the one the offsets used.
  const size = first.list.pageSize;
  if (!(size > 0)) return { status: 200 };
  const count = Math.ceil(first.list.total / size);
  for (let page = 2; page <= count; page++) {
    const next = await listClients(providerId, { page, pageSize: size });
    if (!next.list) return { status: next.status };
    pages.push(next.list);
  }
  const items = wholeClientBase(pages);
  return items ? { status: 200, items } : { status: 200 };
}

export async function addClient(
  providerId: string,
  input: { name: string; phone: string; note?: string },
): Promise<{
  ok: boolean;
  status: number;
  clientId?: string;
  error?: string;
}> {
  const res = await send('/api/pro/clients', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ providerId, ...input }),
  });
  const b = (await res.json().catch(() => ({}))) as {
    id?: string;
    clientId?: string;
    error?: string;
  };
  if (res.ok) return { ok: true, status: res.status, clientId: b.id };
  // 409 client_exists carries the existing card's id.
  return { ok: false, status: res.status, clientId: b.clientId, error: b.error };
}

export async function getClientCard(
  providerId: string,
  clientId: string,
): Promise<{ status: number; card?: SalonClientCard }> {
  const res = await send(
    `/api/pro/clients/${clientId}?providerId=${encodeURIComponent(providerId)}`,
  );
  if (!res.ok) return { status: res.status };
  const card = await readJson<SalonClientCard>(res);
  return card ? { status: 200, card } : { status: 0 };
}

export async function getClientVisits(
  providerId: string,
  clientId: string,
  page = 1,
): Promise<{ status: number; items: ProAppointment[]; total: number }> {
  const res = await send(
    `/api/pro/clients/${clientId}/visits?providerId=${encodeURIComponent(providerId)}&page=${page}`,
  );
  if (!res.ok) return { status: res.status, items: [], total: 0 };
  const b = await readJson<{ items?: ProAppointment[]; total?: number }>(res);
  if (!b) return { status: 0, items: [], total: 0 };
  return { status: 200, items: b.items ?? [], total: b.total ?? 0 };
}

export async function updateClientTags(
  providerId: string,
  clientId: string,
  tags: string[],
): Promise<MutationResult> {
  return mutate(`/api/pro/clients/${clientId}`, 'PATCH', { providerId, tags });
}

/// A GUEST card's number (docs/design/phone-leftovers.md §8) — the salon's
/// manual appointments on the old number follow it server-side. Send the
/// NORMALIZED number (`normalizePhone`). Refusals: 400 `invalid_phone`;
/// 409 `client_exists` + the `clientId` of the card that holds it; 409
/// `client_linked` (a linked card keeps the account's number).
export async function updateClientPhone(
  providerId: string,
  clientId: string,
  phone: string,
): Promise<MutationResult & { clientId?: string }> {
  const res = await send(`/api/pro/clients/${clientId}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ providerId, phone }),
  });
  if (res.ok) return { ok: true, status: res.status };
  const b = (await res.json().catch(() => ({}))) as {
    error?: string;
    clientId?: string;
  };
  return { ok: false, status: res.status, error: b.error, clientId: b.clientId };
}

/// Under [key], one per submission (docs/design/write-idempotency.md §4): a
/// lost answer — or a 2xx without the note — is asked again once with it,
/// so the note is added once and shows once.
export async function addClientNote(
  providerId: string,
  clientId: string,
  body: string,
  key: string,
  opts: { wait?: (ms: number) => Promise<void> } = {},
): Promise<{ ok: boolean; status: number; note?: SalonClientNote }> {
  const r = await sendIdempotent<SalonClientNote>(
    `/api/pro/clients/${clientId}/notes`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ providerId, body }),
    },
    key,
    { complete: (b) => Boolean(b?.id), ...opts },
  );
  if (r.status < 200 || r.status >= 300) return { ok: false, status: r.status };
  return { ok: true, status: r.status, note: r.body };
}

export async function deleteClientNote(
  providerId: string,
  clientId: string,
  noteId: string,
): Promise<MutationResult> {
  return mutate(
    `/api/pro/clients/${clientId}/notes/${noteId}?providerId=${encodeURIComponent(providerId)}`,
    'DELETE',
  );
}


// --- journal grid (module journal J1) ---------------------------------------

export async function getJournalDay(
  providerId: string,
  date: string,
): Promise<{ status: number; day?: JournalDay }> {
  const res = await send(
    `/api/pro/journal?providerId=${encodeURIComponent(providerId)}&date=${date}`,
  );
  if (!res.ok) return { status: res.status };
  const day = await readJson<JournalDay>(res);
  return day ? { status: 200, day } : { status: 0 };
}

/// Drag-reschedule (+ optional column change). 409 = slot taken.
export async function rescheduleAppointment(
  id: string,
  newDateTime: string,
  artistId?: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await send(`/api/pro/appointments/${id}/reschedule`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ newDateTime, ...(artistId ? { artistId } : {}) }),
  });
  if (res.ok) return { ok: true, status: res.status };
  const b = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: b.error };
}

export async function arriveAppointment(
  id: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  return proAction(id, 'arrive');
}

/// Quick-create a manual booking (server-priced, arrives confirmed).
export async function createManualBooking(
  providerId: string,
  input: {
    serviceIds: string[];
    appointmentDateTime: string;
    artistId?: string;
    clientName?: string;
    clientPhone?: string;
    notes?: string;
    sendSmsInvite?: boolean;
  },
  key: string,
  opts: { wait?: (ms: number) => Promise<void> } = {},
): Promise<{ ok: boolean; status: number; appt?: ProAppointment; error?: string }> {
  // Under [key], one per submission (docs/design/write-idempotency.md §4): a
  // lost answer is asked again once with it — one booking, never a 409 on
  // the slot the salon just took.
  const r = await sendIdempotent<ProAppointment>(
    '/api/pro/appointments',
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ providerId, ...input }),
    },
    key,
    { complete: (b) => Boolean(b?.id), ...opts },
  );
  if (r.status >= 200 && r.status < 300) {
    return { ok: true, status: r.status, appt: r.body };
  }
  return { ok: false, status: r.status, error: r.error };
}


// --- salon registration (docs/design/web-pro-registration.md) ---------------

export type ProRegisterFields = {
  businessName: string;
  businessType: string;
  phoneNumber: string;
  address?: string;
  /// Multi-pays MP3: the picked locality area — optional at registration
  /// (the publish gate enforces a valid area, T57).
  areaId?: string | null;
};

/// Identity + business fields in ONE submit (201 → pro cookies set by the
/// BFF). Pass EITHER `idToken` (Google) or `email`+`code`.
export async function registerPro(
  identity: {
    idToken?: string;
    identityToken?: string;
    nonce?: string;
    fullName?: string;
    /// Apple's one-time code (B6.7).
    authorizationCode?: string;
    email?: string;
    code?: string;
  },
  fields: ProRegisterFields,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await send('/api/pro/auth/register', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ...identity, ...fields }),
  });
  if (res.ok) return { ok: true, status: res.status };
  const b = (await res.json().catch(() => ({}))) as { error?: string };
  return { ok: false, status: res.status, error: b.error };
}
