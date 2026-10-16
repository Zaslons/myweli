import { spawn } from 'node:child_process';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

/// The e2e stub's refusals follow the backend's — for the client-card PATCH
/// (docs/design/phone-leftovers.md §8, §11) and for the salon registration.
///
/// The Playwright specs only ever meet the codes the web sends for, so a stub
/// that answers in another order, or with a code the backend never sends,
/// stays green there while saying something untrue about the server. The
/// order checked here is the backend's, read off its code:
/// - PATCH: `routes/providers/[id]/clients/[clientId]/index.dart` (the field
///   types, then « neither field »), then `ClientsService.updateClient`
///   (the capability, the tag set, the card, then the number's rules);
/// - register: `routes/auth/provider/register.dart` (name and type, then the
///   number, then the identity proof).
///
/// It talks to the RUNNING stub, as `stub-clock.test.ts` does: a copy of its
/// rules here would guard nothing.
const PORT = 8797;
const BASE = `http://127.0.0.1:${PORT}`;
const OWNER = { authorization: 'Bearer stub-pro-access' };
/// A staff member: no `clients.view`.
const STAFF = { authorization: 'Bearer pro-staff-access' };

let child: ReturnType<typeof spawn>;

beforeAll(async () => {
  child = spawn('node', ['tests/e2e/stub-api.mjs'], {
    env: { ...process.env, STUB_PORT: String(PORT), TZ: 'UTC' },
    stdio: 'ignore',
  });
  const deadline = Date.now() + 10_000;
  for (;;) {
    try {
      await fetch(`${BASE}/localities`);
      return;
    } catch {
      if (Date.now() > deadline) throw new Error('stub did not start');
      await new Promise((r) => setTimeout(r, 100));
    }
  }
});

afterAll(() => child?.kill());

async function call(
  method: string,
  path: string,
  body?: unknown,
  headers: Record<string, string> = OWNER,
) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'content-type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

const patch = (id: string, body: unknown, headers?: Record<string, string>) =>
  call('PATCH', `/providers/p1/clients/${id}`, body, headers);

/// A fresh guest card of its own (the stub is one process for the file).
let seq = 0;
async function guest(): Promise<{ id: string; phone: string }> {
  seq += 1;
  const phone = `+22501${String(seq).padStart(8, '0')}`;
  const r = await call('POST', '/providers/p1/clients', {
    name: `Invitée ${seq}`,
    phone,
  });
  expect(r.status).toBe(201);
  return { id: r.body.id, phone };
}

