// Minimal stub of the Myweli API for hermetic web e2e — the Next server fetches
// it server-side, so this replaces the dart_frog backend (no DB/network needed).
// Started by playwright.config.ts; serves one provider + the sitemap feed.
import { createServer } from 'node:http';

const port = Number(process.env.STUB_PORT ?? 8787);

const provider = {
  id: 'p1',
  slug: 'beaute-divine',
  name: 'Beauté Divine',
  description: 'Salon de coiffure à Cocody.',
  address: 'Rue des Jardins, Cocody',
  city: 'Abidjan',
  commune: 'Cocody',
  latitude: 5.35,
  longitude: -3.99,
  imageUrls: ['https://cdn.stub/p1.jpg', 'https://cdn.stub/p2.jpg'],
  beforeAfters: [
    { before: 'https://cdn.stub/b1.jpg', after: 'https://cdn.stub/a1.jpg', caption: 'Belle transformation' },
  ],
  rating: 4.8,
  reviewCount: 2,
  phoneNumber: '+2250700000000',
  whatsapp: '+2250700000000',
  category: 'salon',
  verified: true,
  depositRequired: false,
  depositPercentage: 0,
  cancellationWindowHours: 24,
  services: [
    {
      id: 's1',
      name: 'Tresses',
      description: '',
      price: 15000,
      priceMax: 25000,
      durationMinutes: 120,
      durationVariants: { court: 90, moyen: 120, long: 180 },
      providerId: 'p1',
      active: true,
    },
    {
      // K2: restricted to Awa — exercises the capability dim/drop rules.
      id: 's2',
      name: 'Soin visage',
      description: '',
      price: 5000,
      durationMinutes: 30,
      artistIds: ['a1'],
      providerId: 'p1',
      active: true,
    },
  ],
  artists: [
    { id: 'a1', name: 'Awa', specialization: 'Tresses', providerId: 'p1' },
    { id: 'a2', name: 'Binta', specialization: 'Coiffure', providerId: 'p1' },
  ],
  availability: {
    providerId: 'p1',
    weeklySchedule: { '0': [{ startTime: '09:00', endTime: '18:00' }] },
    blockedDates: [],
    bufferMinutes: 0,
  },
  reviews: [
    {
      id: 'r1',
      providerId: 'p1',
      userId: 'u1',
      userName: 'Awa',
      photoUrls: ['https://cdn.stub/review/u1/seed.jpg'],
      rating: 5,
      text: 'Service impeccable.',
      createdAt: '2026-06-01T10:00:00.000Z',
    },
  ],
};

// Web KYC (web-pro-kyc.md) — mutable status + submitted docs.
const kycState = { status: 'pending', documents: [], rejectionReason: null };

// K2: a deposit-required salon for the pay-later proof-upload journey.
const depositProvider = {
  ...JSON.parse(JSON.stringify(provider)),
  id: 'p2',
  slug: 'institut-acompte',
  name: 'Institut Acompte',
  depositRequired: true,
  depositPercentage: 0.5,
  depositMobileMoneyOperator: 'Orange Money',
  depositMobileMoneyNumber: '+2250701020304',
};

function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

// Dated "today" (UTC) so the pro views show it whenever the suite runs.
const todayAt9 = `${new Date().toISOString().slice(0, 10)}T09:00:00.000Z`;
// Consumer bookings sit TOMORROW so future-only actions (« Reporter ») show.
const tomorrowAt9 = `${new Date(Date.now() + 86400000)
  .toISOString()
  .slice(0, 10)}T09:00:00.000Z`;

// Consumer side (M5/M6) — appt1; cancel is stateful.
const cancelled = new Set();

// Auth-overhaul consumer identity (email login; phone = contact attribute).
const stubUser = {
  id: 'u1',
  name: 'Awa',
  email: 'awa@example.com',
  authProvider: 'email',
  phoneNumber: '+2250700000000',
  phoneVerified: false,
};
// Notifications (parity 5.1/5.2): n1 starts unread; prefs default all-true.
const notifRead = new Set(['n2']);
const notifPrefs = { reminders: true, marketing: true, push: true };
const NOTIFS = [
  {
    id: 'n1',
    type: 'bookingConfirmed',
    title: 'Rendez-vous confirmé',
    body: 'Beauté Divine a confirmé votre rendez-vous.',
    createdAt: todayAt9,
    route: '/bookings',
  },
  {
    id: 'n2',
    type: 'general',
    title: 'Bienvenue sur MyWeli',
    body: 'Réservez vos soins en quelques clics.',
    createdAt: '2026-06-01T10:00:00.000Z',
    route: null,
  },
];

// Earnings ledger (parity 9.1): one transaction today, one at TODAY 23:30 —
// the salon-day boundary probe (timezone-salon-time.md §8: it must land in
// « Aujourd'hui » under the TZ-pinned harness; device-local bucketing used
// to drop it on non-UTC machines) — and one older.
const todayAt2330 = `${todayAt9.slice(0, 10)}T23:30:00.000Z`;
const EARN_TX = [
  { id: 't1', appointmentId: 'e1', amount: 15000, date: todayAt9, status: 'completed' },
  { id: 't3', appointmentId: 'e3', amount: 2000, date: todayAt2330, status: 'completed' },
  {
    id: 't2',
    appointmentId: 'e2',
    amount: 20000,
    date: '2026-06-05T14:00:00.000Z',
    status: 'completed',
  },
];

const consumerAppt = (id) => ({
  id,
  userId: 'u1',
  providerId: 'p1',
  serviceIds: ['s1'],
  clientName: 'Awa',
  // P3: the chosen spécialiste (1.8) + the booking note (1.4).
  artistId: 'a1',
  notes: 'Cheveux fragiles',
  appointmentDate: tomorrowAt9,
  status:
    id === 'appt2'
      ? 'completed'
      : id === 'appt3'
        ? 'pending'
        : cancelled.has(id)
          ? 'cancelled'
          : 'confirmed',
  totalPrice: 15000,
  // appt3: pending WITH an attached proof (1.3 « Voir ma capture »).
  depositAmount: id === 'appt3' ? 5000 : 0,
  depositScreenshotUrl:
    id === 'appt3' ? 'https://cdn.stub/deposit/u1/proof.jpg' : null,
  balanceDue: id === 'appt3' ? 10000 : 15000,
  cancellationWindowHours: 24,
});

