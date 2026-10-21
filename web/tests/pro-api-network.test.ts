import { afterEach, describe, expect, it, vi } from 'vitest';
import * as pro from '../lib/api/pro';

/// docs/design/web-pro-network-failure.md §2 — a wrapper of `lib/api/pro.ts`
/// never throws. A dropped connection is status 0 (or `ok: false`), and the
/// non-200 branch every caller already has is its error state; before, the
/// rejection went through to a page that never caught it, and the page stayed
/// on its skeleton for ever.

/// How a call's result is judged.
/// - `read`: a GET — status 0 when no usable answer came back (a 2xx body that
///   cannot be read included: never an invented empty list).
/// - `write`: `ok: false` with status 0 when nothing came back; a 2xx whose
///   body is lost is `ok` — the server acted — with no payload.
/// - `logout`: its own shape (`'offline'`).
type Kind = 'read' | 'write' | 'logout';

type Row = {
  name: keyof typeof pro;
  kind: Kind;
  call: () => Promise<unknown>;
  /// The payload fields a successful write would carry — absent when the 2xx
  /// body cannot be read.
  payload?: string[];
  /// The result carries no `status` (the oldest auth wrappers).
  noStatus?: boolean;
  /// The result is `{ status }`, not `{ ok, status }` (`submitKyc`).
  statusOnly?: boolean;
};

const service = {
  name: 'Coupe',
  price: 5000,
  durationMinutes: 30,
} as unknown as Parameters<typeof pro.createService>[1];
const artist = { name: 'Awa' } as unknown as Parameters<typeof pro.createArtist>[1];