describe('stub PATCH /providers/{id}/clients/{clientId} — the backend’s order', () => {
  it('a field of the wrong JSON type is invalid_body — before any rule, a linked card’s included', async () => {
    const g = await guest();
    expect(await patch(g.id, { phone: 7 })).toMatchObject({
      status: 400,
      body: { error: 'invalid_body' },
    });
    expect(await patch(g.id, { tags: 'VIP' })).toMatchObject({
      status: 400,
      body: { error: 'invalid_body' },
    });
    // sc1 is linked: the type is read before the card is.
    expect(await patch('sc1', { phone: 7 })).toMatchObject({
      status: 400,
      body: { error: 'invalid_body' },
    });
  });

  it('neither field is invalid_tags — the route’s code for a body without tags', async () => {
    const g = await guest();
    expect(await patch(g.id, {})).toMatchObject({
      status: 400,
      body: { error: 'invalid_tags' },
    });
    expect(await patch(g.id, { tags: null, phone: null })).toMatchObject({
      status: 400,
      body: { error: 'invalid_tags' },
    });
  });

  it('no clients.view is 403 — before the card is looked up (no 404 to probe ids with)', async () => {
    expect(await patch('no-such-card', { tags: [] }, STAFF)).toMatchObject({
      status: 403,
      body: { error: 'forbidden' },
    });
    expect(await patch('no-such-card', { tags: [] })).toMatchObject({
      status: 404,
      body: { error: 'not_found' },
    });
  });

  it('a tag set the service would not keep is invalid_tags', async () => {
    const g = await guest();
    expect(await patch(g.id, { tags: ['  '] })).toMatchObject({
      status: 400,
      body: { error: 'invalid_tags' },
    });
    expect(await patch(g.id, { tags: ['x'.repeat(25)] })).toMatchObject({
      status: 400,
      body: { error: 'invalid_tags' },
    });
    const eleven = Array.from({ length: 11 }, (_, i) => `t${i}`);
    expect(await patch(g.id, { tags: eleven })).toMatchObject({
      status: 400,
      body: { error: 'invalid_tags' },
    });
    // Trimmed and de-duplicated when kept.
    const ok = await patch(g.id, { tags: [' VIP ', 'VIP', 'Fidèle'] });
    expect(ok.status).toBe(200);
    expect(ok.body.tags).toEqual(['VIP', 'Fidèle']);
  });

  it('a linked card is client_linked — before the number is judged', async () => {
    expect(await patch('sc1', { phone: 'pas un numéro' })).toMatchObject({
      status: 409,
      body: { error: 'client_linked' },
    });
  });

  it('a card with neither account nor number is client_anonymized — before the number is judged', async () => {
    // An erased account's card. The stub's POST takes a card without a number
    // (the backend's does not) — the one way to hold such a card here.
    const r = await call('POST', '/providers/p1/clients', { name: 'Effacée' });
    expect(r.status).toBe(201);
    expect(await patch(r.body.id, { phone: '+2250500000001' })).toMatchObject({
      status: 409,
      body: { error: 'client_anonymized' },
    });
    expect(await patch(r.body.id, { phone: 'pas un numéro' })).toMatchObject({
      status: 409,
      body: { error: 'client_anonymized' },
    });
  });

  it('a number the shared rule refuses is invalid_phone — empty included', async () => {
    const g = await guest();
    for (const phone of ['+2250700000', '', '0700000001']) {
      expect(await patch(g.id, { phone })).toMatchObject({
        status: 400,
        body: { error: 'invalid_phone' },
      });
    }
  });

  it('another card’s number is client_exists with its id — and nothing changes', async () => {
    const g = await guest();
    expect(await patch(g.id, { phone: '+2250700000002' })).toMatchObject({
      status: 409,
      body: { error: 'client_exists', clientId: 'sc2' },
    });
    const card = await call('GET', `/providers/p1/clients/${g.id}`);
    expect(card.body.phone).toBe(g.phone);
  });

  it('a free number is taken, and the card says it stays editable', async () => {
    const g = await guest();
    const next = `+22505${String(seq).padStart(8, '0')}`;
    const r = await patch(g.id, { phone: next });
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ id: g.id, phone: next, phoneEditable: true });
  });

  it('phoneEditable: a guest with a number yes; a linked card no', async () => {
    expect((await call('GET', '/providers/p1/clients/sc2')).body.phoneEditable).toBe(
      true,
    );
    expect((await call('GET', '/providers/p1/clients/sc1')).body.phoneEditable).toBe(
      false,
    );
  });
});

describe('stub POST /auth/provider/register — the backend’s order', () => {
  const register = (body: Record<string, unknown>) =>
    call('POST', '/auth/provider/register', body, {});
  const IDENTITY = { email: 'ordre@salon.test', code: '123456' };
  const PHONE = '+2250700000010';

  it('the business name and type come first — invalid_input, whatever the number', async () => {
    expect(
      await register({ businessType: 'salon', phoneNumber: 'x', ...IDENTITY }),
    ).toMatchObject({ status: 400, body: { error: 'invalid_input' } });
    expect(
      await register({
        businessName: 'Salon Ordre',
        businessType: 'garage',
        phoneNumber: 'x',
        ...IDENTITY,
      }),
    ).toMatchObject({ status: 400, body: { error: 'invalid_input' } });
  });

  it('then the number: missing or refused is invalid_phone', async () => {
    const base = { businessName: 'Salon Ordre', businessType: 'salon', ...IDENTITY };
    expect(await register(base)).toMatchObject({
      status: 400,
      body: { error: 'invalid_phone' },
    });
    expect(await register({ ...base, phoneNumber: '+2250700000' })).toMatchObject({
      status: 400,
      body: { error: 'invalid_phone' },
    });
  });

  it('then the identity proof: none is invalid_input', async () => {
    expect(
      await register({
        businessName: 'Salon Ordre',
        businessType: 'salon',
        phoneNumber: PHONE,
      }),
    ).toMatchObject({ status: 400, body: { error: 'invalid_input' } });
  });

  it('all of it: 201', async () => {
    const r = await register({
      businessName: 'Salon Ordre',
      businessType: 'salon',
      phoneNumber: PHONE,
      ...IDENTITY,
    });
    expect(r.status).toBe(201);
  });
});
