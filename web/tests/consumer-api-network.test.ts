import { afterEach, describe, expect, it, vi } from 'vitest';

const captureMessage = vi.fn();
vi.mock('@sentry/nextjs', () => ({
  captureMessage: (...a: unknown[]) => captureMessage(...a),
}));

const account = await import('../lib/api/account');
const auth = await import('../lib/auth/client');
const booking = await import('../lib/booking/client');
const deposit = await import('../lib/booking/deposit');
const reviewPhotos = await import('../lib/account/review-photos');

/// docs/design/web-consumer-network-failure.md §2 — a consumer browser → BFF
/// wrapper never throws. A dropped connection is status 0 (or `ok: false`),
/// and the non-200 branch every caller already has is its error state;
/// before, the rejection went through to a page that never caught it, and the
/// page stayed on its skeleton for ever (Mon compte, le détail, les
/// notifications, Mes données, la confirmation d'une réservation), or its
/// button stayed busy.

/// How a call's result is judged.
/// - `read`: a GET — status 0 when no usable answer came back (a 2xx body that
///   cannot be read included: never an invented empty list).
/// - `write`: `ok: false` with status 0 when nothing came back; a 2xx whose
///   body is lost is `ok` — the server acted — with no payload.
/// - `logout`: `'offline'` / `'ok'` (the pro `LogoutOutcome`).
/// - `slots`: `fetchSlots`' `{ ok, slots }` — a lost body is « we could not
///   ask », never « no opening that day ».
/// - `upload`: the presign got no answer → the upload failed, nothing was
///   reported (the person's network, not storage nor CORS — §5).
type Kind = 'read' | 'write' | 'logout' | 'slots' | 'upload';

type Row = {
  name: string;
  kind: Kind;
  call: () => Promise<unknown>;
  /// The payload fields a successful write would carry — absent when the 2xx
  /// body cannot be read.
  payload?: string[];
  /// The result carries no `status` (`{ ok }` alone).
  noStatus?: boolean;
  /// The upload's « failed » value: `null`, or the deposit's `{ ok: false }`.
  failed?: (r: unknown, offline: boolean) => void;
};

const file = new File(['x'], 'photo.jpg', { type: 'image/jpeg' });

const reviewUploadFailed = (r: unknown) => expect(r).toBeNull();
const depositUploadFailed = (r: unknown, offline: boolean) =>
  expect(r).toEqual({ ok: false, offline });

type Module = {
  file: string;
  exports: Record<string, unknown>;
  rows: Row[];
  /// Exported functions that never touch the network (pure list rules).
  pure?: string[];
};

