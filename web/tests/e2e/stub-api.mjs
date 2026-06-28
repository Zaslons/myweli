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

// Stateful so the cancel e2e reflects the new status on reload.
const cancelled = new Set();
const appt = (id) => ({
  id,
  userId: 'u1',
  providerId: 'p1',
  serviceIds: ['s1'],
  appointmentDate: '2026-12-01T09:00:00.000Z',
  status: cancelled.has(id) ? 'cancelled' : 'confirmed',
  totalPrice: 15000,
  depositAmount: 0,
  balanceDue: 15000,
  cancellationWindowHours: 24,
});

createServer((req, res) => {
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
  const apptMatch = url.pathname.match(
    /^\/appointments(?:\/([^/]+)(\/cancel)?)?$/,
  );
  if (apptMatch) {
    const [, id, cancel] = apptMatch;
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
      return json(res, 200, {
        items: [appt('appt1')],
        page: 1,
        pageSize: 1,
        total: 1,
      });
    }
    if (cancel) cancelled.add(id);
    return json(res, 200, appt(id));
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
