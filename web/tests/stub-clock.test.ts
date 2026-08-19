import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { materialiseDates, stubDayKey, TODAY, TOMORROW } from './e2e/stub-clock.mjs';
import { salonDayKey, salonDayRange } from '../lib/time';

/// The midnight-rollover regression.
///
/// The e2e stub used to freeze "today" at module load while the app derives it
/// per render, so any CI run that spanned 00:00 UTC failed five date-dependent
/// pro specs — and only those runs. A suite that is green at every hour except
/// one fails a future PR at random and looks like that PR's fault.
///
/// The oracle here is deliberately the APP's own `salonDayKey`, not a restated
/// rule: the property under test is that the stub and the app AGREE, so if the
/// salon zone ever moves off UTC this test notices rather than passing on a
/// definition that drifted.

/// DELIBERATELY IN THE PAST, and the first version of this file got it wrong.
/// It used the real rollover these tests were written on — 2026-08-18 into
/// 2026-08-19 — and a mutation that froze the clock at module load still
/// PASSED, because a frozen clock yields the real today and the real today WAS
/// 2026-08-19. The oracle agreed with the bug by coincidence: a date-dependent
/// test for a date-dependent defect. An instant that can never be "now" again
/// removes the coincidence permanently.
const BOOT = new Date('2019-11-30T23:58:00.000Z'); // stub starts
const RENDER = new Date('2019-12-01T00:01:00.000Z'); // a spec asserts, 3 min later

describe('the stub and the app agree on "today" across midnight', () => {
  it('the OLD shape disagreed — this is the bug, kept executable', () => {
    // What stub-api.mjs did: bake the boot day into the fixture string.
    const frozenAtBoot = `${salonDayKey(BOOT)}T09:00:00.000Z`;

    // What the pro « Aujourd'hui » view asks at render time.
    expect(salonDayKey(new Date(frozenAtBoot))).not.toBe(salonDayKey(RENDER));
    // ...so `todaysAppointments` filtered the row out and 'Tresses' was absent.
  });

  it('the token is materialised at RESPONSE time, so they agree', () => {
    const payload = JSON.stringify({ appointmentDate: `${TODAY}T09:00:00.000Z` });
    const served = JSON.parse(materialiseDates(payload, RENDER));

    expect(salonDayKey(new Date(served.appointmentDate))).toBe(
      salonDayKey(RENDER),
    );
  });

  it('and it still agrees when nothing rolls over', () => {
    const noon = new Date('2026-08-19T12:00:00.000Z');
    const served = JSON.parse(
      materialiseDates(JSON.stringify({ d: `${TODAY}T09:00:00.000Z` }), noon),
    );
    expect(salonDayKey(new Date(served.d))).toBe(salonDayKey(noon));
  });

  it('TOMORROW stays in the future on both sides of midnight', () => {
    // Consumer fixtures sit here so « Reporter » remains reachable; a frozen
    // "tomorrow" becomes "today" the moment the day rolls, and the future-only
    // actions vanish.
    for (const now of [BOOT, RENDER]) {
      const served = JSON.parse(
        materialiseDates(JSON.stringify({ d: `${TOMORROW}T09:00:00.000Z` }), now),
      );
      expect(new Date(served.d).getTime()).toBeGreaterThan(now.getTime());
      expect(salonDayKey(new Date(served.d))).not.toBe(salonDayKey(now));
    }
  });

  it('a tokenised fixture survives being COMPARED, not only written', () => {
    // The case no unit test had, and the one the real suite caught: the
    // /earnings handler filters its ledger with `t.date >= start` against the
    // ISO range the app's salonDayRange() sends. An unresolved token there is a
    // string comparison with no meaning, and « Aujourd'hui » silently totalled
    // nothing. Resolution has to happen before the comparison, not only on the
    // way out.
    const range = salonDayRange('today', RENDER)!;
    const ledger = [
      { id: 't1', date: `${TODAY}T09:00:00.000Z`, amount: 15000 },
      { id: 't3', date: `${TODAY}T23:30:00.000Z`, amount: 2000 },
      { id: 't2', date: '2019-01-04T09:00:00.000Z', amount: 20000 },
    ];
    const inRange = ledger.filter((t) => {
      const d = materialiseDates(t.date, RENDER);
      return d >= range.startDate && d < range.endDate;
    });
    expect(inRange.map((t) => t.id)).toEqual(['t1', 't3']);
    expect(inRange.reduce((n, t) => n + t.amount, 0)).toBe(17000);

    // Unresolved, the same filter finds nothing — which is what the pro
    // « Revenus » tab showed.
    const naive = ledger.filter(
      (t) => t.date >= range.startDate && t.date < range.endDate,
    );
    expect(naive.map((t) => t.id)).not.toContain('t1');
  });

  it('substitutes every occurrence, not just the first', () => {
    const payload = JSON.stringify({
      a: `${TODAY}T09:00:00.000Z`,
      b: `${TODAY}T23:30:00.000Z`,
      c: `${TOMORROW}T09:00:00.000Z`,
    });
    expect(materialiseDates(payload, RENDER)).not.toContain('@');
  });

  it('stubDayKey matches the app for an ordinary instant', () => {
    expect(stubDayKey(RENDER)).toBe(salonDayKey(RENDER));
  });

  it('THE ANSWER DEPENDS ON WHEN IT IS ASKED — the whole property', () => {
    // The one assertion a frozen clock cannot survive, whatever today happens
    // to be. Everything else above compares against a fixture date and could,
    // on the wrong day, agree with a bug by coincidence; this cannot.
    const payload = JSON.stringify({ d: `${TODAY}T09:00:00.000Z` });
    expect(materialiseDates(payload, BOOT)).not.toBe(
      materialiseDates(payload, RENDER),
    );
  });
});