const ROWS: Row[] = [
  // --- reads ---------------------------------------------------------------
  { name: 'getMyProvider', kind: 'read', call: () => pro.getMyProvider() },
  { name: 'getMySalons', kind: 'read', call: () => pro.getMySalons() },
  { name: 'listProAppointments', kind: 'read', call: () => pro.listProAppointments() },
  { name: 'getKycStatus', kind: 'read', call: () => pro.getKycStatus() },
  { name: 'listProviderReviews', kind: 'read', call: () => pro.listProviderReviews('p1') },
  { name: 'getProAppointment', kind: 'read', call: () => pro.getProAppointment('a1') },
  { name: 'getSalonSubscription', kind: 'read', call: () => pro.getSalonSubscription('p1') },
  { name: 'getDashboard', kind: 'read', call: () => pro.getDashboard('p1') },
  { name: 'getEarnings', kind: 'read', call: () => pro.getEarnings('p1', null) },
  { name: 'getDepositPolicy', kind: 'read', call: () => pro.getDepositPolicy('p1') },
  { name: 'getTeamMembers', kind: 'read', call: () => pro.getTeamMembers() },
  { name: 'getMyInvitations', kind: 'read', call: () => pro.getMyInvitations() },
  { name: 'listClients', kind: 'read', call: () => pro.listClients('p1') },
  // #618's walk over every page — built on listClients, so it never throws either.
  { name: 'listAllClients', kind: 'read', call: () => pro.listAllClients('p1') },
  { name: 'getClientCard', kind: 'read', call: () => pro.getClientCard('p1', 'c1') },
  { name: 'getClientVisits', kind: 'read', call: () => pro.getClientVisits('p1', 'c1') },
  { name: 'getJournalDay', kind: 'read', call: () => pro.getJournalDay('p1', '2026-10-16') },
  // A read like the others since docs/design/web-pro-journal-panel-deposit.md
  // §5: it used to be `string | null`, and `null` was every failure at once —
  // the detail page's « Voir le justificatif » did nothing, and said nothing.
  { name: 'proDepositScreenshotUrl', kind: 'read', call: () => pro.proDepositScreenshotUrl('a1') },
  // The salon's notification center (web-pro-notifications.md).
  { name: 'getProNotifications', kind: 'read', call: () => pro.getProNotifications() },
  // The member's « Alertes par e-mail » (salon-email-alerts.md §4).
  { name: 'getProNotificationPrefs', kind: 'read', call: () => pro.getProNotificationPrefs() },
  // --- writes --------------------------------------------------------------
  { name: 'requestOtpPro', kind: 'write', noStatus: true, call: () => pro.requestOtpPro('+2250700000000') },
  { name: 'verifyOtpPro', kind: 'write', noStatus: true, call: () => pro.verifyOtpPro('+2250700000000', '1234') },
  {
    name: 'addSalon',
    kind: 'write',
    payload: ['salon'],
    call: () => pro.addSalon({ businessName: 'B', businessType: 'salon' }),
  },
  { name: 'selectSalon', kind: 'write', payload: ['profile'], call: () => pro.selectSalon('s1') },
  { name: 'publishSalon', kind: 'write', call: () => pro.publishSalon('p1') },
  { name: 'markProNotificationRead', kind: 'write', call: () => pro.markProNotificationRead('n1') },
  { name: 'markAllProNotificationsRead', kind: 'write', call: () => pro.markAllProNotificationsRead() },
  { name: 'setProEmailAlerts', kind: 'write', payload: ['prefs'], call: () => pro.setProEmailAlerts(false) },
  // This browser's notification token (web-pro-browser-push.md §5).
  { name: 'registerProDevice', kind: 'write', call: () => pro.registerProDevice('tok') },
  { name: 'unregisterProDevice', kind: 'write', call: () => pro.unregisterProDevice('tok') },
  {
    name: 'submitKyc',
    kind: 'write',
    statusOnly: true,
    payload: ['kyc'],
    call: () => pro.submitKyc([]),
  },
  { name: 'proAction', kind: 'write', call: () => pro.proAction('a1', 'accept') },
  { name: 'createService', kind: 'write', call: () => pro.createService('p1', service) },
  { name: 'updateService', kind: 'write', call: () => pro.updateService('p1', 's1', service) },
  { name: 'deleteService', kind: 'write', call: () => pro.deleteService('p1', 's1') },
  { name: 'createArtist', kind: 'write', call: () => pro.createArtist('p1', artist) },
  {
    name: 'createArtistReturning',
    kind: 'write',
    payload: ['artist'],
    call: () => pro.createArtistReturning('p1', artist),
  },
  { name: 'updateArtist', kind: 'write', call: () => pro.updateArtist('p1', 'ar1', artist) },
  { name: 'deleteArtist', kind: 'write', call: () => pro.deleteArtist('p1', 'ar1') },
  {
    name: 'saveAvailability',
    kind: 'write',
    call: () =>
      pro.saveAvailability('p1', {
        providerId: 'p1',
        weeklySchedule: {},
        blockedDates: [],
        bufferMinutes: 0,
      }),
  },
  { name: 'chooseOffer', kind: 'write', payload: ['offer'], call: () => pro.chooseOffer('p1', 'pro') },
  { name: 'deleteProAccount', kind: 'write', call: () => pro.deleteProAccount() },
  { name: 'updateProviderProfile', kind: 'write', call: () => pro.updateProviderProfile('p1', {}) },
  {
    name: 'saveDepositPolicy',
    kind: 'write',
    call: () =>
      pro.saveDepositPolicy('p1', {
        depositRequired: false,
        depositPercentage: 0.3,
        cancellationWindowHours: 24,
      } as Parameters<typeof pro.saveDepositPolicy>[1]),
  },
  { name: 'saveGallery', kind: 'write', call: () => pro.saveGallery('p1', []) },
  { name: 'saveBeforeAfters', kind: 'write', call: () => pro.saveBeforeAfters('p1', []) },
  { name: 'logoutPro', kind: 'logout', call: () => pro.logoutPro() },
  { name: 'loginProWithGoogle', kind: 'write', noStatus: true, call: () => pro.loginProWithGoogle('t') },
  {
    name: 'loginProWithApple',
    kind: 'write',
    noStatus: true,
    call: () => pro.loginProWithApple({ identityToken: 't', nonce: 'n' }),
  },
  { name: 'requestEmailOtpPro', kind: 'write', call: () => pro.requestEmailOtpPro('a@b.ci') },
  { name: 'verifyEmailOtpPro', kind: 'write', call: () => pro.verifyEmailOtpPro('a@b.ci', '1234') },
  {
    name: 'acceptInvitationPublic',
    kind: 'write',
    call: () => pro.acceptInvitationPublic({ invitationId: 'i1', idToken: 't' }),
  },
  {
    name: 'declineInvitationPublic',
    kind: 'write',
    call: () => pro.declineInvitationPublic({ invitationId: 'i1', idToken: 't' }),
  },
  {
    name: 'inviteMember',
    kind: 'write',
    payload: ['member'],
    call: () => pro.inviteMember({ email: 'a@b.ci', role: 'manager' }, 'test-key-00000001'),
  },
  {
    name: 'changeMemberRole',
    kind: 'write',
    payload: ['member'],
    call: () => pro.changeMemberRole('m1', { role: 'manager' }),
  },
  { name: 'revokeMember', kind: 'write', payload: ['member'], call: () => pro.revokeMember('m1') },
  { name: 'resendInvitation', kind: 'write', payload: ['member'], call: () => pro.resendInvitation('m1') },
  { name: 'acceptMyInvitation', kind: 'write', call: () => pro.acceptMyInvitation('i1') },
  { name: 'declineMyInvitation', kind: 'write', call: () => pro.declineMyInvitation('i1') },
  // B6.6: the salon reports a review of its own salon.
  { name: 'reportSalonReview', kind: 'write', call: () => pro.reportSalonReview('r1', 'Insultes') },
  {
    name: 'addClient',
    kind: 'write',
    payload: ['clientId'],
    call: () => pro.addClient('p1', { name: 'Awa', phone: '+2250700000000' }),
  },
  { name: 'updateClientTags', kind: 'write', call: () => pro.updateClientTags('p1', 'c1', ['VIP']) },
  {
    name: 'updateClientPhone',
    kind: 'write',
    call: () => pro.updateClientPhone('p1', 'c1', '+2250700000000'),
  },
  { name: 'addClientNote', kind: 'write', payload: ['note'], call: () => pro.addClientNote('p1', 'c1', 'x', 'test-key-00000001') },
  { name: 'deleteClientNote', kind: 'write', call: () => pro.deleteClientNote('p1', 'c1', 'n1') },
  {
    name: 'rescheduleAppointment',
    kind: 'write',
    call: () => pro.rescheduleAppointment('a1', '2030-01-15T09:00:00.000Z'),
  },
  { name: 'arriveAppointment', kind: 'write', call: () => pro.arriveAppointment('a1') },
  {
    name: 'createManualBooking',
    kind: 'write',
    payload: ['appt'],
    call: () =>
      pro.createManualBooking(
        'p1',
        { serviceIds: ['s1'], appointmentDateTime: '2030-01-15T09:00:00.000Z' },
        'test-key-00000001',
      ),
  },
  {
    name: 'registerPro',
    kind: 'write',
    call: () =>
      pro.registerPro(
        { idToken: 't' },
        { businessName: 'B', businessType: 'salon', phoneNumber: '+2250700000000' },
      ),
  },
];

