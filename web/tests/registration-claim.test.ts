import { execFileSync } from 'node:child_process';
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';

/// L1 — the guard on « société en cours d'immatriculation ».
///
/// **What this replaces.** `legal.test.tsx` used to assert
/// `COMPANY.registration` still MATCHED `/en cours d'immatriculation/i`. That
/// guard was aimed at the wrong end of the fact: it went red the day someone
/// CORRECTED the claim and stayed green forever while it went stale.
///
/// **And the first version of THIS file made the same mistake, twice.** It
/// asserted the checklist against the real tree with the flag flipped, and it
/// asserted the stripper worked by looking for `numéro RCCM` — a string that
/// exists only while registration is pending. Both would have gone red on
/// registration day: the one day the suite exists to help. An adversarial audit
/// found them; SKILL.md §15 is the rule they earned.
///
/// So the truth table is exercised on FIXTURES, which do not care what world we
/// are in, and only ONE assertion touches the real tree — the one that reads
/// `registered` and is therefore correct in both worlds.

const WEB = process.cwd();
const REPO = join(WEB, '..');

type Surface = {
  file: string;
  anchor: string;
  what: string;
  atRegistration: string;
};

type Manifest = {
  $comment?: string[];
  registered: boolean;
  attestedOn: string;
  attestationMaxAgeDays: number;
  surfaces: Surface[];
  scan: {
    roots: string[];
    pattern: string;
    allowedFiles: string[];
    allowedAnchors: string[];
  };
};

const MANIFEST_PATH = join(REPO, 'infra/legal/registration-manifest.json');
const manifest: Manifest = JSON.parse(readFileSync(MANIFEST_PATH, 'utf8'));

const readRepoFile = (file: string) => readFileSync(join(REPO, file), 'utf8');

/// Four guards in this repo have matched a string that existed only in a
/// comment — one of them the comment explaining that footgun. Blanking rather
/// than deleting keeps line numbers honest for the failure message.
export function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/(^|[^:])\/\/.*$/gm, (_m, before: string) => before);
}

/// THE PURE CORE. Both directions in one function so neither can be the branch
/// nobody exercises: while unregistered, a MISSING anchor is the defect; once
/// registered, a SURVIVING anchor is. **Both messages carry `atRegistration`**
/// — the first version put it only on the registered branch, so on registration
/// day the checklist assertion failed on a message that was otherwise correct.
export function pendingViolations(
  registered: boolean,
  surfaces: Surface[],
  read: (file: string) => string,
): string[] {
  return surfaces.flatMap((s) => {
    const present = stripComments(read(s.file)).includes(s.anchor);
    if (registered && present) {
      return [`${s.file}: still says « ${s.anchor} » — ${s.atRegistration}`];
    }
    if (!registered && !present) {
      return [
        `${s.file}: « ${s.anchor} » is gone (${s.what}) but the manifest still ` +
          `says registered=false — ${s.atRegistration}`,
      ];
    }
    return [];
  });
}

// Fixture readers. `read` receives a FILE, and several surfaces share a file,
// so "pending" must return every anchor recorded against that file — returning
// only the first would fake a violation for its siblings.
const anchorsIn = (file: string) =>
  manifest.surfaces.filter((s) => s.file === file).map((s) => s.anchor);
const stillPending = (file: string) => anchorsIn(file).join('\n');
const alreadyRewritten = () => 'a document with nothing pending left in it';
/// The anchors are present as TEXT but only inside comments, so this must read
/// as REWRITTEN. Delete the `stripComments` call from `pendingViolations` and
/// THIS is the fixture that goes red — measured: without it the whole suite
/// stayed green with the stripping removed, leaving this repo's most-repeated
/// footgun unguarded inside the one function built around it.
const onlyInComments = (file: string) =>
  anchorsIn(file)
    .map((anchor) => `/// a docstring that happens to quote ${anchor}`)
    .join('\n');