/// The one suite here that talks to the REAL stub.
///
/// The first version of the ledger test above simulated the handler inline: it
/// documented the property and guarded nothing, and a mutation that put the
/// unresolved token back into the comparison still passed. Exercising the
/// running server is what makes it a check rather than a comment.
describe('the running stub resolves tokens before comparing', () => {
  const PORT = 8799;
  let child: ReturnType<typeof spawn>;

  beforeAll(async () => {
    child = spawn('node', ['tests/e2e/stub-api.mjs'], {
      env: { ...process.env, STUB_PORT: String(PORT), TZ: 'UTC' },
      stdio: 'ignore',
    });
    const deadline = Date.now() + 10_000;
    for (;;) {
      try {
        await fetch(`http://127.0.0.1:${PORT}/localities`);
        return;
      } catch {
        if (Date.now() > deadline) throw new Error('stub did not start');
        await new Promise((r) => setTimeout(r, 100));
      }
    }
  });

  afterAll(() => child?.kill());

  it('« Aujourd’hui » earnings return the two same-day rows, 17 000', async () => {
    // Both sides use the real clock, so this is date-independent — and it is
    // the exact query the pro « Revenus » tab issues.
    const range = salonDayRange('today', new Date())!;
    const res = await fetch(
      `http://127.0.0.1:${PORT}/providers/p1/earnings` +
        `?startDate=${encodeURIComponent(range.startDate)}` +
        `&endDate=${encodeURIComponent(range.endDate)}`,
    );
    const body = await res.json();
    expect(body.totalEarnings).toBe(17000);
    expect(body.transactions.map((t: { id: string }) => t.id)).toEqual([
      't1',
      't3',
    ]);
    // …including the 23:30 row, the salon-day boundary probe.
  });

  it('and no token ever reaches the wire', async () => {
    const res = await fetch(`http://127.0.0.1:${PORT}/providers/p1/earnings`);
    expect(await res.text()).not.toContain('@');
  });
});

describe('the harness cannot go back to freezing', () => {
  it('stub-api.mjs derives no day key of its own', () => {
    // tests/time-pin.test.ts forbids this pattern across app/components/lib —
    // the stub sat outside that firewall's scope, which is exactly why the bug
    // could live here. Same rule, extended to the one file that needed it.
    const stub = readFileSync('tests/e2e/stub-api.mjs', 'utf8');
    expect(stub).not.toMatch(/toISOString\(\)\.slice\(0,\s*10\)/);
    expect(stub).toContain("from './stub-clock.mjs'");
  });

  it('json() materialises — no response bypasses the seam', () => {
    const stub = readFileSync('tests/e2e/stub-api.mjs', 'utf8');
    expect(stub).toMatch(/function json\([\s\S]{0,400}materialiseDates\(/);
  });
});
