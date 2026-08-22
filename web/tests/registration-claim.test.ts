import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
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
const stillPending = (file: string) =>
  manifest.surfaces
    .filter((s) => s.file === file)
    .map((s) => s.anchor)
    .join('\n');
const alreadyRewritten = () => 'a document with nothing pending left in it';

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

  it('the manifest states no surface count of its own', () => {
    // The first version of this branch fixed « three files repeat a false
    // count » by leaving four files repeating a different false count — the
    // manifest header said FIVE while its array held SEVEN. A number written
    // beside a list is a second source of truth that only ever goes stale.
    const prose = JSON.stringify(manifest.$comment ?? '');
    expect(
      prose,
      'do not write a surface count in prose — the array is the count',
    ).not.toMatch(/\b(five|six|seven|eight|nine)\s+surfaces\b/i);
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

  it('is actually applied to the files the scan reads', () => {
    // The control for the above: prove the real pipeline strips, on a phrase
    // that lives in a comment and is not a claim about the world.
    const raw = readRepoFile('web/lib/legal.ts');
    const inACommentOnly = 'owner decision, docs/design/legal-l1.md';
    expect(raw).toContain(inACommentOnly);
    expect(stripComments(raw)).not.toContain(inACommentOnly);
  });
});

describe('the surface list cannot go stale behind our backs', () => {
  const walk = (dir: string, out: string[] = []): string[] => {
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
    .flatMap((f) =>
      stripComments(readFileSync(f.abs, 'utf8'))
        .split('\n')
        .map((line, i) => ({ file: f.rel, line: i + 1, text: line }))
        .filter((l) => pattern.test(l.text)),
    );

  it('finds the sentences it is supposed to be looking at', () => {
    // THE CONTROL. A scan pointed at a path that does not exist returns zero
    // lines and passes the next test for the wrong reason.
    //
    // It asserts PRESENCE PER FILE rather than a total, because a total has
    // only as much slack as there are unrelated matches — two ordinary copy
    // edits elsewhere would have fired it and sent the reader hunting for a
    // broken scan root.
    const scanned = manifest.surfaces
      .map((s) => s.file)
      .filter((f) => manifest.scan.roots.some((r) => f.startsWith(r)));
    expect(scanned.length).toBeGreaterThan(0);
    for (const file of new Set(scanned)) {
      expect(
        hits.map((h) => h.file),
        `the scan reached no line of ${file}`,
      ).toContain(file);
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
        h.text,
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

  it('refuses a manifest it cannot read at all', () => {
    let code = 0;
    try {
      execFileSync('node', [SCRIPT], {
        env: { ...process.env, REGISTRATION_MANIFEST: join(dir, 'absent.json') },
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (e) {
      code = (e as { status?: number }).status ?? -1;
    }
    expect(code).toBe(1);
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