// Pro side (M7) — pappt1, mutable status via the lifecycle endpoints. Kept
// separate from the consumer flow (split by token below) so parallel tests
// don't race on shared state.
const proStatus = { pappt1: 'pending', pj1: 'pending', pstaff1: 'confirmed' };
const PRO_TRANSITION = {
  accept: 'confirmed',
  reject: 'cancelled',
  complete: 'completed',
  'no-show': 'noShow',
};
const proAppt = (id) => ({
  id,
  userId: 'u2',
  providerId: 'p1',
  serviceIds: ['s1'],
  clientName: 'Koffi',
  appointmentDate: todayAt9,
  status: proStatus[id] ?? 'pending',
  totalPrice: 15000,
  depositAmount: 0,
  balanceDue: 15000,
  cancellationWindowHours: 24,
  depositScreenshotUrl: null,
  // Module clients C1: provider-view enrichment (badge + card link).
  salonClientId: 'sc1',
  clientNoShowCount: 2,
  // Journal J1: column, duration, in-day arrival. pstaff1 (team access
  // R5b) is PERMANENTLY the member's own row (artist-a / Awa).
  artistId: id === 'pstaff1' || proArrived[id] ? 'artist-a' : null,
  durationMinutes: 60,
  arrivedAt: proArrived[id] || null,
});
const proArrived = {};

// Module clients C1b — the salon client base (mutable for add/notes/tags).
const salonClients = [
  {
    id: 'sc1',
    displayName: 'Koffi',
    phone: '+2250700000001',
    tags: ['VIP'],
    lastVisitAt: todayAt9,
    linked: true,
    createdAt: todayAt9,
    visits: 3,
    noShows: 2,
  },
  {
    id: 'sc2',
    displayName: 'Aminata',
    phone: '+2250700000002',
    tags: [],
    lastVisitAt: null,
    linked: false,
    createdAt: todayAt9,
    visits: 0,
    noShows: 0,
  },
];
const clientNotes = { sc1: [], sc2: [] };
let clientSeq = 3;
const isPro = (req) => (req.headers.authorization || '').includes('pro');

// --- team access R5b: per-role sessions -----------------------------------
// Member logins get role tokens; everything else (stub-pro-access, pro-access,
// the bridge session) stays OWNER-shaped so the pre-R5b e2e are untouched.
// NB: a refresh would rotate to the owner token (pro-access-2) — irrelevant
// here because a 403 never triggers the BFF refresh (401 only).
function roleOf(req) {
  const auth = req.headers.authorization || '';
  if (auth.includes('pro-manager-access')) return 'manager';
  if (auth.includes('pro-reception-access')) return 'reception';
  if (auth.includes('pro-staff-access')) return 'staff';
  if (auth.includes('pro-revoked-access')) return 'revoked';
  return 'owner';
}
// The backend preset matrix (capabilities.dart rolePresets), verbatim.
const ROLE_CAPS = {
  owner: [
    'availability.manage',
    'catalogue.manage',
    'clients.view',
    'deposit.manage',
    'finances.view',
    'journal.manage.all',
    'journal.manage.own',
    'journal.view.all',
    'journal.view.own',
    'members.manage',
    'profile.manage',
    'salon.publish',
    'subscription.manage',
  ],
  manager: [
    'availability.manage',
    'catalogue.manage',
    'clients.view',
    'journal.manage.all',
    'journal.manage.own',
    'journal.view.all',
    'journal.view.own',
    'profile.manage',
  ],
  reception: [
    'clients.view',
    'journal.manage.all',
    'journal.manage.own',
    'journal.view.all',
    'journal.view.own',
  ],
  staff: ['journal.manage.own', 'journal.view.own'],
};
// Login email → role (code 123456). revoked.staff logs in fine but every
// /me/provider probe 403s not_a_member — the revoked-mid-session journey.
const MEMBER_LOGINS = {
  'awa.manager@equipe.test': 'manager',
  'fatou.reception@equipe.test': 'reception',
  'sonia.staff@equipe.test': 'staff',
  'revoked.staff@equipe.test': 'revoked',
};
const MEMBER_EMAILS = {
  owner: 'salon@example.com',
  manager: 'awa.manager@equipe.test',
  reception: 'fatou.reception@equipe.test',
  staff: 'sonia.staff@equipe.test',
};

// Pro-side mutable salon (catalogue 7.3a) — its own copy so consumer reads of
// `provider` stay stable. /me/provider returns this.
const proProvider = JSON.parse(JSON.stringify(provider));
proProvider.imageUrls = [
  'https://cdn.stub/a.jpg',
  'https://cdn.stub/b.jpg',
  'https://cdn.stub/c.jpg',
];
proProvider.beforeAfters = [];
// Salon lifecycle (pro-salon-lifecycle.md): the pro salon starts as a
// complete DRAFT — the go-live e2e publishes it.
proProvider.status = 'draft';
proProvider.services.push({
  id: 's3',
  name: 'Manucure',
  description: '',
  price: 8000,
  durationMinutes: 45,
  providerId: 'p1',
  active: true,
});
let svcSeq = 1;
let artSeq = 1;
let imgSeq = 1;

// --- team access R6c: the multi-salon world --------------------------------
// The owner also owns a SECOND salon (draft, its own free SETUP state) so the
// « Mes salons » switcher is e2e-testable; created salons land in the same
// registry. Members belong to p1 only.
const secondSalon = JSON.parse(JSON.stringify(provider));
secondSalon.id = 'p3';
secondSalon.slug = 'institut-belle-vue';
secondSalon.name = 'Institut Belle Vue';
secondSalon.status = 'draft';
secondSalon.artists = [];
secondSalon.imageUrls = [];
let addedSalonSeq = 3;
// salonId → the pro-side salon document (p1 keeps the historical proProvider).
const ownedSalons = new Map([
  ['p1', proProvider],
  ['p3', secondSalon],
]);
function salonEntryOf(id, role) {
  const salon = ownedSalons.get(id);
  return {
    salonId: id,
    salonName: salon.name,
    role,
    salonStatus: salon.status ?? 'active',
    verified: salon.verified === true,
    imageUrl: salon.imageUrls?.[0] ?? null,
  };
}

