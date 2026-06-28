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
  imageUrls: [], // empty → no external image fetch during e2e
  rating: 4.8,
  reviewCount: 2,
  phoneNumber: '+2250700000000',
  whatsapp: '+2250700000000',
  category: 'salon',
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
      providerId: 'p1',
      active: true,
    },
  ],
  artists: [{ id: 'a1', name: 'Awa', specialization: 'Tresses', providerId: 'p1' }],
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
      rating: 5,
      text: 'Service impeccable.',
      createdAt: '2026-06-01T10:00:00.000Z',
    },
  ],
};

function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

// Dated "today" (UTC) so the pro views show it whenever the suite runs.
const todayAt9 = `${new Date().toISOString().slice(0, 10)}T09:00:00.000Z`;

// Consumer side (M5/M6) — appt1; cancel is stateful.
const cancelled = new Set();
const consumerAppt = (id) => ({
  id,
  userId: 'u1',
  providerId: 'p1',
  serviceIds: ['s1'],
  clientName: 'Awa',
  appointmentDate: todayAt9,
  status: cancelled.has(id) ? 'cancelled' : 'confirmed',
  totalPrice: 15000,
  depositAmount: 0,
  balanceDue: 15000,
  cancellationWindowHours: 24,
});

// Pro side (M7) — pappt1, mutable status via the lifecycle endpoints. Kept
// separate from the consumer flow (split by token below) so parallel tests
// don't race on shared state.
const proStatus = { pappt1: 'pending' };
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
});
const isPro = (req) => (req.headers.authorization || '').includes('pro');

// Pro-side mutable salon (catalogue 7.3a) — its own copy so consumer reads of
// `provider` stay stable. /me/provider returns this.
const proProvider = JSON.parse(JSON.stringify(provider));
let svcSeq = 1;
let artSeq = 1;

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
    return m[1] === 'beaute-divine'
      ? json(res, 200, provider)
      : json(res, 404, { error: 'not_found' });
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
    return json(res, 200, {
      slots: ['2026-12-01T09:00:00.000Z', '2026-12-01T10:30:00.000Z'],
    });
  }
  if (url.pathname === '/auth/otp/request') {
    return json(res, 200, { devCode: '123456' });
  }
  if (url.pathname === '/auth/otp/verify') {
    return json(res, 200, {
      accessToken: 'stub-access',
      refreshToken: 'stub-refresh',
      user: { id: 'u1', phoneNumber: '+2250700000000' },
    });
  }
  // --- consumer account (M6) ---
  if (url.pathname === '/me') {
    return json(res, 200, {
      id: 'u1',
      name: 'Awa',
      phoneNumber: '+2250700000000',
    });
  }
  if (url.pathname === '/auth/refresh') {
    return json(res, 200, {
      accessToken: 'stub-access-2',
      refreshToken: 'stub-refresh-2',
    });
  }
  // --- pro dashboard (M7.0) ---
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
    return json(res, 200, {
      account: {
        id: 'acc1',
        businessName: 'Beauté Divine',
        phoneNumber: '+2250700000000',
        providerId: 'p1',
      },
      provider: proProvider,
    });
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
  // disponibilités (7.3c) — PUT replaces the salon availability.
  if (url.pathname.match(/^\/providers\/[^/]+\/availability$/)) {
    if (req.method === 'PUT') {
      const body = await readBody(req);
      proProvider.availability = body;
      return json(res, 200, body);
    }
    return json(res, 405, { error: 'method_not_allowed' });
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
        return json(res, 201, {
          id: 'appt1',
          status: 'pending',
          totalPrice: 15000,
          depositAmount: 0,
          balanceDue: 15000,
        });
      }
      // Provider list (M7) vs consumer list (M6), split by token.
      const items = isPro(req) ? [proAppt('pappt1')] : [consumerAppt('appt1')];
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
    if (sub === 'deposit-screenshot') {
      return json(res, 200, { url: 'https://example.test/justificatif.jpg' });
    }
    if (PRO_TRANSITION[sub]) {
      proStatus[id] = PRO_TRANSITION[sub];
      return json(res, 200, proAppt(id));
    }
    return json(res, 404, { error: 'not_found' });
  }
  // single-provider lookup for enrichment: /providers/{id}
  const provMatch = url.pathname.match(/^\/providers\/([^/]+)$/);
  if (provMatch) {
    return provMatch[1] === 'p1'
      ? json(res, 200, provider)
      : json(res, 404, { error: 'not_found' });
  }
  return json(res, 404, { error: 'not_found' });
}).listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`stub-api on :${port}`);
});
