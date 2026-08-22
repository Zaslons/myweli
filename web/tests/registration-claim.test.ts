import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';

/// L1 — the guard on « société en cours d'immatriculation ».
///
/// **What this replaces.** `legal.test.tsx` used to assert
/// `COMPANY.registration` still MATCHED `/en cours d'immatriculation/i`. That
/// guard was aimed at the wrong end of the fact: it went red the day someone
/// CORRECTED the claim and stayed green forever while it went stale. It was the
/// only automated thing touching a published legal claim, and it defended the
/// claim's staleness.
///
/// **What it does instead.** The fact lives once, in
/// `infra/legal/registration-manifest.json`, and this file asserts three things
/// — none of which depend on what day it is:
///
///   1. while `registered` is false, every pending surface is still saying so
///      (so correcting one paragraph and forgetting the other three fails);
///   2. flipping `registered` to true produces a CHECKLIST naming every surface
///      that still carries pending prose — proven here, today, against the real
///      files, rather than on the day it matters;
///   3. the surface list is re-derived from the tree, so a SIXTH sentence
///      written next month fails until it is recorded.
///
/// Staleness — « is this still true? » — is deliberately NOT here. It is on the
/// `production-checks` cron, which opens an issue and cannot block a merge. See
/// `web/tests/stub-clock.test.ts`: a suite green at every hour except one fails
/// a future PR at random and looks like that PR's fault.

const WEB = process.cwd();
const REPO = join(WEB, '..');

type Surface = {
  file: string;
  anchor: string;
  what: string;
  atRegistration: string;
};

type Manifest = {
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

const manifest: Manifest = JSON.parse(
  readFileSync(join(REPO, 'infra/legal/registration-manifest.json'), 'utf8'),
);

const readRepoFile = (file: string) => readFileSync(join(REPO, file), 'utf8');

/// Four guards in this repo have matched a string that existed only in a
/// comment — one of them the comment explaining that footgun. Blanking rather
/// than deleting keeps line numbers honest for the failure message.
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/(^|[^:])\/\/.*$/gm, (_m, before: string) => before);
}

/// THE PURE CORE. Both directions in one function so neither can be the branch
/// nobody exercises: while unregistered, a MISSING anchor is the defect; once
/// registered, a SURVIVING anchor is.
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
        `${s.file}: « ${s.anchor} » is gone, but registration-manifest.json ` +
          `still says registered=false (${s.what})`,
      ];
    }
    return [];
  });
}

describe('the registration claim, and every surface that carries it', () => {
  it('every surface is in the state the manifest records', () => {
    // THE GUARD. It reads `registered` rather than pinning it, so it is correct
    // in BOTH worlds: while false, a surface that stopped saying « en cours »
    // is the defect; once true, a surface that still says it is. The old
    // `legal.test.tsx` assertion could only ever be right in the first world,
    // which is why it went red the day the claim was corrected.
    expect(
      pendingViolations(manifest.registered, manifest.surfaces, readRepoFile),
      'infra/legal/registration-manifest.json and the pages disagree',
    ).toEqual([]);
  });

  it('the other direction fires, and says what to do', () => {
    // A check that cannot fire is worse than no check — and with `registered`
    // false, the branch that matters on registration day never runs. Flipping
    // the flag against the REAL tree runs it today: every recorded surface must
    // be flagged, and each message must carry its own instruction, because a
    // checklist that names files without saying what they become is a red
    // suite nobody can act on.
    const checklist = pendingViolations(
      !manifest.registered,
      manifest.surfaces,
      readRepoFile,
    );
    expect(checklist).toHaveLength(manifest.surfaces.length);
    for (const s of manifest.surfaces) {
      // `toContain('')` is true of every string, so the instruction has to be
      // shown to exist before it is looked for. Found by mutation: blanking an
      // `atRegistration` left this whole test green.
      expect(
        s.atRegistration.length,
        `${s.file} « ${s.anchor} » records no instruction`,
      ).toBeGreaterThan(10);
      expect(checklist.join('\n')).toContain(s.file);
      expect(checklist.join('\n')).toContain(s.atRegistration);
    }
  });

  it('a comment is not a surface', () => {
    // `lib/legal.ts` names the RCCM in its docstring as well as in
    // `pendingFacts`. If the stripper failed open, deleting the real data would
    // still "pass" on the comment — the defect this repo has hit four times.
    const raw = readRepoFile('web/lib/legal.ts');
    const inACommentOnly = 'owner decision, docs/design/legal-l1.md';
    // THE CONTROL. Without this the assertion below passes just as happily if
    // the sentence was deleted from the file — absence proving nothing about
    // the stripper. It has to be there before its removal means anything.
    expect(raw).toContain(inACommentOnly);
    expect(stripComments(raw)).not.toContain(inACommentOnly);
    expect(stripComments(raw)).toContain('numéro RCCM');
  });

  it('the cron checker stays read-only, and is not merely empty', () => {
    // infra/gcp/97-verify-log-retention.sh is pinned the same way by
    // backend/test/infra/log_retention_test.dart: a commented-out mutating
    // call is a line someone uncomments at 2am. The `readFileSync` assertion
    // is the control — without it this passes just as happily on a file that
    // does nothing at all.
    const src = readRepoFile('infra/legal/98-verify-registration-attestation.mjs');
    expect(src).toContain('readFileSync');
    expect(src).not.toMatch(/writeFileSync|appendFile|unlinkSync|execSync|spawn/);
  });

  it('carries an attestation the cron can actually read', () => {
    // `attestedOn` is consumed only by infra/legal/98-verify-*.mjs, which runs
    // once a day. Without this, a typo there would be invisible until the next
    // 06:00 UTC — and the failure would look like the monitor, not the edit.
    expect(manifest.attestedOn).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(Number.isNaN(Date.parse(manifest.attestedOn))).toBe(false);
    expect(manifest.attestationMaxAgeDays).toBeGreaterThan(0);
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
  const anchors = [
    ...manifest.surfaces.map((s) => s.anchor),
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
    // lines and passes the real assertion below for the wrong reason. This is
    // the floor that makes the next test mean something.
    expect(hits.length).toBeGreaterThanOrEqual(manifest.surfaces.length);
    expect(hits.map((h) => h.file)).toContain(
      'web/app/politique-confidentialite/page.tsx',
    );
  });

  it('every registration sentence in the tree is a recorded surface', () => {
    // Widening a list fixes the instance, not the blindness — so the list is
    // re-derived here instead of trusted. A new « dès notre immatriculation »
    // written next month fails until someone records what it must become.
    // Anchors are removed from the line and the pattern re-run, rather than
    // asking whether the line merely CONTAINS an anchor. Found by mutation: a
    // new « Dès notre immatriculation » sentence written onto the same line as
    // an exempt phrase passed a contains-check, because the exemption covered
    // the whole line instead of the words that earned it.
    const unrecorded = hits.filter((h) => {
      const rest = anchors.reduce((t, a) => t.split(a).join(' '), h.text);
      return pattern.test(rest);
    });
    expect(
      unrecorded.map((h) => `${h.file}:${h.line} ${h.text.trim()}`),
      'add these to infra/legal/registration-manifest.json (surfaces, or scan.allowedAnchors if unrelated)',
    ).toEqual([]);
  });
});