afterEach(() => {
  vi.unstubAllGlobals();
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

describe('lib/api/pro.ts — the table covers every wrapper', () => {
  it('every exported function has a row (a new wrapper must join the table)', () => {
    const exported = Object.entries(pro)
      .filter(([, v]) => typeof v === 'function')
      .map(([k]) => k)
      .sort();
    expect(ROWS.map((r) => r.name).sort()).toEqual(exported);
  });
});

describe('lib/api/pro.ts — no network: every wrapper answers, none throws', () => {
  for (const row of ROWS) {
    it(`${row.name}`, async () => {
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
        case 'write':
          expect(r).toMatchObject(
            row.statusOnly
              ? { status: 0 }
              : row.noStatus
                ? { ok: false }
                : { ok: false, status: 0 },
          );
          break;
      }
    });
  }
});

describe('lib/api/pro.ts — a 2xx whose body cannot be read', () => {
  // What a connection cut mid-body, or something other than the BFF
  // answering, looks like: headers came, the JSON did not.
  const unreadable = () =>
    new Response('<html>Bad gateway</html>', {
      status: 200,
      headers: { 'content-type': 'text/html' },
    });

  for (const row of ROWS) {
    it(`${row.name}`, async () => {
      stubFetch(unreadable);
      const r = (await row.call()) as Record<string, unknown> | string | null;
      switch (row.kind) {
        case 'read':
          // Not 200 with an empty list nobody sent: no answer.
          expect(r).toMatchObject({ status: 0 });
          break;
        case 'logout':
          expect(r).toBe('ok');
          break;
        case 'write': {
          const res = r as Record<string, unknown>;
          if (row.statusOnly) expect(res.status).toBe(200);
          else expect(res.ok).toBe(true);
          for (const field of row.payload ?? []) {
            expect(res[field], `${row.name}.${field}`).toBeUndefined();
          }
          break;
        }
      }
    });
  }
});

describe('lib/api/pro.ts — an answer is still read as before', () => {
  it('a 401 stays a 401 (the redirect to /pro/connexion keys on it)', async () => {
    stubFetch(() => new Response('{"error":"unauthorized"}', { status: 401 }));
    expect(await pro.getMyProvider()).toMatchObject({ status: 401 });
    expect(await pro.listProAppointments()).toMatchObject({ status: 401 });
  });

  it('a 403 keeps its code (the membership probe acts on not_a_member)', async () => {
    stubFetch(() => new Response('{"error":"not_a_member"}', { status: 403 }));
    expect(await pro.getMyProvider()).toEqual({ status: 403, error: 'not_a_member' });
  });

  it('a 404 stays a 404 (the abonnement setup state, « introuvable »)', async () => {
    stubFetch(() => new Response('{}', { status: 404 }));
    expect(await pro.getSalonSubscription('p1')).toEqual({ status: 404 });
    expect(await pro.getClientCard('p1', 'c1')).toEqual({ status: 404 });
  });

  it('the deposit screenshot: its URL, its refusal, and a 200 without a URL', async () => {
    // docs/design/web-pro-journal-panel-deposit.md §5 — the screen tells a
    // cut connection (status 0) from a refusal (any other status), so the
    // wrapper must keep them apart. A 200 that names no URL is nothing usable:
    // status 0, like any other unreadable 2xx.
    stubFetch(() => new Response('{"url":"https://r2.test/p.jpg"}', { status: 200 }));
    expect(await pro.proDepositScreenshotUrl('a1')).toEqual({
      status: 200,
      url: 'https://r2.test/p.jpg',
    });
    stubFetch(() => new Response('{"error":"not_found"}', { status: 404 }));
    expect(await pro.proDepositScreenshotUrl('a1')).toEqual({ status: 404 });
    stubFetch(() => new Response('{}', { status: 200 }));
    expect(await pro.proDepositScreenshotUrl('a1')).toEqual({ status: 0 });
  });

  it('a refused write keeps its status and code', async () => {
    stubFetch(() => new Response('{"error":"slot_unavailable"}', { status: 409 }));
    expect(await pro.rescheduleAppointment('a1', 'x')).toEqual({
      ok: false,
      status: 409,
      error: 'slot_unavailable',
    });
    expect(await pro.saveGallery('p1', [])).toEqual({
      ok: false,
      status: 409,
      error: 'slot_unavailable',
    });
  });

  it('a 200 with a body is that body', async () => {
    stubFetch(
      () => new Response(JSON.stringify({ items: [{ id: 'a1', status: 'confirmed' }] }), { status: 200 }),
    );
    expect(await pro.listProAppointments()).toEqual({
      status: 200,
      items: [{ id: 'a1', status: 'confirmed' }],
    });
  });

  it('a 200 list without `items` is an empty list — the server said so', async () => {
    stubFetch(() => new Response('{}', { status: 200 }));
    expect(await pro.getTeamMembers()).toEqual({ status: 200, items: [] });
  });
});

/// docs/design/export-unreadable-200.md §2.2 / §4 — the salon export's reads
/// require their shape. The server always sends `items`, `totalEarnings` and
/// `transactions`, so a 200 without them is a failed read (status 0): the
/// export refuses and the pages show their error. Before, `{}` was « no
/// bookings » in the file, and an earnings `{}` broke the assembly with
/// nothing said. (`getTeamMembers` above keeps its reading: it feeds no
/// export — §5.)
describe('lib/api/pro.ts — a 200 without its shape is a failed read', () => {
  const ok = (body: string) => () => new Response(body, { status: 200 });

  it.each(['{}', '{"items":null}', '{"items":"x"}', '{"items":{}}', '[]'])(
    'listProAppointments on %s → status 0, not an empty agenda',
    async (body) => {
      stubFetch(ok(body));
      expect(await pro.listProAppointments()).toEqual({ status: 0, items: [] });
    },
  );

  it.each([
    '{}',
    '[]',
    '{"totalEarnings":0,"transactions":null}',
    '{"totalEarnings":0,"transactions":"x"}',
    '{"totalEarnings":0,"transactions":{}}',
    '{"transactions":[]}',
    '{"totalEarnings":"0","transactions":[]}',
  ])('getEarnings on %s → status 0, not earnings', async (body) => {
    stubFetch(ok(body));
    expect(await pro.getEarnings('p1', null)).toEqual({ status: 0 });
  });

  it('CONTROL — an empty agenda and a salon that earned nothing are 200s', async () => {
    stubFetch(ok('{"items":[],"page":1,"pageSize":0,"total":0}'));
    expect(await pro.listProAppointments()).toEqual({ status: 200, items: [] });
    stubFetch(ok('{"totalEarnings":0,"currency":"XOF","transactions":[]}'));
    expect(await pro.getEarnings('p1', null)).toEqual({
      status: 200,
      earnings: { totalEarnings: 0, currency: 'XOF', transactions: [] },
    });
  });
});
