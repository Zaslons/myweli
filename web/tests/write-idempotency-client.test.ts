import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  IDEMPOTENCY_KEY_HEADER,
  MAX_IN_PROGRESS_WAITS,
  SubmissionKey,
  sendIdempotent,
} from '../lib/api/network';
import {
  addClientNote,
  createManualBooking,
  inviteMember,
} from '../lib/api/pro';
import { createBooking } from '../lib/booking/client';

/// docs/design/write-idempotency.md §4 — a creating write carries one
/// `Idempotency-Key` per form submission; an answer lost on the way (nothing
/// came back, or a gateway's page) is asked again ONCE, at once, with the SAME
/// key — the server replays the write it did instead of a 409 on the
/// person's own slot or a second booking. A 2xx whose body was lost is asked
/// again too: the replay brings the body (the deposit block). « Already
/// running » waits and asks again, three times at most.

type Answer = 'throw' | { status: number; body?: unknown; raw?: string };

/// The BFF's answers, one per request, in order (the last one repeats).
function bff(...answers: Answer[]) {
  const calls: { url: string; key: string | null; body: unknown }[] = [];
  let i = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const headers = new Headers(init?.headers);
      calls.push({
        url: String(url),
        key: headers.get(IDEMPOTENCY_KEY_HEADER),
        body: init?.body ? JSON.parse(String(init.body)) : undefined,
      });
      const a = answers[Math.min(i, answers.length - 1)];
      i += 1;
      if (a === 'throw') throw new TypeError('Failed to fetch');
      return new Response(a.raw ?? JSON.stringify(a.body ?? {}), {
        status: a.status,
      });
    }),
  );
  return calls;
}

afterEach(() => vi.unstubAllGlobals());

const noWait = { wait: async () => {} };
const hasId = (b: { id?: string } | undefined) => Boolean(b?.id);
const send = (key = 'key-0000000001') =>
  sendIdempotent<{ id?: string }>(
    '/api/x',
    { method: 'POST', body: '{}' },
    key,
    { complete: hasId, ...noWait },
  );

describe('sendIdempotent', () => {
  it('sends the key; an answer that arrives is the answer — asked once', async () => {
    const calls = bff({ status: 201, body: { id: 'a1' } });
    expect(await send()).toEqual({ status: 201, body: { id: 'a1' } });
    expect(calls).toHaveLength(1);
    expect(calls[0].key).toBe('key-0000000001');
  });

  it('nothing came back → asked again ONCE with the same key → its answer', async () => {
    const calls = bff('throw', { status: 201, body: { id: 'a1' } });
    expect(await send()).toEqual({ status: 201, body: { id: 'a1' } });
    expect(calls.map((c) => c.key)).toEqual(['key-0000000001', 'key-0000000001']);
  });

  it('a gateway’s answer (502, 503, 504) is a lost answer too', async () => {
    for (const status of [502, 503, 504]) {
      const calls = bff({ status, raw: '<html>' }, { status: 201, body: { id: 'a1' } });
      expect((await send()).status, String(status)).toBe(201);
      expect(calls).toHaveLength(2);
    }
  });

  it('lost twice → status 0 (« nothing answered »), never a third try', async () => {
    const calls = bff('throw');
    expect((await send()).status).toBe(0);
    expect(calls).toHaveLength(2);
  });

  it('a 2xx whose body was lost → asked again → the replay brings it', async () => {
    const calls = bff({ status: 201, raw: '{"id":' }, { status: 201, body: { id: 'a1' } });
    expect(await send()).toEqual({ status: 201, body: { id: 'a1' } });
    expect(calls).toHaveLength(2);
  });

  it('a 2xx without its body twice → still a success (the write was done), without the body', async () => {
    bff({ status: 201, raw: '' });
    const r = await send();
    expect(r.status).toBe(201);
    expect(r.body).toBeUndefined();
  });

  it('« already running » → wait, ask again with the same key, three times at most', async () => {
    const waits: number[] = [];
    const calls = bff(
      { status: 409, body: { error: 'request_in_progress' } },
      { status: 409, body: { error: 'request_in_progress' } },
      { status: 201, body: { id: 'a1' } },
    );
    const r = await sendIdempotent<{ id?: string }>(
      '/api/x',
      { method: 'POST', body: '{}' },
      'key-0000000001',
      { complete: hasId, wait: async (ms) => void waits.push(ms) },
    );
    expect(r.status).toBe(201);
    expect(calls.every((c) => c.key === 'key-0000000001')).toBe(true);
    expect(waits).toHaveLength(2);
    expect(waits.every((ms) => ms > 0)).toBe(true);

    const always = bff({ status: 409, body: { error: 'request_in_progress' } });
    expect((await send()).status, 'still running: nothing answered').toBe(0);
    expect(always).toHaveLength(1 + MAX_IN_PROGRESS_WAITS);
  });

  it('a real refusal is the answer — never asked again', async () => {
    for (const [status, error] of [
      [409, 'slot_unavailable'],
      [400, 'invalid_input'],
      [422, 'idempotency_key_reused'],
      [500, 'internal'],
    ] as const) {
      const calls = bff({ status, body: { error } });
      expect(await send()).toEqual({ status, error });
      expect(calls, error).toHaveLength(1);
    }
  });
});