describe('pendingViolations — all four cells, in fixtures, in every world', () => {
  // The real tree is in exactly ONE of these states at a time, so asserting
  // against it can only ever exercise half the function. These four cannot go
  // stale, cannot go red on a repair, and cover the transition itself.

  it('not registered + still pending → silence, correctly', () => {
    expect(pendingViolations(false, manifest.surfaces, stillPending)).toEqual([]);
  });

  it('registered + already rewritten → silence, correctly', () => {
    expect(pendingViolations(true, manifest.surfaces, alreadyRewritten)).toEqual(
      [],
    );
  });

  it('registered + still pending → the checklist, with an instruction each', () => {
    const checklist = pendingViolations(true, manifest.surfaces, stillPending);
    expect(checklist).toHaveLength(manifest.surfaces.length);
    for (const s of manifest.surfaces) {
      // `toContain('')` is true of every string, so the instruction has to be
      // shown to exist before it is looked for. Found by mutation: blanking an
      // `atRegistration` left this test green.
      expect(
        s.atRegistration.length,
        `${s.file} « ${s.anchor} » records no instruction`,
      ).toBeGreaterThan(10);
      expect(checklist.join('\n')).toContain(s.file);
      expect(checklist.join('\n')).toContain(s.atRegistration);
    }
  });

  it('an anchor surviving only in a comment is not a surface', () => {
    // THE STRIPPER, exercised where it actually runs. The dedicated
    // `stripComments` test proves the function; this proves `pendingViolations`
    // still calls it.
    expect(
      pendingViolations(true, manifest.surfaces, onlyInComments),
      'a commented-out anchor must not count as the claim still being made',
    ).toEqual([]);
    expect(
      pendingViolations(false, manifest.surfaces, onlyInComments),
    ).toHaveLength(manifest.surfaces.length);
  });

  it('not registered + already rewritten → also flagged, also actionable', () => {
    // The half-corrected state: someone edited the pages and not the manifest.
    // This message ALSO carries `atRegistration`, because the first version did
    // not and that is what turned the suite red on registration day.
    const flagged = pendingViolations(false, manifest.surfaces, alreadyRewritten);
    expect(flagged).toHaveLength(manifest.surfaces.length);
    for (const s of manifest.surfaces) {
      expect(flagged.join('\n')).toContain(s.atRegistration);
    }
  });
});

