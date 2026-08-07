import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';

/// The salon-time regression firewall (docs/design/timezone-salon-time.md
/// §8): time facts live ONLY in lib/time.ts. A hit here means new code
/// bypassed the seam — route it through salonDayKey/salonFormatter instead.

const ROOT = process.cwd();
const DIRS = ['app', 'components', 'lib'];

function walk(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx)$/.test(name)) out.push(p);
  }
  return out;
}

const files = DIRS.flatMap((d) => walk(join(ROOT, d))).map((p) => ({
  rel: relative(ROOT, p),
  content: readFileSync(p, 'utf8'),
}));

const RULES: { name: string; pattern: RegExp; allow: string[]; hint: string }[] =
  [
    {
      name: 'day keys go through the seam',
      pattern: /toISOString\(\)\.slice\(0,\s*10\)/,
      allow: ['lib/time.ts'],
      hint: 'use salonDayKey()/salonToday() from lib/time.ts',
    },
    {
      name: 'formatters go through the seam',
      pattern: /new Intl\.DateTimeFormat/,
      allow: ['lib/time.ts'],
      hint: 'use salonFormatter() from lib/time.ts',
    },
    {
      name: 'no hardcoded UTC display zone',
      pattern: /timeZone:\s*'UTC'/,
      allow: ['lib/time.ts'],
      hint: 'the salon zone is SALON_TZ (lib/time.ts), not a UTC literal',
    },
    {
      // Multi-pays MP3: per-salon timezones come from the API; the Wave-0
      // fallback lives ONLY in SALON_TZ.
      name: "no 'Africa/Abidjan' literal outside the seam",
      pattern: /'Africa\/Abidjan'/,
      allow: ['lib/time.ts'],
      hint: 'use SALON_TZ — or better, thread the salon tz (lib/time.ts)',
    },
    {
      // Multi-pays MP3: wall-clock → instant goes through
      // salonWallClockToUtc; a `T${…}:00.000Z` template is the old
      // hardcoded-UTC construction (midday ANCHORS `T12:00:00.000Z` are
      // fine — day identifiers, no interpolated time).
      name: 'no hand-built wall-clock instants',
      pattern: /T\$\{[^}]*\}:00\.000Z/,
      // `lib/pro/availability.ts` is an exception of a different kind, and it
      // is declared rather than dodged (concatenating the string to slip past
      // this regex would be the silent drift the pin exists to stop).
      // `TimeSlot.startTime` is a **carrier**, not an instant: `openapi.yaml`
      // types it `format: date-time` and says only the time-of-day is
      // significant, and the server normalises every value to the placeholder
      // date 2024-01-01. Sending it through `salonWallClockToUtc` would shift a
      // salon's opening hour by its own UTC offset — i.e. the conversion this
      // rule mandates is the bug, here. `wireTime` therefore builds the carrier
      // literally, and `timeOfDay` reads it back with a regex for the same
      // reason (a `Date` would re-introduce the browser's timezone).
      allow: ['lib/time.ts', 'lib/pro/availability.ts'],
      hint: 'build instants with salonWallClockToUtc()/isoAt()/combineDateTime()',
    },
  ];

describe('salon-time grep pins', () => {
  for (const rule of RULES) {
    it(rule.name, () => {
      const offenders = files
        .filter((f) => !rule.allow.includes(f.rel))
        .filter((f) => rule.pattern.test(f.content))
        .map((f) => f.rel);
      expect(offenders, `${offenders.join(', ')} — ${rule.hint}`).toEqual([]);
    });
  }
});