const MODULES: Module[] = [
  {
    file: 'lib/api/account.ts',
    exports: account,
    rows: [
      // --- reads -------------------------------------------------------------
      { name: 'getMe', kind: 'read', call: () => account.getMe() },
      { name: 'listAppointments', kind: 'read', call: () => account.listAppointments() },
      { name: 'getAppointment', kind: 'read', call: () => account.getAppointment('a1') },
      { name: 'getFavorites', kind: 'read', call: () => account.getFavorites() },
      { name: 'getNotifications', kind: 'read', call: () => account.getNotifications() },
      { name: 'getNotificationPrefs', kind: 'read', call: () => account.getNotificationPrefs() },
      // --- writes ------------------------------------------------------------
      { name: 'cancelAppointment', kind: 'write', call: () => account.cancelAppointment('a1') },
      {
        name: 'rescheduleAppointment',
        kind: 'write',
        call: () => account.rescheduleAppointment('a1', '2030-01-15T09:00:00.000Z'),
      },
      { name: 'submitReview', kind: 'write', call: () => account.submitReview('a1', { rating: 5 }) },
      { name: 'addFavorite', kind: 'write', call: () => account.addFavorite('p1') },
      { name: 'removeFavorite', kind: 'write', call: () => account.removeFavorite('p1') },
      { name: 'updateName', kind: 'write', call: () => account.updateName('Awa') },
      { name: 'deleteAccount', kind: 'write', call: () => account.deleteAccount() },
      // Their callers tell « no network » from a refusal (the status), and put
      // the screen back (docs/design/web-consumer-optimistic-revert.md §3.3).
      { name: 'markNotificationRead', kind: 'write', call: () => account.markNotificationRead('n1') },
      { name: 'markAllNotificationsRead', kind: 'write', call: () => account.markAllNotificationsRead() },
      {
        name: 'updateNotificationPrefs',
        kind: 'write',
        noStatus: true,
        payload: ['prefs'],
        call: () => account.updateNotificationPrefs({ marketing: false }),
      },
      { name: 'logout', kind: 'logout', call: () => account.logout() },
    ],
  },
  {
    file: 'lib/auth/client.ts',
    exports: auth,
    rows: [
      { name: 'loginWithGoogle', kind: 'write', payload: ['user'], call: () => auth.loginWithGoogle('t') },
      {
        name: 'loginWithApple',
        kind: 'write',
        payload: ['user'],
        call: () => auth.loginWithApple({ identityToken: 't', nonce: 'n' }),
      },
      { name: 'requestEmailOtp', kind: 'write', payload: ['devCode'], call: () => auth.requestEmailOtp('a@b.ci') },
      {
        name: 'verifyEmailOtp',
        kind: 'write',
        payload: ['user'],
        call: () => auth.verifyEmailOtp('a@b.ci', '123456'),
      },
      {
        name: 'updateContactPhone',
        kind: 'write',
        call: () => auth.updateContactPhone('+2250707123456'),
      },
    ],
  },
  {
    file: 'lib/booking/client.ts',
    exports: booking,
    rows: [
      // Phone OTP — no caller since the auth overhaul; held all the same.
      { name: 'requestOtp', kind: 'write', noStatus: true, call: () => booking.requestOtp('+2250707123456') },
      {
        name: 'verifyOtp',
        kind: 'write',
        noStatus: true,
        call: () => booking.verifyOtp('+2250707123456', '1234'),
      },
      {
        name: 'createBooking',
        kind: 'write',
        noStatus: true,
        payload: ['appointment'],
        call: () =>
          booking.createBooking({
            providerId: 'p1',
            serviceIds: ['s1'],
            appointmentDateTime: '2030-01-15T09:00:00.000Z',
            artistId: null,
          }, 'test-key-00000001'),
      },
      {
        name: 'fetchSlots',
        kind: 'slots',
        call: () =>
          booking.fetchSlots({
            providerId: 'p1',
            date: '2030-01-15',
            serviceIds: ['s1'],
            durationMinutes: 30,
          }),
      },
    ],
  },
  {
    file: 'lib/booking/deposit.ts',
    exports: deposit,
    rows: [
      {
        name: 'uploadDepositProof',
        kind: 'upload',
        failed: depositUploadFailed,
        call: () => deposit.uploadDepositProof(file),
      },
      {
        name: 'attachDepositProof',
        kind: 'write',
        call: () => deposit.attachDepositProof('a1', 'deposit/u1/1.jpg'),
      },
    ],
  },
  {
    file: 'lib/account/review-photos.ts',
    exports: reviewPhotos,
    pure: ['addPhoto', 'canAddPhoto', 'removePhoto'],
    rows: [
      {
        name: 'uploadReviewPhoto',
        kind: 'upload',
        failed: reviewUploadFailed,
        call: () => reviewPhotos.uploadReviewPhoto(file),
      },
      { name: 'reportReview', kind: 'write', call: () => reviewPhotos.reportReview('r1', 'spam') },
    ],
  },
];

afterEach(() => {
  vi.unstubAllGlobals();
  captureMessage.mockClear();
});

/// Every request the stub saw — a call that never reaches `fetch` proves
/// nothing.
let calls = 0;

function stubFetch(answer: () => Response) {
  calls = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => {
      calls += 1;
      return answer();
    }),
  );
}