describe('the real tree agrees with the manifest', () => {
  it('every surface is in the state the manifest records', () => {
    // THE ONLY REAL-TREE ASSERTION, and it reads `registered` rather than
    // pinning it — so it is correct in both worlds. While false, a surface that
    // stopped saying « en cours » is the defect; once true, a surface that
    // still says it is.
    expect(
      pendingViolations(manifest.registered, manifest.surfaces, readRepoFile),
      'infra/legal/registration-manifest.json and the pages disagree',
    ).toEqual([]);
  });

  it('carries an attestation the cron can read, with a pinned limit', () => {
    // `attestedOn` is consumed only by the daily monitor; a typo there would be
    // invisible until 06:00 and would look like the monitor's fault.
    expect(manifest.attestedOn).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(Number.isNaN(Date.parse(manifest.attestedOn))).toBe(false);
    // **Pinned exactly, not merely positive.** The limit is operator-controlled
    // and read only by the cron, so `> 0` let anyone silence the entire design
    // with a one-line PR: set it to 36500 and the monitor congratulates you for
    // a century. It is a policy constant — changing it should mean changing
    // this line, on purpose, in a review.
    expect(manifest.attestationMaxAgeDays).toBe(90);
  });

  it('nothing writes a surface count in prose — the array is the count', () => {
    // Two rounds of this fix shipped a wrong count. The first said FIVE in the
    // manifest header while the array held SEVEN, and SIX in three source
    // files. The second left SEVEN inside the monitor script itself and FIVE
    // beside `pendingFacts`. A number written next to a list is a second source
    // of truth, and it only ever goes stale.
    //
    // The first version of THIS guard read `JSON.stringify(manifest.$comment)`
    // and matched /five|six|…\s+surfaces/. Measured blind spots: French
    // (« sept surfaces »), digits (« 7 surfaces »), counts outside the five-to-
    // nine window, and — the likeliest form, since `$comment` is hard-wrapped —
    // a count split across two array entries, where `","` sits between the
    // number and the noun and `\s+` cannot match.
    const strings = (v: unknown): string[] =>
      typeof v === 'string'
        ? [v]
        : Array.isArray(v)
          ? v.flatMap(strings)
          : v && typeof v === 'object'
            ? Object.values(v).flatMap(strings)
            : [];

    // Ordinals, a hyphen, and ONE intervening adjective — « seven recorded
    // surfaces », « the seventh surface », « a seven-surface list » all escaped
    // the first version. `of|de|des` is excluded so « four of those surfaces »
    // (a reference, not a count) does not fire.
    const N =
      '\\d+|one|two|three|four|five|six|seven|eight|nine|ten' +
      '|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth' +
      '|un|une|deux|trois|quatre|cinq|sept|huit|neuf|dix';
    const COUNT = new RegExp(
      `\\b(${N})[-\\s]+(?:(?!of\\b|de\\b|des\\b)[A-Za-zÀ-ÿ]+[-\\s]+)?(surfaces?|facts?|faits?)\\b`,
      'i',
    );

    // Joined with a single space: line wrapping must not hide a count. Both the
    // manifest and the monitor are checked, because the second round's worst
    // survivor was in the monitor, which a manifest-scoped guard cannot see.
    // **Every file that has ever carried a stale count**, not the two where the
    // last round happened to find one. Round two fixed four more by hand in the
    // same commit that added a guard which could not see them.
    //
    // NOT read, and each for a reason: docs/LAUNCH.md and docs/ROADMAP.md, where
    // "surfaces" means app/web/pro and a count is legitimate; and this file,
    // whose comment above quotes « sept surfaces » and « 7 surfaces » as
    // examples, so it would match itself.
    const flat = (f: string) => readRepoFile(f).split('\n').join(' ');
    for (const [what, text] of [
      ['infra/legal/registration-manifest.json', strings(manifest).join(' ')],
      [
        'infra/legal/98-verify-registration-attestation.mjs',
        flat('infra/legal/98-verify-registration-attestation.mjs'),
      ],
      ['.github/workflows/production-checks.yml', flat('.github/workflows/production-checks.yml')],
      ['docs/design/legal-l1.md', flat('docs/design/legal-l1.md')],
      ['web/tests/legal.test.tsx', flat('web/tests/legal.test.tsx')],
    ] as const) {
      expect(text, `${what} writes a count beside a list`).not.toMatch(COUNT);
    }
  });
});

describe('stripComments', () => {
  it('removes comments, spares URLs, and keeps the line count', () => {
    // Deliberately synthetic. The first version asserted `numéro RCCM` survived
    // stripping a REAL file — a string that exists only while registration is
    // pending, so this test would have gone red on the repair.
    const src = [
      '/// doc comment KEEP_OUT_A',
      "const kept = 'KEEP_IN_A';",
      '/* block',
      '   spanning KEEP_OUT_B */',
      "const url = 'https://example.com/a'; // KEEP_OUT_C",
      "const after = 'KEEP_IN_B';",
    ].join('\n');
    const out = stripComments(src);

    expect(out).not.toContain('KEEP_OUT_A');
    expect(out).not.toContain('KEEP_OUT_B');
    expect(out).not.toContain('KEEP_OUT_C');
    expect(out).toContain('KEEP_IN_A');
    expect(out).toContain('KEEP_IN_B');
    // A `//` inside a URL is not a comment. Getting this wrong would blank
    // half the lines in any file that links to anything.
    expect(out).toContain('https://example.com/a');
    // Line numbers have to survive or the failure messages point nowhere.
    expect(out.split('\n')).toHaveLength(src.split('\n').length);
  });

  // **A second control used to live here**, pinning « owner decision,
  // docs/design/legal-l1.md » from `lib/legal.ts` as proof the stripper runs on
  // real files. That phrase sits inside a paragraph stating the company is not
  // registered, so the registration-day rewrite would have turned it red — the
  // same defend-the-stale-world trap, one notch quieter. « an anchor surviving
  // only in a comment is not a surface » covers the same property with a
  // fixture that holds no opinion about the world.
});