// --- team access R5a: the salon roster, offer & pending invitations --------
// The owner row is pinned & inert; the offer defaults to a LIVE trial so the
// 55 pre-team e2e (publish, abonnement) are untouched. `team-reset` (a
// test-only DELETE) drops back to the no-offer SETUP state for the picker arc.
let memberSeq = 1;
function freshTeam() {
  return [
    {
      id: 'member-owner',
      providerId: 'p1',
      accountId: 'acc1',
      email: 'proprietaire@beaute-divine.test',
      role: 'owner',
      artistId: null,
      artistName: null,
      status: 'active',
      invitedAt: '2026-01-01T00:00:00.000Z',
      acceptedAt: '2026-01-01T00:00:00.000Z',
      revokedAt: null,
      expiresAt: null,
    },
  ];
}
const SEAT_CAP = { pro: 5, business: 15, reseau: 15 };
function liveOffer() {
  return {
    tier: 'pro',
    status: 'trial',
    trialEndsAt: '2026-10-12T00:00:00.000Z',
    paidUntil: null,
    graceEndsAt: '2026-10-19T00:00:00.000Z',
    unpublishedForBilling: false,
    seats: { cap: SEAT_CAP.pro, used: 1 },
  };
}
let teamMembers = freshTeam();
// R6c: offers are PER SALON (p1 keeps the historical live trial; p3 and
// created salons start in the free SETUP state with their own trial).
const salonOffers = new Map([['p1', liveOffer()]]);
const trialUsedIds = new Set(['p1']);
// The login-bridge fixture: an invited email that is NOT yet a member — a 202
// {invitations} login lands on the « Invitations » step.
const INVITED_EMAIL = 'invitee@equipe.test';
function seededInvitationFor() {
  return {
    id: 'inv-seed-1',
    providerId: 'p1',
    salonName: 'Beauté Divine',
    role: 'manager',
    roleLabel: 'Manager',
    expiresAt: '2099-01-01T00:00:00.000Z',
  };
}
// Kept live for the whole run so the login-bridge e2e is retry-safe (a
// hermetic stub never really "consumes" it).
const bridgeInvitationLive = true;

function seatsUsed() {
  return teamMembers.filter((m) => m.status !== 'revoked').length;
}
function syncSeats() {
  const p1Offer = salonOffers.get('p1');
  if (p1Offer) p1Offer.seats.used = seatsUsed();
}
const ROLE_LABELS = {
  owner: 'Propriétaire',
  manager: 'Manager',
  reception: 'Réception',
  staff: 'Collaborateur',
};
// The invitee's view of their own pending rows (module `access` R2b DTO).
function myInvitations() {
  return teamMembers
    .filter((m) => m.status === 'invited')
    .map((m) => ({
      id: m.id,
      providerId: m.providerId,
      salonName: 'Beauté Divine',
      role: m.role,
      roleLabel: ROLE_LABELS[m.role],
      expiresAt: m.expiresAt,
    }));
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(data || '{}'));
      } catch {
        resolve({});
      }
    });
  });
}

createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);
  if (url.pathname === '/sitemap/providers') {
    return json(res, 200, { items: [{ slug: 'beaute-divine' }] });
  }
  const m = url.pathname.match(/^\/providers\/by-slug\/(.+)$/);
  if (m) {
    if (m[1] === 'beaute-divine') return json(res, 200, provider);
    if (m[1] === 'institut-acompte') return json(res, 200, depositProvider);
    return json(res, 404, { error: 'not_found' });
  }
  if (url.pathname === '/providers') {
    const category = url.searchParams.get('category');
    const commune = url.searchParams.get('commune');
    const matches =
      (!category || category === provider.category) &&
      (!commune || commune === provider.commune);
    const items = matches ? [provider] : [];
    return json(res, 200, {
      items,
      page: 1,
      pageSize: 20,
      total: items.length,
    });
  }
  // --- booking funnel (M5) ---
  if (url.pathname === '/availability') {
    const date =
      url.searchParams.get('date') || new Date().toISOString().slice(0, 10);
    const artistId = url.searchParams.get('artistId');
    const duration = Number(url.searchParams.get('durationMinutes') || 30);
    let slots = [
      `${date}T09:00:00.000Z`,
      `${date}T10:30:00.000Z`,
      `${date}T14:00:00.000Z`,
    ];
    // Binta's chair is taken all morning (per-artist capacity, K1).
    if (artistId === 'a2') slots = slots.slice(2);
    // Long variants (>150 min) no longer fit the mid-morning gap.
    if (duration > 150) slots = slots.filter((x) => !x.includes('T10:30'));
    return json(res, 200, { slots });
  }
  if (url.pathname === '/auth/otp/request') {
    return json(res, 200, { devCode: '123456' });
  }
  if (url.pathname === '/auth/otp/verify') {
    // Real API shape (AuthSession): tokens are NESTED under `tokens`, not flat.
    return json(res, 200, {
      tokens: {
        accessToken: 'stub-access',
        refreshToken: 'stub-refresh',
        expiresAt: '2099-01-01T00:00:00.000Z',
      },
      user: { id: 'u1', phoneNumber: '+2250700000000' },
    });
  }
  // --- auth overhaul (P2): email OTP + social (nested AuthSession) ---
  if (url.pathname === '/auth/email/otp/request') {
    return json(res, 202, { expiresInSeconds: 300, devCode: '123456' });
  }
  if (
    url.pathname === '/auth/email/otp/verify' ||
    url.pathname === '/auth/google' ||
    url.pathname === '/auth/apple'
  ) {
    return json(res, 200, {
      tokens: {
        accessToken: 'stub-access',
        refreshToken: 'stub-refresh',
        expiresAt: '2099-01-01T00:00:00.000Z',
      },
      user: stubUser,
    });
  }
  // --- consumer account (M6) ---
  if (url.pathname === '/me') {
    if (req.method === 'PATCH') {
      const body = await readBody(req);
      if (body.phone !== undefined) stubUser.phoneNumber = body.phone;
      if (body.name !== undefined) stubUser.name = body.name;
      return json(res, 200, stubUser);
    }
    if (req.method === 'DELETE') {
      // Parity 11.1 — definitive delete.
      res.writeHead(204);
      return res.end();
    }
    return json(res, 200, stubUser);
  }
  if (url.pathname === '/auth/refresh') {
    return json(res, 200, {
      accessToken: 'stub-access-2',
      refreshToken: 'stub-refresh-2',
    });
  }
  // favorites (M8.3)
  // « Signaler » (parity 2.14) — idempotent per reporter server-side.
  const reportMatch = url.pathname.match(/^\/reviews\/([^/]+)\/report$/);
  if (reportMatch) {
    if (!req.headers.authorization) {
      return json(res, 401, { error: 'unauthorized' });
    }
    return json(res, 200, {});
  }
  if (url.pathname === '/me/notifications') {
    return json(res, 200, {
      items: NOTIFS.map((n) => ({ ...n, read: notifRead.has(n.id) })),
    });
  }
  if (url.pathname === '/me/notifications/read-all') {
    for (const n of NOTIFS) notifRead.add(n.id);
    return json(res, 200, {});
  }
  const notifReadMatch = url.pathname.match(
    /^\/me\/notifications\/([^/]+)\/read$/,
  );
  if (notifReadMatch) {
    notifRead.add(notifReadMatch[1]);
    return json(res, 200, {});
  }
  if (url.pathname === '/me/notification-preferences') {
    if (req.method === 'PUT') {
      const body = await readBody(req);
      for (const k of ['reminders', 'marketing', 'push']) {
        if (typeof body[k] === 'boolean') notifPrefs[k] = body[k];
      }
    }
    return json(res, 200, notifPrefs);
  }
  if (url.pathname === '/me/favorites') {
    return json(res, 200, { providerIds: ['p1'] });
  }
  if (url.pathname.match(/^\/me\/favorites\/[^/]+$/)) {
    res.writeHead(204);
    return res.end();
  }
  // --- pro dashboard (M7.0) ---
  // --- pro auth overhaul (P4): email OTP + google (FLAT ProviderSession) ---
  if (url.pathname === '/auth/provider/email/otp/request') {
    return json(res, 202, { expiresInSeconds: 300, devCode: '123456' });
  }
  if (url.pathname === '/auth/provider/register') {
    const b = await readBody(req);
    if (!b.businessName || !b.phoneNumber || (!b.idToken && !(b.email && b.code))) {
      return json(res, 400, { error: 'invalid_input' });
    }
    if (b.email === 'existe@salon.test') {
      return json(res, 409, { error: 'provider_exists' });
    }
    if (b.code && b.code !== '123456') {
      return json(res, 401, { error: 'otp_invalid' });
    }
    return json(res, 201, {
      provider: {
        id: 'acc-new',
        businessName: b.businessName,
        providerId: 'p1',
      },
      accessToken: 'stub-pro-access',
      refreshToken: 'stub-pro-refresh',
      expiresAt: '2099-01-01T00:00:00.000Z',
    });
  }
  if (
    url.pathname === '/auth/provider/email/otp/verify' ||
    url.pathname === '/auth/provider/google'
  ) {
    const b = await readBody(req);
    // Team access R5a: an invited-but-not-yet-member identity gets the 202
    // bridge (no session) — the client shows the « Invitations » step. Driven
    // by the email path (deterministic) or a Google sentinel credential.
    const invited =
      (b.email === INVITED_EMAIL || b.idToken === 'google-invitee') &&
      bridgeInvitationLive;
    if (invited) {
      return json(res, 202, { invitations: [seededInvitationFor()] });
    }
    // Team access R5b: member logins carry ROLE tokens.
    const memberRole = MEMBER_LOGINS[b.email];
    if (memberRole) {
      return json(res, 200, {
        provider: {
          id: `acc-${memberRole}`,
          businessName: 'Beauté Divine',
          providerId: 'p1',
        },
        accessToken: `pro-${memberRole}-access`,
        refreshToken: `pro-${memberRole}-refresh`,
        expiresAt: '2099-01-01T00:00:00.000Z',
      });
    }
    return json(res, 200, {
      provider: { id: 'acc1', businessName: 'Beauté Divine', providerId: 'p1' },
      accessToken: 'stub-pro-access',
      refreshToken: 'stub-pro-refresh',
      expiresAt: '2099-01-01T00:00:00.000Z',
    });
  }
  // Team access R5a: the LOGIN-bridge accept/decline (identity-proven, no
  // prior session). Accept → a flat ProviderSession (cookies set exactly like
  // a login); decline → a bare {declined:true}.
  if (url.pathname === '/auth/provider/invitations/accept') {
    const b = await readBody(req);
    if (!b.invitationId || (!b.idToken && !(b.email && b.code))) {
      return json(res, 400, { error: 'invalid_input' });
    }
    if (b.code && b.code !== '123456') {
      return json(res, 401, { error: 'otp_invalid' });
    }
    return json(res, 200, {
      provider: {
        id: 'acc-member',
        businessName: 'Beauté Divine',
        providerId: 'p1',
      },
      accessToken: 'stub-pro-access',
      refreshToken: 'stub-pro-refresh',
      expiresAt: '2099-01-01T00:00:00.000Z',
    });
  }
  if (url.pathname === '/auth/provider/invitations/decline') {
    const b = await readBody(req);
    if (!b.invitationId || (!b.idToken && !(b.email && b.code))) {
      return json(res, 400, { error: 'invalid_input' });
    }
    return json(res, 200, { declined: true });
  }
  // --- module journal J1 ------------------------------------------------
  const journalM = url.pathname.match(/^\/providers\/([^/]+)\/journal$/);
  if (journalM) {
    const date = url.searchParams.get('date') || todayAt9.slice(0, 10);
    // Team access R5b: own-scope (staff) gets ONLY their artist's column +
    // their own rows — mirrors journal_service.dart's journalScope filter.
    if (roleOf(req) === 'staff') {
      return json(res, 200, {
        date,
        hours: { open: '09:00', close: '18:00', breaks: [{ start: '12:30', end: '13:30' }] },
        artists: [{ id: 'artist-a', name: 'Awa', imageUrl: null }],
        appointments: [
          { ...proAppt('pstaff1'), appointmentDate: `${date}T11:00:00.000Z` },
        ],
      });
    }
    return json(res, 200, {
      date,
      hours: { open: '09:00', close: '18:00', breaks: [{ start: '12:30', end: '13:30' }] },
      artists: [{ id: 'artist-a', name: 'Awa', imageUrl: null }],
      appointments: [
        { ...proAppt('pj1'), appointmentDate: `${date}T09:00:00.000Z` },
      ],
    });
  }
  const provApptM = url.pathname.match(/^\/providers\/([^/]+)\/appointments$/);
  if (provApptM && req.method === 'POST') {
    const b = await readBody(req);
    if ((b.appointmentDateTime || '').includes('T10:00')) {
      return json(res, 409, { error: 'slot_unavailable' });
    }
    return json(res, 201, {
      ...proAppt('pnew'),
      status: 'confirmed',
      appointmentDate: b.appointmentDateTime,
      clientName: b.clientName || 'Client',
    });
  }

  // --- module clients C1b -----------------------------------------------
  const clientsList = url.pathname.match(/^\/providers\/([^/]+)\/clients$/);
  if (clientsList) {
    if (req.method === 'POST') {
      const b = await readBody(req);
      const existing = salonClients.find((c) => c.phone === b.phone);
      if (existing) {
        return json(res, 409, { error: 'client_exists', clientId: existing.id });
      }
      const created = {
        id: `sc${clientSeq++}`,
        displayName: b.name,
        phone: b.phone,
        tags: [],
        lastVisitAt: null,
        linked: false,
        createdAt: todayAt9,
        visits: 0,
        noShows: 0,
      };
      salonClients.push(created);
      clientNotes[created.id] = b.note
        ? [{ id: `n${clientSeq++}`, authorName: 'Vous', body: b.note, createdAt: todayAt9 }]
        : [];
      return json(res, 201, created);
    }
    const q = (url.searchParams.get('query') || '').toLowerCase();
    const tag = url.searchParams.get('tag') || '';
    const qDigits = q.replace(/[^0-9]/g, '');
    const items = salonClients
      .filter((c) => !tag || c.tags.includes(tag))
      .filter(
        (c) =>
          !q ||
          c.displayName.toLowerCase().includes(q) ||
          (qDigits.length >= 2 &&
            (c.phone || '').replace(/[^0-9]/g, '').includes(qDigits)),
      );
    return json(res, 200, {
      items,
      page: 1,
      pageSize: 20,
      total: items.length,
      availableTags: ['VIP', 'Fidèle', 'À risque'],
    });
  }
  const clientCard = url.pathname.match(
    /^\/providers\/([^/]+)\/clients\/([^/]+)$/,
  );
  if (clientCard) {
    const c = salonClients.find((x) => x.id === clientCard[2]);
    if (!c) return json(res, 404, { error: 'not_found' });
    if (req.method === 'PATCH') {
      const b = await readBody(req);
      c.tags = b.tags || [];
      return json(res, 200, c);
    }
    return json(res, 200, {
      ...c,
      stats: {
        visits: c.visits,
        spentFcfa: c.visits * 15000,
        noShows: c.noShows,
        cancellations: 0,
      },
      notes: clientNotes[c.id] || [],
    });
  }
  const clientVisits = url.pathname.match(
    /^\/providers\/([^/]+)\/clients\/([^/]+)\/visits$/,
  );
  if (clientVisits) {
    const c = salonClients.find((x) => x.id === clientVisits[2]);
    if (!c) return json(res, 404, { error: 'not_found' });
    const items = c.id === 'sc1' ? [proAppt('pappt1')] : [];
    return json(res, 200, { items, page: 1, pageSize: 20, total: items.length });
  }
  const clientNotesM = url.pathname.match(
    /^\/providers\/([^/]+)\/clients\/([^/]+)\/notes$/,
  );
  if (clientNotesM && req.method === 'POST') {
    const b = await readBody(req);
    const note = {
      id: `n${clientSeq++}`,
      authorName: 'Vous',
      body: b.body,
      createdAt: todayAt9,
    };
    (clientNotes[clientNotesM[2]] ||= []).unshift(note);
    return json(res, 201, note);
  }
  const clientNoteDel = url.pathname.match(
    /^\/providers\/([^/]+)\/clients\/([^/]+)\/notes\/([^/]+)$/,
  );
  if (clientNoteDel && req.method === 'DELETE') {
    const list = clientNotes[clientNoteDel[2]] || [];
    clientNotes[clientNoteDel[2]] = list.filter((n) => n.id !== clientNoteDel[3]);
    res.statusCode = 204;
    return res.end();
  }

  if (url.pathname === '/auth/provider/otp/request') {
    return json(res, 200, { devCode: '123456' });
  }
  if (url.pathname === '/auth/provider/otp/verify') {
    return json(res, 200, {
      provider: { id: 'acc1', businessName: 'Beauté Divine', providerId: 'p1' },
      accessToken: 'pro-access',
      refreshToken: 'pro-refresh',
    });
  }
  if (url.pathname === '/auth/provider/refresh') {
    return json(res, 200, {
      accessToken: 'pro-access-2',
      refreshToken: 'pro-refresh-2',
    });
  }
  if (url.pathname === '/me/provider') {
    // Audit 11.5 — account deletion (the gate is backend-tested; the stub
    // accepts).
    if (req.method === 'DELETE') {
      res.writeHead(204);
      return res.end();
    }
    const role = roleOf(req);
    // Team access R5b: a REVOKED member's probe → the distinct 403 that
    // drives the web sign-out (+ ?motif=acces-retire banner).
    if (role === 'revoked') {
      return json(res, 403, { error: 'not_a_member' });
    }
    // R6c: an explicit selection — an OWNER may act in any owned salon;
    // anything else is the uniform per-salon 403 (T55).
    const selected = url.searchParams.get('salonId');
    let servedSalon = proProvider;
    if (selected && selected !== 'p1') {
      if (role !== 'owner' || !ownedSalons.has(selected)) {
        return json(res, 403, { error: 'forbidden' });
      }
      servedSalon = ownedSalons.get(selected);
    }
    return json(res, 200, {
      account: {
        id: role === 'owner' ? 'acc1' : `acc-${role}`,
        businessName: 'Beauté Divine',
        businessType: 'other',
        phoneNumber: '+2250700000000',
        email: MEMBER_EMAILS[role],
        // The salon session is VERIFIED (T52 flows: acompte editor enabled);
        // the /me/kyc page reads kycState separately (its own e2e).
        verificationStatus: 'verified',
        providerId: 'p1',
      },
      provider: servedSalon,
      // Access R4a: the caller's role-shaped membership.
      membership: {
        role,
        capabilities: ROLE_CAPS[role],
        ...(role === 'staff'
          ? { artistId: 'artist-a', artistName: 'Awa' }
          : {}),
      },
    });
  }
  // --- team access R6c: « Mes salons » -----------------------------------
  if (url.pathname === '/me/salons') {
    const role = roleOf(req);
    if (role === 'revoked') return json(res, 403, { error: 'not_a_member' });
    if (req.method === 'POST') {
      if (role !== 'owner') return json(res, 403, { error: 'forbidden' });
      const b = await readBody(req);
      if (!b.businessName || typeof b.businessName !== 'string') {
        return json(res, 400, { error: 'invalid_input' });
      }
      const p1Offer = salonOffers.get('p1');
      const reseauLive =
        [...salonOffers.values()].some(
          (o) => o.tier === 'reseau' && o.status !== 'expired',
        ) && Boolean(p1Offer);
      if (!reseauLive) {
        return json(res, 403, { error: 'reseau_required' });
      }
      const id = `p${++addedSalonSeq}`;
      const created = JSON.parse(JSON.stringify(provider));
      created.id = id;
      created.slug = `salon-${id}`;
      created.name = b.businessName.trim();
      created.status = 'draft';
      created.artists = [];
      created.imageUrls = [];
      ownedSalons.set(id, created);
      return json(res, 201, { salon: salonEntryOf(id, 'owner') });
    }
    // GET: owners see the whole owned fleet; members see their one salon.
    const items =
      role === 'owner'
        ? [...ownedSalons.keys()].map((id) => salonEntryOf(id, 'owner'))
        : [salonEntryOf('p1', role)];
    const canAddSalon =
      role === 'owner' &&
      [...salonOffers.values()].some(
        (o) => o.tier === 'reseau' && o.status !== 'expired',
      );
    return json(res, 200, { items, canAddSalon });
  }
  // --- team access R5a: the salon roster (owner-only) -------------------
  if (url.pathname === '/me/provider/members') {
    if (req.method === 'POST') {
      const b = await readBody(req);
      const email = (b.email || '').trim().toLowerCase();
      const role = b.role;
      // Backend gate order: offer_required → seat_limit → member_exists →
      // artist_required/not_found.
      const p1Offer = salonOffers.get('p1');
      if (!p1Offer || p1Offer.status === 'expired') {
        return json(res, 409, { error: 'offer_required' });
      }
      if (seatsUsed() >= p1Offer.seats.cap) {
        return json(res, 409, { error: 'seat_limit' });
      }
      if (
        teamMembers.some(
          (m) => m.email === email && m.status !== 'revoked',
        )
      ) {
        return json(res, 409, { error: 'member_exists' });
      }
      if (role === 'staff') {
        if (!b.artistId) return json(res, 400, { error: 'artist_required' });
        const a = (proProvider.artists ?? []).find((x) => x.id === b.artistId);
        if (!a) return json(res, 400, { error: 'artist_not_found' });
      }
      const artist =
        role === 'staff'
          ? (proProvider.artists ?? []).find((x) => x.id === b.artistId)
          : null;
      const member = {
        id: `member-${++memberSeq}`,
        providerId: 'p1',
        accountId: null,
        email,
        role,
        artistId: artist ? artist.id : null,
        artistName: artist ? artist.name : null,
        status: 'invited',
        invitedAt: todayAt9,
        acceptedAt: null,
        revokedAt: null,
        expiresAt: '2099-01-01T00:00:00.000Z',
        resendsLeft: 3,
        expired: false,
      };
      teamMembers.push(member);
      syncSeats();
      return json(res, 201, member);
    }
    // R6c: a selected non-p1 salon has its own (owner-only) roster.
    const memberSalon = url.searchParams.get('salonId');
    if (memberSalon && memberSalon !== 'p1') {
      if (!ownedSalons.has(memberSalon)) {
        return json(res, 403, { error: 'forbidden' });
      }
      return json(res, 200, {
        items: [
          {
            ...freshTeam()[0],
            id: `member-owner-${memberSalon}`,
            providerId: memberSalon,
          },
        ],
      });
    }
    return json(res, 200, { items: teamMembers });
  }
  const memberActionM = url.pathname.match(
    /^\/me\/provider\/members\/([^/]+)(?:\/(revoke|resend))?$/,
  );
  if (memberActionM) {
    const [, memberId, action] = memberActionM;
    const member = teamMembers.find((m) => m.id === memberId);
    if (!member) return json(res, 404, { error: 'not_found' });
    if (member.role === 'owner') {
      return json(res, 403, { error: 'owner_protected' });
    }
    if (action === 'revoke' && req.method === 'POST') {
      member.status = 'revoked';
      member.revokedAt = todayAt9;
      syncSeats();
      return json(res, 200, member);
    }
    if (action === 'resend' && req.method === 'POST') {
      if ((member.resendsLeft ?? 0) <= 0) {
        return json(res, 429, { error: 'invite_rate_limited' });
      }
      member.resendsLeft -= 1;
      return json(res, 200, member);
    }
    if (!action && req.method === 'PATCH') {
      const b = await readBody(req);
      if (b.role === 'staff') {
        if (!b.artistId) return json(res, 400, { error: 'artist_required' });
        const a = (proProvider.artists ?? []).find((x) => x.id === b.artistId);
        if (!a) return json(res, 400, { error: 'artist_not_found' });
        member.artistId = a.id;
        member.artistName = a.name;
      } else {
        member.artistId = null;
        member.artistName = null;
      }
      member.role = b.role;
      return json(res, 200, member);
    }
    return json(res, 405, { error: 'method_not_allowed' });
  }
  // The signed-in provider's OWN pending invitations + authed accept/decline.
  if (url.pathname === '/me/provider/invitations') {
    return json(res, 200, { invitations: myInvitations() });
  }
  const myInvActionM = url.pathname.match(
    /^\/me\/provider\/invitations\/([^/]+)\/(accept|decline)$/,
  );
  if (myInvActionM && req.method === 'POST') {
    const [, invitationId, action] = myInvActionM;
    const member = teamMembers.find(
      (m) => m.id === invitationId && m.status === 'invited',
    );
    if (!member) return json(res, 404, { error: 'not_found' });
    if (action === 'accept') {
      member.status = 'active';
      member.acceptedAt = todayAt9;
      member.expiresAt = null;
    } else {
      teamMembers = teamMembers.filter((m) => m.id !== invitationId);
    }
    syncSeats();
    return json(res, 200, action === 'accept' ? member : { declined: true });
  }
  // The salon offer (pricing pivot). 404 = SETUP (no offer chosen yet).
  const subM = url.pathname.match(/^\/providers\/([^/]+)\/subscription$/);
  if (subM) {
    // R6c: offers are PER SALON — p1 keeps the historical seeded trial;
    // p3/created salons start in SETUP with their own single trial.
    const subSalonId = subM[1];
    if (req.method === 'PUT') {
      const b = await readBody(req);
      if (!['pro', 'business', 'reseau'].includes(b.tier)) {
        return json(res, 400, { error: 'invalid_input' });
      }
      const current = salonOffers.get(subSalonId);
      if (!current) {
        if (trialUsedIds.has(subSalonId)) {
          return json(res, 409, { error: 'trial_used' });
        }
        trialUsedIds.add(subSalonId);
        salonOffers.set(subSalonId, {
          tier: b.tier,
          status: 'trial',
          trialEndsAt: '2026-10-12T00:00:00.000Z',
          paidUntil: null,
          graceEndsAt: '2026-10-19T00:00:00.000Z',
          unpublishedForBilling: false,
          seats: { cap: SEAT_CAP[b.tier], used: seatsUsed() },
        });
      } else {
        // A switch keeps the trial clock; only the tier/cap change.
        current.tier = b.tier;
        current.seats.cap = SEAT_CAP[b.tier];
        syncSeats();
      }
      return json(res, 200, salonOffers.get(subSalonId));
    }
    const offer = salonOffers.get(subSalonId);
    if (!offer) return json(res, 404, { error: 'no_offer' });
    syncSeats();
    return json(res, 200, offer);
  }
  // KYC (web-pro-kyc.md) — stateful: POST stores the docs, stays pending.
  if (url.pathname === '/me/kyc') {
    if (req.method === 'POST') {
      const b = await readBody(req);
      kycState.documents = (b.documents ?? []).map((d) => ({
        ...d,
        submittedAt: todayAt9,
      }));
      kycState.status = 'pending';
      return json(res, 200, kycState);
    }
    return json(res, 200, kycState);
  }
  // catalogue services CRUD (7.3a) — mutates the pro salon copy.
  const svcMatch = url.pathname.match(
    /^\/providers\/[^/]+\/services(?:\/([^/]+))?$/,
  );
  if (svcMatch) {
    const sid = svcMatch[1];
    if (req.method === 'POST') {
      const body = await readBody(req);
      const created = { id: `svc${++svcSeq}`, providerId: 'p1', active: true, ...body };
      proProvider.services.push(created);
      return json(res, 201, created);
    }
    if (req.method === 'PATCH' && sid) {
      const body = await readBody(req);
      const s = proProvider.services.find((x) => x.id === sid);
      if (!s) return json(res, 404, { error: 'not_found' });
      Object.assign(s, body);
      return json(res, 200, s);
    }
    if (req.method === 'DELETE' && sid) {
      proProvider.services = proProvider.services.filter((x) => x.id !== sid);
      res.writeHead(204);
      return res.end();
    }
    return json(res, 404, { error: 'not_found' });
  }
  // tableau de bord (7.3d) — server-computed stats. Team access R5b: staff
  // (own-scope) → 403; manager/réception → counts WITHOUT the revenue keys
  // (finances.view field-gating); owner → full.
  if (url.pathname.match(/^\/providers\/[^/]+\/dashboard$/)) {
    const role = roleOf(req);
    if (role === 'staff' || role === 'revoked') {
      return json(res, 403, { error: 'forbidden' });
    }
    if (role !== 'owner') {
      return json(res, 200, {
        todayAppointments: 1,
        pendingRequests: 1,
        totalAppointments: 1,
      });
    }
    return json(res, 200, {
      todayAppointments: 1,
      pendingRequests: 1,
      todayRevenue: 15000,
      weekRevenue: 15000,
      monthRevenue: 45000,
      totalAppointments: 1,
    });
  }
  // go-live (pro-salon-lifecycle.md B2) — flips the draft to active. Team
  // access R5a: publishing requires a LIVE offer (else 409 missing:['offer']).
  const pubM = url.pathname.match(/^\/providers\/([^/]+)\/publish$/);
  if (pubM) {
    const pubOffer = salonOffers.get(pubM[1]);
    const offerLive =
      pubOffer && (pubOffer.status === 'trial' || pubOffer.status === 'paid');
    if (!offerLive) {
      return json(res, 409, { error: 'not_ready', missing: ['offer'] });
    }
    const target = ownedSalons.get(pubM[1]) ?? proProvider;
    target.status = 'active';
    return json(res, 200, target);
  }
  // revenus (parity 9.1) — realized ledger, optional inclusive range.
  if (url.pathname.match(/^\/providers\/[^/]+\/earnings$/)) {
    const start = url.searchParams.get('startDate');
    const end = url.searchParams.get('endDate');
    const tx = EARN_TX.filter(
      (t) => (!start || t.date >= start) && (!end || t.date < end),
    );
    return json(res, 200, {
      totalEarnings: tx.reduce((sum, t) => sum + t.amount, 0),
      transactions: tx,
    });
  }
  // disponibilités (7.3c) — PUT replaces the salon availability.
  if (url.pathname.match(/^\/providers\/[^/]+\/availability$/)) {
    if (req.method === 'PUT') {
      const body = await readBody(req);
      proProvider.availability = body;
      return json(res, 200, body);
    }
    return json(res, 405, { error: 'method_not_allowed' });
  }
  // médias (7.3e-ii) — presigned upload + R2 POST + gallery/before-after PUT.
  if (url.pathname === '/uploads/sign') {
    const b = await readBody(req);
    if (b.purpose === 'deposit') {
      return json(res, 200, {
        method: 'POST',
        uploadUrl: `http://127.0.0.1:${port}/r2-upload`,
        fields: {},
        key: `deposit/u1/${imgSeq++}.jpg`,
      });
    }
    if (b.purpose === 'review') {
      const n = imgSeq++;
      return json(res, 200, {
        method: 'POST',
        uploadUrl: `http://127.0.0.1:${port}/r2-upload`,
        fields: {},
        key: `review/u1/${n}.jpg`,
        publicUrl: `https://cdn.stub/review/u1/${n}.jpg`,
      });
    }
    if (b.purpose === 'kyc') {
      return json(res, 200, {
        method: 'POST',
        uploadUrl: `http://127.0.0.1:${port}/r2-upload`,
        fields: {},
        key: `kyc/acc1/${imgSeq++}.jpg`,
      });
    }
    return json(res, 200, {
      method: 'POST',
      uploadUrl: `http://127.0.0.1:${port}/r2-upload`,
      fields: {},
      key: `gallery/p1/${imgSeq}.jpg`,
      publicUrl: `https://cdn.stub/gallery/p1/${imgSeq++}.jpg`,
    });
  }
  if (url.pathname === '/r2-upload') {
    // The browser POSTs bytes here directly (cross-origin) — accept + CORS-allow.
    res.writeHead(204, { 'access-control-allow-origin': '*' });
    return res.end();
  }
  // « Avis » (web-pro-reviews.md) — the salon's paginated public reviews.
  if (url.pathname.match(/^\/providers\/[^/]+\/reviews$/)) {
    return json(res, 200, {
      items: [
        {
          id: 'r1',
          providerId: 'p1',
          userId: 'u1',
          userName: 'Awa',
          rating: 5,
          text: 'Service impeccable.',
          serviceName: 'Tresses',
          artistName: 'Awa',
          createdAt: '2026-06-01T10:00:00.000Z',
        },
        {
          id: 'r2',
          providerId: 'p1',
          userId: 'u3',
          userName: 'Mariam',
          rating: 4,
          text: 'Très bon accueil.',
          photoUrls: ['https://cdn.stub/avis1.jpg'],
          createdAt: '2026-06-15T10:00:00.000Z',
        },
      ],
      page: 1,
      pageSize: 50,
      total: 2,
    });
  }
  if (url.pathname.match(/^\/providers\/[^/]+\/gallery$/)) {
    if (req.method === 'PUT') {
      const body = await readBody(req);
      proProvider.imageUrls = body.imageUrls ?? [];
      return json(res, 200, { imageUrls: proProvider.imageUrls });
    }
    return json(res, 200, { imageUrls: proProvider.imageUrls ?? [] });
  }
  if (url.pathname.match(/^\/providers\/[^/]+\/before-after$/)) {
    if (req.method === 'PUT') {
      const body = await readBody(req);
      proProvider.beforeAfters = body.beforeAfters ?? [];
      return json(res, 200, proProvider.beforeAfters);
    }
    return json(res, 200, proProvider.beforeAfters ?? []);
  }
  // acompte (7.3e-i) — deposit policy GET/PUT.
  if (url.pathname.match(/^\/providers\/[^/]+\/deposit-policy$/)) {
    if (req.method === 'PUT') {
      const body = await readBody(req);
      proProvider.depositPolicy = body;
      return json(res, 200, body);
    }
    return json(
      res,
      200,
      proProvider.depositPolicy ?? {
        depositRequired: false,
        depositPercentage: 0,
        cancellationWindowHours: 24,
      },
    );
  }
  // catalogue artists CRUD (7.3b)
  const artMatch = url.pathname.match(
    /^\/providers\/[^/]+\/artists(?:\/([^/]+))?$/,
  );
  if (artMatch) {
    const aid = artMatch[1];
    proProvider.artists = proProvider.artists ?? [];
    if (req.method === 'POST') {
      const body = await readBody(req);
      const created = { id: `art${++artSeq}`, providerId: 'p1', ...body };
      proProvider.artists.push(created);
      return json(res, 201, created);
    }
    if (req.method === 'PATCH' && aid) {
      const body = await readBody(req);
      const a = proProvider.artists.find((x) => x.id === aid);
      if (!a) return json(res, 404, { error: 'not_found' });
      Object.assign(a, body);
      return json(res, 200, a);
    }
    if (req.method === 'DELETE' && aid) {
      proProvider.artists = proProvider.artists.filter((x) => x.id !== aid);
      res.writeHead(204);
      return res.end();
    }
    return json(res, 404, { error: 'not_found' });
  }
  const apptMatch = url.pathname.match(
    /^\/appointments(?:\/([^/]+)(?:\/([^/]+))?)?$/,
  );
  if (apptMatch) {
    const [, id, sub] = apptMatch;
    if (!id) {
      if (req.method === 'POST') {
        const b = await readBody(req);
        const deposit = b.providerId === 'p2' ? 7500 : 0;
        return json(res, 201, {
          id: 'appt1',
          status: 'pending',
          totalPrice: 15000,
          depositAmount: deposit,
          balanceDue: 15000 - deposit,
        });
      }
      // Provider list (M7) vs consumer list (M6), split by token. Team
      // access R5b: staff (own-scope) sees only THEIR artist's rows —
      // pstaff1 stays OUT of the owner list so the pre-R5b count
      // assertions hold. R6c: a selected non-p1 salon starts empty.
      const listSalon = url.searchParams.get('salonId');
      if (isPro(req) && listSalon && listSalon !== 'p1') {
        return json(res, 200, { items: [], page: 1, pageSize: 0, total: 0 });
      }
      const items = isPro(req)
        ? roleOf(req) === 'staff'
          ? [proAppt('pstaff1')]
          : [proAppt('pappt1')]
        : [
            consumerAppt('appt1'),
            consumerAppt('appt2'),
            consumerAppt('appt3'),
          ];
      return json(res, 200, {
        items,
        page: 1,
        pageSize: items.length,
        total: items.length,
      });
    }
    if (!sub) {
      // GET /appointments/{id} — consumer detail (provider uses the list).
      return json(res, 200, consumerAppt(id));
    }
    if (sub === 'cancel') {
      cancelled.add(id);
      return json(res, 200, consumerAppt(id));
    }
    if (sub === 'review') {
      return json(res, 200, { id, rating: 5 });
    }
    if (sub === 'deposit' && req.method === 'POST') {
      const b = await readBody(req);
      if (!b.screenshotKey) return json(res, 400, { error: 'invalid_input' });
      return json(res, 200, {
        ...consumerAppt(id),
        depositScreenshotUrl: 'https://cdn.stub/deposit.jpg',
      });
    }
    if (sub === 'deposit-screenshot') {
      return json(res, 200, { url: 'https://example.test/justificatif.jpg' });
    }
    // Team access R5b (T40): staff may only complete/no-show THEIR OWN
    // bookings; accept/reject/arrive/reschedule are whole-journal acts.
    const staffCaller = roleOf(req) === 'staff';
    if (
      staffCaller &&
      ['arrive', 'reschedule', 'accept', 'reject'].includes(sub)
    ) {
      return json(res, 403, { error: 'forbidden' });
    }
    if (sub === 'arrive') {
      proArrived[id] = new Date().toISOString();
      return json(res, 200, proAppt(id));
    }
    if (sub === 'reschedule') {
      // Accept the move; a 10:00 target simulates a taken slot (409).
      const b = await readBody(req);
      if ((b.newDateTime || '').includes('T10:00')) {
        return json(res, 409, { error: 'slot_unavailable' });
      }
      return json(res, 200, proAppt(id));
    }
    if (PRO_TRANSITION[sub]) {
      if (staffCaller && id !== 'pstaff1') {
        return json(res, 403, { error: 'forbidden' });
      }
      proStatus[id] = PRO_TRANSITION[sub];
      return json(res, 200, proAppt(id));
    }
    return json(res, 404, { error: 'not_found' });
  }
  // single provider: GET (enrichment, const) · PATCH (profil 7.3e-i, pro copy).
  const provMatch = url.pathname.match(/^\/providers\/([^/]+)$/);
  if (provMatch) {
    if (req.method === 'PATCH') {
      const body = await readBody(req);
      Object.assign(proProvider, body);
      return json(res, 200, proProvider);
    }
    if (provMatch[1] === 'p1') return json(res, 200, provider);
    if (provMatch[1] === 'p2') return json(res, 200, depositProvider);
    return json(res, 404, { error: 'not_found' });
  }
  return json(res, 404, { error: 'not_found' });
}).listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`stub-api on :${port}`);
});