for (const mod of MODULES) {
  describe(`${mod.file} — the table covers every export`, () => {
    it('every exported function has a row, or is named pure (a new wrapper must join the table)', () => {
      const exported = Object.entries(mod.exports)
        .filter(([, v]) => typeof v === 'function')
        .map(([k]) => k)
        .sort();
      expect([...mod.rows.map((r) => r.name), ...(mod.pure ?? [])].sort()).toEqual(exported);
    });
  });

  describe(`${mod.file} — no network: every wrapper answers, none throws`, () => {
    for (const row of mod.rows) {
      it(row.name, async () => {
        stubFetch(() => {
          throw new TypeError('Failed to fetch');
        });
        const r = (await row.call()) as Record<string, unknown> | string | null;
        expect(calls).toBeGreaterThan(0);
        switch (row.kind) {
          case 'read':
            expect(r).toMatchObject({ status: 0 });
            break;
          case 'logout':
            expect(r).toBe('offline');
            break;
          case 'slots':
            expect(r).toEqual({ ok: false, slots: [] });
            break;
          case 'upload':
            row.failed!(r, true);
            // Only the presign was asked; storage never saw a request.
            expect(calls).toBe(1);
            expect(captureMessage).not.toHaveBeenCalled();
            break;
          case 'write':
            expect(r).toMatchObject(row.noStatus ? { ok: false } : { ok: false, status: 0 });
            break;
        }
      });
    }
  });

  describe(`${mod.file} — a 2xx whose body cannot be read`, () => {
    // What a connection cut mid-body, or something other than the BFF
    // answering, looks like: headers came, the JSON did not.
    const unreadable = () =>
      new Response('<html>Bad gateway</html>', {
        status: 200,
        headers: { 'content-type': 'text/html' },
      });

    for (const row of mod.rows) {
      it(row.name, async () => {
        stubFetch(unreadable);
        const r = (await row.call()) as Record<string, unknown> | string | null;
        switch (row.kind) {
          case 'read':
            // Not 200 with an empty list nobody sent: no answer.
            expect(r).toMatchObject({ status: 0 });
            break;
          case 'logout':
            // The BFF answered OK: its response cleared the cookies.
            expect(r).toBe('ok');
            break;
          case 'slots':
            // « Aucun créneau disponible » for a lost body was a lie.
            expect(r).toEqual({ ok: false, slots: [] });
            break;
          case 'upload':
            // The presign came back unreadable: storage was never asked, and
            // THAT is reported (a broken BFF answer, not the network).
            row.failed!(r, false);
            expect(calls).toBe(1);
            expect(captureMessage).toHaveBeenCalledTimes(1);
            break;
          case 'write': {
            const res = r as Record<string, unknown>;
            expect(res.ok).toBe(true);
            for (const field of row.payload ?? []) {
              expect(res[field] ?? undefined, `${row.name}.${field}`).toBeUndefined();
            }
            break;
          }
        }
      });
    }
  });
}

