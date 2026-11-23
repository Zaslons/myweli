import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  type Appointment,
  clientStatusLabel,
  clientStatusTone,
  clientTab,
} from '../lib/account/appointments';

/// docs/design/web-account-bookings-truth.md §2.8 — one table, pinned on both
/// surfaces. The app's `client_booking_rule_test.dart` reads the SAME file, so
/// « the same on both surfaces » is a test rather than a sentence: a rule
/// changed on one side turns that side red; a row changed in the file turns
/// both red until both follow.

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const WEB = join(REPO_ROOT, 'web');

type Row = {
  status: string;
  minutesFromNow: number;
  tab: string;
  label: string;
  tone: string;
};

const table: { rows: Row[] } = JSON.parse(
  readFileSync(join(REPO_ROOT, 'docs/design/fixtures/client-booking-rule.json'), 'utf8'),
);

const NOW = new Date('2026-11-23T12:00:00.000Z');

describe('the shared client booking table', () => {
  it('has the seven rows of §2.1 plus the edges — an emptied file cannot pass', () => {
    expect(table.rows.length).toBeGreaterThanOrEqual(13);
    // Every status of the table, both sides of now, and the boundary.
    const seen = new Set(table.rows.map((r) => r.status));
    expect([...seen].sort()).toEqual(['cancelled', 'completed', 'confirmed', 'noShow', 'pending']);
    expect(table.rows.some((r) => r.minutesFromNow === 0)).toBe(true);
  });

  for (const r of table.rows) {
    it(`${r.status} at ${r.minutesFromNow} min → ${r.tab}, « ${r.label} », ${r.tone}`, () => {
      const a: Appointment = {
        id: 'a',
        status: r.status,
        appointmentDate: new Date(NOW.getTime() + r.minutesFromNow * 60_000).toISOString(),
        providerId: 'p1',
      };
      expect(clientTab(a, NOW)).toBe(r.tab);
      expect(clientStatusLabel(a, NOW)).toBe(r.label);
      expect(clientStatusTone(a, NOW)).toBe(r.tone);
    });
  }
});

/// Blank comments (keeping line numbers) so a name in a comment cannot trip,
/// or rescue, the pin below.
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/(^|[^:])\/\/.*$/gm, (_m, before: string) => before);
}

function sources(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...sources(p));
    else if (/\.(ts|tsx)$/.test(name)) out.push(p);
  }
  return out;
}

describe('the Espace pro keeps the stored status (§1)', () => {
  // For a salon, a past booking nobody confirmed is work still to do: it
  // stays « En attente » there. The client rule must never reach a pro list.
  const CLIENT_ONLY =
    /\b(clientTab|clientStatusLabel|clientStatusTone|bookingsForTab|ClientStatusChip)\b/;
  const PRO_DIRS = ['components/pro', 'lib/pro', 'app/pro'];

  it('reads real directories with real files', () => {
    for (const d of PRO_DIRS) {
      expect(sources(join(WEB, d)).length, d).toBeGreaterThan(0);
    }
  });

  it('no file under components/pro, lib/pro or app/pro names a client-only helper', () => {
    const hits = PRO_DIRS.flatMap((d) => sources(join(WEB, d))).filter((f) =>
      CLIENT_ONLY.test(stripComments(readFileSync(f, 'utf8'))),
    );
    expect(hits.map((f) => relative(WEB, f))).toEqual([]);
  });
});