describe('SubmissionKey — one key per submission of a form', () => {
  it('the same form → the same key; a changed form → a new one', () => {
    const k = new SubmissionKey();
    const first = k.for({ slot: '10:00' });
    expect(first).toMatch(/^[A-Za-z0-9_-]{8,128}$/);
    expect(k.for({ slot: '10:00' })).toBe(first);
    const other = k.for({ slot: '11:00' });
    expect(other).not.toBe(first);
    expect(k.for({ slot: '10:00' }), 'back to the first form: a new submission').not.toBe(first);
  });

  it('after a success the next submission takes a new key, even unchanged', () => {
    const k = new SubmissionKey();
    const first = k.for({ body: 'OK' });
    k.settle();
    expect(k.for({ body: 'OK' })).not.toBe(first);
  });
});

describe('the four writes', () => {
  const appt = { id: 'a1', status: 'pending', depositAmount: 5000 };
  const booking = {
    providerId: 'p1',
    serviceIds: ['s1'],
    appointmentDateTime: '2026-10-22T10:00:00.000Z',
    artistId: null,
  };

  it('the client’s booking: the key crosses, a lost answer is asked again, the deposit comes back', async () => {
    const calls = bff('throw', { status: 201, body: { ok: true, appointment: appt } });
    const r = await createBooking(booking, 'book-key-0001', noWait);
    expect(r).toEqual({ ok: true, appointment: appt });
    expect(calls.map((c) => [c.url, c.key])).toEqual([
      ['/api/bookings', 'book-key-0001'],
      ['/api/bookings', 'book-key-0001'],
    ]);
  });

  it('the client’s booking lost twice → `lost`, not a refusal', async () => {
    bff('throw');
    expect(await createBooking(booking, 'book-key-0001', noWait)).toEqual({ ok: false, lost: true });
  });

  it('the client’s booking: a 2xx without its body is asked again for the deposit block', async () => {
    const calls = bff(
      { status: 201, body: { ok: true, appointment: {} } },
      { status: 201, body: { ok: true, appointment: appt } },
    );
    expect((await createBooking(booking, 'book-key-0001', noWait)).appointment).toEqual(appt);
    expect(calls).toHaveLength(2);
  });

  it('the client’s booking refused: the code, unchanged', async () => {
    bff({ status: 409, body: { error: 'slot_unavailable' } });
    expect(await createBooking(booking, 'book-key-0001', noWait)).toEqual({
      ok: false,
      error: 'slot_unavailable',
    });
  });

  it('the salon’s booking: the key crosses, a lost answer is asked again', async () => {
    const calls = bff({ status: 502, raw: '' }, { status: 201, body: { id: 'm1' } });
    const r = await createManualBooking(
      'p1',
      { serviceIds: ['s1'], appointmentDateTime: '2026-10-22T10:00:00.000Z' },
      'manual-key-01',
      noWait,
    );
    expect(r).toEqual({ ok: true, status: 201, appt: { id: 'm1' } });
    expect(calls.map((c) => c.key)).toEqual(['manual-key-01', 'manual-key-01']);
  });

  it('a note: the key crosses, a lost answer is asked again', async () => {
    const note = { id: 'n1', body: 'Allergie' };
    const calls = bff('throw', { status: 201, body: note });
    const r = await addClientNote('p1', 'c1', 'Allergie', 'note-key-0001', noWait);
    expect(r).toEqual({ ok: true, status: 201, note });
    expect(calls.map((c) => c.key)).toEqual(['note-key-0001', 'note-key-0001']);
  });

  it('an invitation: the key crosses, a lost answer is asked again', async () => {
    const member = { id: 'mem1', email: 'a@b.ci', role: 'manager', status: 'pending' };
    const calls = bff('throw', { status: 201, body: member });
    const r = await inviteMember({ email: 'a@b.ci', role: 'manager' }, 'invite-key-01', noWait);
    expect(r).toEqual({ ok: true, status: 201, member });
    expect(calls.map((c) => c.key)).toEqual(['invite-key-01', 'invite-key-01']);
  });

  it('lost twice: status 0 on the three Pro writes', async () => {
    bff('throw');
    expect(
      (await createManualBooking('p1', { serviceIds: ['s1'], appointmentDateTime: 'x' }, 'manual-key-01', noWait))
        .status,
    ).toBe(0);
    expect((await addClientNote('p1', 'c1', 'x', 'note-key-0001', noWait)).status).toBe(0);
    expect((await inviteMember({ email: 'a@b.ci', role: 'manager' }, 'invite-key-01', noWait)).status).toBe(0);
  });
});