describe('the surface list cannot go stale behind our backs', () => {
  const walk = (dir: string, out: string[] = []): string[] => {
    // A renamed or deleted root threw ENOENT out of module scope, taking every
    // test in this file with it — so the control's own « renamed, or a typo? »
    // message could never print for the case it names.
    if (!existsSync(dir)) return out;
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) walk(p, out);
      else if (/\.(ts|tsx)$/.test(name)) out.push(p);
    }
    return out;
  };

  const pattern = new RegExp(manifest.scan.pattern, 'i');

  /// **Anchors are scoped to the file that recorded them.** They used to be a
  /// global pool, which meant a NEW page repeating an already-recorded sentence
  /// was silently accepted as "recorded" — so the scan only ever caught new
  /// WORDING, not new PLACES, while the manifest claimed it caught both.
  /// `allowedAnchors` stays global on purpose: « pièces d'identité et
  /// d'immatriculation » means salon paperwork wherever it appears.
  const anchorsFor = (file: string) => [
    ...manifest.surfaces.filter((s) => s.file === file).map((s) => s.anchor),
    ...manifest.scan.allowedAnchors,
  ];

  const hits = manifest.scan.roots
    .flatMap((root) => walk(join(REPO, root)))
    .map((abs) => ({ rel: relative(REPO, abs), abs }))
    .filter((f) => !manifest.scan.allowedFiles.includes(f.rel))
    .flatMap((f) => {
      const lines = stripComments(readFileSync(f.abs, 'utf8')).split('\n');
      return lines
        .map((line, i) => ({
          file: f.rel,
          line: i + 1,
          text: line,
          // **Anchors are matched on a WINDOW, not a line.** Prettier wraps at
          // 80 columns, so the published « immatriculée au RCCM n° … » will
          // land across two lines and a per-line exemption would only ever see
          // half of it — flagging a correctly rewritten page on registration
          // day, for the fourth time in this file's history.
          window: [lines[i - 1] ?? '', line, lines[i + 1] ?? ''].join(' '),
        }))
        .filter((l) => pattern.test(l.text));
    });

  it('the scan configuration itself is pinned, like the 90 beside it', () => {
    // **v3 of the control below removed the only detection of scan tampering.**
    // Measured: `roots: []`, a blanked `pattern`, and adding the surface files
    // to `allowedFiles` each leave the whole suite green — the surface list is
    // back to hand-maintained and nothing says so. v1 and v2 caught two of
    // those; v3 dropped the hit assertion to stop going red on registration day
    // and took the tamper detection with it.
    //
    // roots / pattern / allowedFiles do not change at registration: the
    // published wording « immatriculée au RCCM n° … » still matches this
    // pattern, and the manifest sends the new sentences to `allowedAnchors` —
    // which is deliberately NOT pinned, because it is the one field that must
    // grow that day.
    expect(manifest.scan.roots).toEqual(['web/app', 'web/lib', 'web/components']);
    expect(manifest.scan.pattern).toBe('immatricul|RCCM');
    expect(manifest.scan.allowedFiles).toEqual(['web/lib/pro/kyc.ts']);
  });

  it('every declared root is a real directory that yielded real files', () => {
    // THE CONTROL, and it took three attempts.
    //
    // v1 asserted a TOTAL hit count — its only slack was the unrelated matches,
    // so an ordinary copy edit fired it. v2 asserted a hit in every file
    // holding a surface, which goes RED ON REGISTRATION DAY: those sentences
    // are correctly removed that day, and the message blames the scan for a
    // repair. Both were the defend-the-current-world trap, twice more.
    //
    // What a control here must rule out is a root that reaches NOTHING — a
    // rename, a typo, a deletion. That is a property of the roots rather than
    // of the claim, so registration day does not touch it. It also covers
    // `web/components`, which no surface-keyed version ever reached: no surface
    // lives there, so that root could have been dropped in silence.
    for (const root of manifest.scan.roots) {
      const files = walk(join(REPO, root)).filter(
        (abs) => !manifest.scan.allowedFiles.includes(relative(REPO, abs)),
      );
      expect(
        files.length,
        `scan root "${root}" reached no .ts/.tsx file — renamed, or a typo?`,
      ).toBeGreaterThan(0);
    }
  });

  it('every registration sentence in the tree is a recorded surface', () => {
    // Widening a list fixes the instance, not the blindness — so the list is
    // re-derived here instead of trusted. A new « dès notre immatriculation »
    // fails until someone records what it must become, and so does the same
    // sentence copied onto a page that never had it.
    const unrecorded = hits.filter((h) => {
      const rest = anchorsFor(h.file).reduce(
        (t, a) => t.split(a).join(' '),
        // Whitespace-normalised so an anchor broken by a line wrap still
        // matches the recorded text.
        h.window.replace(/\s+/g, ' '),
      );
      return pattern.test(rest);
    });
    expect(
      unrecorded.map((h) => `${h.file}:${h.line} ${h.text.trim()}`),
      'unrecorded registration wording. Add each to ' +
        'infra/legal/registration-manifest.json: as a `surface` if it is a NEW ' +
        'pending claim; to `scan.allowedAnchors` if it is unrelated (salon ' +
        'paperwork) OR if it is the post-registration wording — that text is ' +
        'the thing being published, so it can never be a surface, whose anchor ' +
        'must be ABSENT once registered.',
    ).toEqual([]);
  });
});