describe('an answer is still read as before', () => {
  it('a 401 stays a 401 (the redirect to /connexion keys on it)', async () => {
    stubFetch(() => new Response('{"error":"not_authenticated"}', { status: 401 }));
    expect(await account.getMe()).toEqual({ status: 401 });
    expect(await account.listAppointments()).toEqual({ status: 401, items: [] });
    expect(await account.getFavorites()).toEqual({ status: 401, favorites: [] });
    expect(await account.addFavorite('p1')).toEqual({ ok: false, status: 401 });
  });

  it('a 404 and a 403 keep their status (the detail page says « introuvable » on them)', async () => {
    stubFetch(() => new Response('{"error":"not_found"}', { status: 404 }));
    expect(await account.getAppointment('a1')).toEqual({ status: 404 });
    stubFetch(() => new Response('{"error":"forbidden"}', { status: 403 }));
    expect(await account.getAppointment('a1')).toEqual({ status: 403 });
  });

  it('a refused write keeps its status and code', async () => {
    stubFetch(() => new Response('{"error":"future_bookings"}', { status: 409 }));
    expect(await account.deleteAccount()).toEqual({
      ok: false,
      status: 409,
      error: 'future_bookings',
    });
    stubFetch(() => new Response('{"error":"slot_unavailable"}', { status: 409 }));
    expect(await booking.createBooking({
      providerId: 'p1',
      serviceIds: ['s1'],
      appointmentDateTime: '2030-01-15T09:00:00.000Z',
      artistId: null,
    }, 'test-key-00000001')).toEqual({ ok: false, error: 'slot_unavailable' });
    stubFetch(() => new Response('{"error":"otp_invalid"}', { status: 400 }));
    expect(await auth.verifyEmailOtp('a@b.ci', '000000')).toEqual({
      ok: false,
      status: 400,
      error: 'otp_invalid',
    });
  });

  it('a logout the BFF refused is `failed`, not `ok` — the cookies are still there', async () => {
    stubFetch(() => new Response('{}', { status: 500 }));
    expect(await account.logout()).toBe('failed');
  });

  it('a 200 with a body is that body', async () => {
    stubFetch(
      () => new Response(JSON.stringify({ items: [{ id: 'a1', status: 'confirmed' }] }), { status: 200 }),
    );
    expect(await account.listAppointments()).toEqual({
      status: 200,
      items: [{ id: 'a1', status: 'confirmed' }],
    });
    stubFetch(() => new Response(JSON.stringify({ id: 'u1', name: 'Awa' }), { status: 200 }));
    expect(await account.getMe()).toEqual({ status: 200, user: { id: 'u1', name: 'Awa' } });
  });

  it('the notifications feed reads a 200 without `items` as a failed read', async () => {
    // Left lenient by export-unreadable-200.md §5; made strict with the other
    // list reads (hygiene-batch9.md §2.10, B9.11): « no notifications » is
    // the server's to say, with `items: []`.
    stubFetch(() => new Response('{}', { status: 200 }));
    expect(await account.getNotifications()).toEqual({ status: 0, items: [] });
  });

  it('a refused presign is still reported (storage, not the network)', async () => {
    stubFetch(() => new Response('{}', { status: 400 }));
    expect(await deposit.uploadDepositProof(file)).toEqual({ ok: false, offline: false });
    expect(await reviewPhotos.uploadReviewPhoto(file)).toBeNull();
    expect(captureMessage).toHaveBeenCalledTimes(2);
  });
});

/// docs/design/export-unreadable-200.md §2.2 / §4 — the reads « Mes données »
/// is made of require their shape. The server always sends the user with its
/// `id`, and the BFF always sends `items` and `favorites`, so a 200 without
/// them is a failed read (status 0): « Mes données » refuses, « Mon compte »
/// shows its error — never a profile of nothing, never an empty list nobody
/// sent. #620 had pinned the opposite for `getFavorites` (« the server said
/// so »); the BFF said so only because it manufactured the key.
describe('a 200 without its shape is a failed read', () => {
  const ok = (body: string) => () => new Response(body, { status: 200 });

  it.each(['{}', '[]', '"x"', '{"id":7,"name":"Awa"}', '{"name":"Awa"}'])(
    'getMe on %s → status 0, not a user',
    async (body) => {
      stubFetch(ok(body));
      expect(await account.getMe()).toEqual({ status: 0 });
    },
  );

  it.each(['{}', '{"items":null}', '{"items":"x"}', '{"items":{}}', '[]'])(
    'listAppointments on %s → status 0, not « 0 rendez-vous »',
    async (body) => {
      stubFetch(ok(body));
      expect(await account.listAppointments()).toEqual({ status: 0, items: [] });
    },
  );

  it.each(['{}', '{"favorites":null}', '{"favorites":"x"}', '{"favorites":{}}', '[]'])(
    'getFavorites on %s → status 0, not « Aucun favori »',
    async (body) => {
      stubFetch(ok(body));
      expect(await account.getFavorites()).toEqual({ status: 0, favorites: [] });
    },
  );

  it('CONTROL — a real empty list is a 200, and so is a user with its id', async () => {
    stubFetch(ok('{"items":[],"page":1,"pageSize":0,"total":0}'));
    expect(await account.listAppointments()).toEqual({ status: 200, items: [] });
    stubFetch(ok('{"favorites":[]}'));
    expect(await account.getFavorites()).toEqual({ status: 200, favorites: [] });
    stubFetch(ok('{"id":"u1"}'));
    expect(await account.getMe()).toEqual({ status: 200, user: { id: 'u1' } });
  });
});