describe('the attestation monitor, exercised rather than described', () => {
  /// **This suite exists because the monitor was executed by nothing.** Its
  /// consistency half had seven tests; its staleness half — the part the whole
  /// design is for — was guarded by a grep for `writeFileSync`, and its eight
  /// "watched red" mutations were a manual claim nobody could repeat. A future
  /// edit to the script could only be caught by the 06:00 cron.
  const SCRIPT = join(REPO, 'infra/legal/98-verify-registration-attestation.mjs');
  const dir = mkdtempSync(join(tmpdir(), 'myweli-attestation-'));
  const iso = (daysAgo: number) =>
    new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10);

  /// Returns the exit code and the combined output, never throwing — the
  /// non-zero exits ARE the subject here.
  const run = (m: unknown): { code: number; out: string } => {
    const path = join(dir, `m-${Math.abs(JSON.stringify(m).length)}-${Math.random()}.json`);
    writeFileSync(path, JSON.stringify(m));
    try {
      const out = execFileSync('node', [SCRIPT], {
        env: { ...process.env, REGISTRATION_MANIFEST: path },
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      return { code: 0, out };
    } catch (e) {
      const err = e as { status?: number; stdout?: string; stderr?: string };
      return { code: err.status ?? -1, out: `${err.stdout ?? ''}${err.stderr ?? ''}` };
    }
  };

  const base = { registered: false, attestationMaxAgeDays: 90 };

  it('passes on a fresh attestation, and on the exact boundary', () => {
    expect(run({ ...base, attestedOn: iso(0) }).code).toBe(0);
    expect(run({ ...base, attestedOn: iso(90) }).code).toBe(0);
  });

  it('fails one day past the boundary, and says how stale', () => {
    const r = run({ ...base, attestedOn: iso(91) });
    expect(r.code).toBe(1);
    expect(r.out).toContain('91 days');
  });

  // **Each case asserts its OWN message, not just a non-zero exit.** Two of
  // these passed for the wrong reason at first: `2026-02-30` is also 173 days
  // old, so it failed on STALENESS whether or not the impossible-date check
  // existed, and deleting that check left the suite green. An oracle that
  // cannot tell "rejected" from "accepted but old" measured nothing.
  it.each([
    ['a malformed date', { ...base, attestedOn: 'not-a-date' }, 'must be YYYY-MM-DD'],
    ['an impossible month', { ...base, attestedOn: '2026-13-45' }, 'not a real date'],
    // **Rolls FORWARD, the one direction a staleness monitor must never fail
    // in.** `new Date('2026-02-30T00:00:00Z')` is 2 March — valid, and fresher
    // than the operator typed. Measured, not assumed: 2026-02-29 → 03-01,
    // 2026-04-31 → 05-01. Only the round trip tells a real date from a repaired
    // one.
    ['a day that does not exist', { ...base, attestedOn: '2026-02-30' }, 'not a real calendar date'],
    ['a future date', { ...base, attestedOn: iso(-5) }, 'in the future'],
    ['a non-string date', { ...base, attestedOn: 20260822 }, 'must be YYYY-MM-DD'],
    ['a missing date', { registered: false, attestationMaxAgeDays: 90 }, 'must be YYYY-MM-DD'],
    ['a zero limit', { ...base, attestedOn: iso(0), attestationMaxAgeDays: 0 }, 'positive number'],
    ['a non-numeric limit', { ...base, attestedOn: iso(0), attestationMaxAgeDays: 'ninety' }, 'positive number'],
    ['an array', [1, 2, 3], 'not a JSON object'],
    ['a bare string', 'nope', 'not a JSON object'],
    // Without the shape guard this one THROWS on destructuring — exit 1 with a
    // stack trace and no annotation, which the tracking issue renders as a bare
    // "failure". It is the only case that distinguishes the guard from nothing.
    ['null', null, 'not a JSON object'],
  ])('fails closed on %s, saying which', (_label, m, expected) => {
    const r = run(m);
    expect(r.code).toBe(1);
    expect(r.out).toContain(expected as string);
    // Not merely non-zero: an unhandled throw also exits 1, but prints a stack
    // trace and no annotation, so the tracking issue would say only "failure".
    expect(r.out).toContain('::error::');
    expect(r.out).not.toMatch(/^\s+at /m);
  });

  it('refuses a manifest it cannot read at all, and says so', () => {
    // The table above asserts a message per row; this case did not, so the one
    // property the design most depends on — failing LOUDLY rather than quietly
    // — was pinned by an exit code that any crash also produces.
    let code = 0;
    let out = '';
    try {
      execFileSync('node', [SCRIPT], {
        env: { ...process.env, REGISTRATION_MANIFEST: join(dir, 'absent.json') },
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (e) {
      const err = e as { status?: number; stdout?: string; stderr?: string };
      code = err.status ?? -1;
      out = `${err.stdout ?? ''}${err.stderr ?? ''}`;
    }
    expect(code).toBe(1);
    expect(out).toContain('cannot read');
    expect(out).toContain('::error::');
  });

  it('stays read-only, and is not merely empty', () => {
    // infra/gcp/97-verify-log-retention.sh is pinned the same way by
    // backend/test/infra/log_retention_test.dart. The `readFileSync`
    // assertion is the control — without it this passes on a file that does
    // nothing at all.
    const src = readFileSync(SCRIPT, 'utf8');
    expect(src).toContain('readFileSync');
    expect(src).not.toMatch(/writeFileSync|appendFile|unlinkSync|execSync|spawn/);
  });
});
