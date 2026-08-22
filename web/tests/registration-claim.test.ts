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
import { LEGAL_UPDATED_AT } from '../lib/legal';
import { organizationJsonLd } from '../lib/seo/jsonld';

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
  /// The wording that REPLACES `anchor` once registered. Absent while pending,
  /// required the day the flag flips — see `pendingViolations`. Without it the
  /// design only ever checks that the old claim is GONE, so deleting the RCCM
  /// number the day after registration would pass every guard here.
  publishedAnchor?: string;
};

type Manifest = {
  $comment?: string[];
  registered: boolean;
  attestedOn: string;
  attestationMaxAgeDays: number;
  surfaces: Surface[];
  /// What `LEGAL_UPDATED_AT.iso` reads while the claim is pending. Once
  /// registered it must have moved — the largest legal-copy change this product
  /// will ever make is the one case the date discipline did not cover.
  legalUpdatedAtWhenPending: string;
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

/// THE PURE CORE. Every direction in one function so none is the branch nobody
/// exercises: while unregistered, a MISSING anchor is the defect; once
/// registered, a SURVIVING anchor is — **and so is the absence of what replaced
/// it.** Every message carries `atRegistration`; the first version put it only
/// on one branch, and that is what turned the suite red on registration day.
///
/// The third arm is the answer to « the registered world has no positive
/// assertion ». Without it this design checks only that the old claim is gone,
/// so on the day after registration someone could delete the RCCM number, empty
/// `COMPANY.registration`, and every guard here would stay green.
export function pendingViolations(
  registered: boolean,
  surfaces: Surface[],
  read: (file: string) => string,
): string[] {
  return surfaces.flatMap((s) => {
    // **Whitespace-normalised.** Anchors and published wording alike are
    // Prettier-wrapped in JSX, and a raw `includes` cannot match a sentence
    // broken across lines — the defect that cost the SCAN two rounds, left
    // standing in the function beside it.
    const flat = (t: string) => t.replace(/\s+/g, ' ');
    const src = flat(stripComments(read(s.file)));
    const pending = src.includes(flat(s.anchor));

    if (!registered) {
      return pending
        ? []
        : [
            `${s.file}: « ${s.anchor} » is gone (${s.what}) but the manifest ` +
              `still says registered=false — ${s.atRegistration}`,
          ];
    }

    const out: string[] = [];
    if (pending) {
      out.push(`${s.file}: still says « ${s.anchor} » — ${s.atRegistration}`);
    }
    if (!s.publishedAnchor) {
      // A surface with nothing recorded as its replacement is a silence, and
      // registration day must not be able to end in one.
      out.push(
        `${s.file}: nothing is recorded as having replaced « ${s.anchor} » — ` +
          `add \`publishedAnchor\` so the new claim is asserted PRESENT rather ` +
          `than only the old one absent — ${s.atRegistration}`,
      );
    } else if (!src.includes(flat(s.publishedAnchor))) {
      out.push(
        `${s.file}: does not carry the published wording ` +
          `« ${s.publishedAnchor} » — ${s.atRegistration}`,
      );
    }
    return out;
  });
}

/// **YAML is not JavaScript, and this file kept forgetting.** `stripComments`
/// handles `//` and `/* */`; a workflow's comments are `#`, so every assertion
/// that read a .yml as raw text could be satisfied by the very comment
/// explaining the thing it was checking. Measured three times in one commit:
/// `npm run check:legal` demoted into a comment, `actions: read` deleted with
/// its comment left behind, a ROUTES entry commented out — all green.
export function stripYamlComments(src: string): string {
  // Only a `#` at line start or after whitespace: `#` inside a quoted string or
  // a `${{ }}` expression is not a comment, and blanking one would be worse
  // than the defect. Line count is preserved for readable failures.
  return src.replace(/(^|\s)#.*$/gm, (m, before: string) => before);
}

/// One job's block, so an assertion cannot be satisfied by a DIFFERENT job.
/// Measured: `actions: read` granted to an unrelated job kept the monitor's own
/// grant deletable and green; a `needs:` list on another job satisfied the one
/// `report` was supposed to have.
export function yamlJob(src: string, name: string): string {
  // `\\Z` is Perl, not JavaScript — it matched nothing and every job came back
  // empty, which the first assertion caught. `$(?![\\s\\S])` is the JS spelling
  // of end-of-input.
  const m = stripYamlComments(src).match(
    new RegExp(`^  ${name}:$[\\s\\S]*?(?=^  \\S[^\\n]*:$|$(?![\\s\\S]))`, 'm'),
  );
  return m ? m[0] : '';
}

/// Registration must move the legal date, and the snapshot that proves it must
/// not go stale. Held BOTH ways: while pending the manifest has to track the
/// constant, so an unrelated amendment bumps both in one PR; once registered
/// they must differ. Without the pending half the registered half is worthless
/// — a date already moved for another reason would satisfy a later-than test
/// while the registration PR changed nothing.
export function legalDateProblems(
  registered: boolean,
  iso: string,
  whenPending: string,
): string[] {
  if (!registered) {
    return iso === whenPending
      ? []
      : [
          `LEGAL_UPDATED_AT.iso is ${iso} but the manifest still records ` +
            `${whenPending}. Bump \`legalUpdatedAtWhenPending\` in the same PR — ` +
            `it is the snapshot that makes the registration-day check mean ` +
            `something.`,
        ];
  }
  return iso !== whenPending
    ? []
    : [
        `LEGAL_UPDATED_AT.iso is still ${iso}, the date it read while the ` +
          `company was unregistered. Registration is the largest legal-copy ` +
          `change this product will make; a document whose substance moved ` +
          `while its date stood still is the version a regulator reads as ` +
          `concealment.`,
      ];
}

/// The RCCM published to machines. `organizationJsonLd()` goes out site-wide
/// from app/layout.tsx and carries no legal identity at all today — which is
/// right while there is none, and wrong the moment there is.
export function organizationProblems(
  registered: boolean,
  org: Record<string, unknown>,
): string[] {
  // A registration number in schema.org is normally
  // `{ '@type': 'PropertyValue', propertyID: 'RCCM', value: '…' }`. `String()`
  // rendered that as « [object Object] » and rejected the canonical encoding;
  // `JSON.stringify` then accepted it for the WRONG reason — the serialisation
  // includes KEYS, so `propertyID: 'RCCM'` with no `value` at all satisfied
  // /RCCM/i. The fix widened the guard past the defect it exists for. Read the
  // value out instead.
  const asObject = (v: unknown): { id: string; value: string } => {
    if (v == null) return { id: '', value: '' };
    if (typeof v === 'string') return { id: v, value: v };
    const o = v as Record<string, unknown>;
    return { id: String(o.propertyID ?? ''), value: String(o.value ?? '') };
  };
  const { id: identifierKind, value: identifierValue } = asObject(org.identifier);
  const identifier = identifierValue.trim();
  if (!registered) {
    // Publishing a registration number we do not have would be a worse defect
    // than publishing none, so this direction is asserted too.
    return identifier || identifierKind
      ? [
          `Organization JSON-LD claims identifier « ${identifier || identifierKind} » ` +
            `while the manifest says the company is not registered`,
        ]
      : [];
  }
  const problems: string[] = [];
  if (!identifier || !/RCCM/i.test(`${identifierKind} ${identifier}`)) {
    problems.push(
      'Organization JSON-LD carries no RCCM `identifier` — the registered ' +
        'entity is published to humans on /mentions-legales and to machines ' +
        'nowhere. Add it in web/lib/seo/jsonld.ts.',
    );
  }
  // Trimmed, and typed: `String()` on an object gives a truthy
  // « [object Object] », and '   ' is truthy — the very idiom removed one
  // branch above, left standing here.
  if (typeof org.legalName !== 'string' || !org.legalName.trim()) {
    problems.push('Organization JSON-LD carries no `legalName`');
  }
  return problems;
}

/// Shared by `allowedAnchors` and `publishedAnchor`: an anchor has to be a
/// sentence. A bare pattern token as an exemption blinds the whole scan, and a
/// one-word `publishedAnchor` asserts nothing. Extracted so BOTH callers are
/// covered by fixtures — the `allowedAnchors` loop is the only one with data in
/// it today, so a shape rule applied inline to `publishedAnchor` would be a
/// loop that never runs.
export function anchorShapeProblems(anchor: string, pattern: string): string[] {
  const problems: string[] = [];
  if (anchor.length <= 24) problems.push(`« ${anchor} » is too short to be a sentence`);
  if (anchor.trim().split(/\s+/).length <= 2) problems.push(`« ${anchor} » is not a phrase`);
  if (new RegExp(`^\\W*(${pattern})\\W*$`, 'i').test(anchor)) {
    problems.push(`« ${anchor} » is a bare pattern token`);
  }
  return problems;
}

/// **The cells run on FIXTURE surfaces, not on `manifest.surfaces`.**
///
/// They used to derive from the real list, and that coupling breaks the moment
/// a `publishedAnchor` is required: the real surfaces have none while the claim
/// is pending, so « registered + already rewritten → silence » would go red on
/// data that is correct. The truth table is a property of the FUNCTION; giving
/// it its own data keeps it that way, and the real manifest gets its own
/// separate shape test below.
const FX: Surface[] = [
  {
    file: 'lib/legal.ts',
    anchor: 'en cours d’immatriculation',
    publishedAnchor:
      'immatriculée au RCCM n° CI-ABJ-2026-B-12345, au capital de 1 000 000 FCFA',
    what: 'the constant the mentions légales render',
    atRegistration: 'publish the RCCM number and the registered name',
  },
  {
    // Two surfaces in one file: `read` receives a FILE, so a fixture that
    // returned only the first anchor would fake a violation for its sibling.
    file: 'lib/legal.ts',
    anchor: "'numéro RCCM',",
    publishedAnchor: 'siège social situé à Cocody, Abidjan, Côte d’Ivoire',
    what: 'the list of facts the page admits it cannot publish',
    atRegistration: 'empty the pending list and publish the facts themselves',
  },
  {
    file: 'app/mentions-legales/page.tsx',
    anchor: 'Immatriculation en cours.',
    publishedAnchor:
      'Société à responsabilité limitée immatriculée au registre du commerce',
    what: 'the Callout, hard-coded rather than read from the constant',
    atRegistration: 'delete the Callout',
  },
];

const fx = (file: string) => FX.filter((s) => s.file === file);
const stillPending = (file: string) => fx(file).map((s) => s.anchor).join('\n');
const alreadyRewritten = (file: string) =>
  fx(file).map((s) => s.publishedAnchor).join('\n');
/// Anchors present as TEXT but only inside comments, so this must read as
/// REWRITTEN. Delete the `stripComments` call from `pendingViolations` and THIS
/// is the fixture that goes red — measured: without it the whole suite stayed
/// green with the stripping removed, leaving this repo's most-repeated footgun
/// unguarded inside the one function built around it. The published wording is
/// included so the fixture isolates the stripper rather than tripping the
/// positive assertion beside it.
const onlyInComments = (file: string) =>
  [
    ...fx(file).map((s) => `/// a docstring that happens to quote ${s.anchor}`),
    ...fx(file).map((s) => s.publishedAnchor),
  ].join('\n');

describe('pendingViolations — every cell, in fixtures, in every world', () => {
  it('not registered + still pending → silence, correctly', () => {
    expect(pendingViolations(false, FX, stillPending)).toEqual([]);
  });

  it('registered + rewritten, with the new wording present → silence', () => {
    expect(pendingViolations(true, FX, alreadyRewritten)).toEqual([]);
  });

  it('registered + still pending → the checklist, with an instruction each', () => {
    const checklist = pendingViolations(true, FX, stillPending);
    // Two per surface now: the old wording still there, AND the new wording
    // not there yet. Both are true of a page nobody has touched, and both are
    // work the author has to do.
    expect(checklist).toHaveLength(FX.length * 2);
    for (const s of FX) {
      // `toContain('')` is true of every string, so the instruction has to be
      // shown to exist before it is looked for. Found by mutation: blanking an
      // `atRegistration` left this test green.
      expect(s.atRegistration.length).toBeGreaterThan(10);
      expect(checklist.join('\n')).toContain(s.file);
      expect(checklist.join('\n')).toContain(s.atRegistration);
      expect(checklist.join('\n')).toContain(s.anchor);
    }
  });

  it('registered + rewritten, but nothing recorded as the replacement', () => {
    // THE SILENCE THIS EXISTS TO CLOSE. A surface with no `publishedAnchor` is
    // a surface whose new claim nothing asserts — so registration day could
    // end with every guard green and the RCCM published nowhere.
    const undeclared = FX.map(({ publishedAnchor, ...rest }) => rest);
    const flagged = pendingViolations(true, undeclared, alreadyRewritten);
    expect(flagged).toHaveLength(FX.length);
    expect(flagged.join('\n')).toContain('nothing is recorded as having replaced');
  });

  it('registered, recorded, but the page does not carry it', () => {
    // The RCCM deleted the day after registration: old wording gone, new
    // wording recorded, page silent. Green before this arm existed.
    const emptied = () => 'a page with neither the old claim nor the new one';
    const flagged = pendingViolations(true, FX, emptied);
    expect(flagged).toHaveLength(FX.length);
    expect(flagged.join('\n')).toContain('does not carry the published wording');
  });

  it('an anchor surviving only in a comment is not a surface', () => {
    // THE STRIPPER, exercised where it actually runs. The dedicated
    // `stripComments` test proves the function; this proves `pendingViolations`
    // still calls it.
    expect(
      pendingViolations(true, FX, onlyInComments),
      'a commented-out anchor must not count as the claim still being made',
    ).toEqual([]);
    expect(pendingViolations(false, FX, onlyInComments)).toHaveLength(FX.length);
  });

  it('not registered + already rewritten → also flagged, also actionable', () => {
    // The half-corrected state: someone edited the pages and not the manifest.
    // This message ALSO carries `atRegistration`, because the first version did
    // not and that is what turned the suite red on registration day.
    const flagged = pendingViolations(false, FX, alreadyRewritten);
    expect(flagged).toHaveLength(FX.length);
    for (const s of FX) expect(flagged.join('\n')).toContain(s.atRegistration);
  });
});

describe('anchorShapeProblems', () => {
  // Fixture-tested because the only caller with data in it today is
  // `allowedAnchors`; a shape rule applied inline to `publishedAnchor` would be
  // a loop that never runs while the claim is pending.
  const pattern = 'immatricul|RCCM';

  it('accepts a real published sentence', () => {
    expect(
      anchorShapeProblems(
        'immatriculée au RCCM n° CI-ABJ-2026-B-12345, au capital de 1 000 000 FCFA',
        pattern,
      ),
    ).toEqual([]);
  });

  // **Each row asserts the rule that catches IT.** They shared one
  // `length > 0` oracle, and `tooShort` fires on all four — so the
  // `not a phrase` and `bare pattern token` branches could both be deleted with
  // the suite green. The bare-token rule is the one the entire kill-switch
  // defence rests on.
  it.each([
    ['a bare pattern token', 'RCCM', 'bare pattern token'],
    ['a bare token with punctuation', '(immatricul)', 'bare pattern token'],
    ['two words', 'RCCM number', 'is not a phrase'],
    ['something short', 'immatriculée au RCCM', 'too short'],
    // Long enough to clear `tooShort`, so `not a phrase` is the ONLY rule that
    // can catch it — without this row that branch is unpinned.
    ['a long two-word string', 'immatriculation-du-registre RCCM-CI-ABJ-2026', 'is not a phrase'],
  ])('rejects %s, by the rule that catches it', (_label, bad, because) => {
    expect(anchorShapeProblems(bad, pattern).join(' | ')).toContain(because);
  });
});

describe('legalDateProblems', () => {
  it('is silent when the snapshot tracks the constant, pending', () => {
    expect(legalDateProblems(false, '2026-08-22', '2026-08-22')).toEqual([]);
  });
  it('fires when the date moved while pending and the snapshot did not', () => {
    expect(legalDateProblems(false, '2026-09-01', '2026-08-22')).toHaveLength(1);
  });
  it('fires when registration did not move the date', () => {
    expect(legalDateProblems(true, '2026-08-22', '2026-08-22')).toHaveLength(1);
  });
  it('is silent once registration moved it', () => {
    expect(legalDateProblems(true, '2026-11-03', '2026-08-22')).toEqual([]);
  });
});

describe('organizationProblems', () => {
  it('is silent while pending with no identifier', () => {
    expect(organizationProblems(false, { name: 'MyWeli' })).toEqual([]);
  });
  it('fires on an identifier we have no right to publish', () => {
    expect(organizationProblems(false, { identifier: 'RCCM CI-X' })).toHaveLength(1);
  });
  it('fires once registered with nothing published', () => {
    expect(organizationProblems(true, { name: 'MyWeli' })).toHaveLength(2);
  });
  it('accepts the structured PropertyValue form', () => {
    // The accepted encoding is data, not an unwritten convention.
    expect(
      organizationProblems(true, {
        legalName: 'MyWeli SARL',
        identifier: {
          '@type': 'PropertyValue',
          propertyID: 'RCCM',
          value: 'CI-ABJ-2026-B-12345',
        },
      }),
    ).toEqual([]);
  });

  it('rejects a PropertyValue that declares RCCM and publishes no number', () => {
    // The hole the previous fix opened: `JSON.stringify` includes KEYS, so
    // `propertyID: 'RCCM'` alone satisfied /RCCM/i. Declare the schema, publish
    // nothing — the exact silence `publishedAnchor` exists to refuse.
    expect(
      organizationProblems(true, {
        legalName: 'MyWeli SARL',
        identifier: { '@type': 'PropertyValue', propertyID: 'RCCM' },
      }),
    ).toHaveLength(1);
    expect(
      organizationProblems(true, {
        legalName: 'MyWeli SARL',
        identifier: { '@type': 'PropertyValue', propertyID: 'RCCM', value: '  ' },
      }),
    ).toHaveLength(1);
  });

  it.each([
    ['an object', {}],
    ['whitespace', '   '],
  ])('rejects a legalName that is %s', (_l, legalName) => {
    expect(
      organizationProblems(true, {
        legalName,
        identifier: 'RCCM CI-ABJ-2026-B-12345',
      }).join(' '),
    ).toContain('legalName');
  });

  it('is silent once the RCCM and legal name are there', () => {
    expect(
      organizationProblems(true, {
        legalName: 'MyWeli SARL',
        identifier: 'RCCM CI-ABJ-2026-B-12345',
      }),
    ).toEqual([]);
  });
});

describe('the rest of what registration must change', () => {
  it('the legal date and its snapshot agree with the world we are in', () => {
    expect(
      legalDateProblems(
        manifest.registered,
        LEGAL_UPDATED_AT.iso,
        manifest.legalUpdatedAtWhenPending,
      ),
    ).toEqual([]);
  });

  it('the machine-readable entity agrees with the world we are in', () => {
    expect(
      organizationProblems(
        manifest.registered,
        organizationJsonLd() as unknown as Record<string, unknown>,
      ),
    ).toEqual([]);
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
      ['web/tool/check-registration-claim.spec.ts', flat('web/tool/check-registration-claim.spec.ts')],
      ['infra/ci/99-verify-monitor-alive.mjs', flat('infra/ci/99-verify-monitor-alive.mjs')],
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

  /// **Anchors are matched against the WHOLE FILE, not a line and not a window.**
  ///
  /// Per-line came first: Prettier wraps at 80 columns, so a recorded sentence
  /// spanning two lines was only ever half-seen and a correctly rewritten page
  /// was flagged. A ±1 window replaced it — and a real French éditeur clause
  /// carrying RCCM number, capital and siège social wraps over THREE lines,
  /// with the matched token on the first, so the window reached two thirds of
  /// it and failed the same way one notch out. A window is a constant that has
  /// to be guessed against a wrap count nobody controls.
  ///
  /// The window also over-reported: `rest` came from the neighbours' text but
  /// the message printed only the hit line, so an already-recorded line was
  /// listed whenever an adjacent one was not — telling the reader to record
  /// wording that was already recorded.
  ///
  /// So: normalise the file once, blank every anchor occurrence IN PLACE
  /// (preserving offsets so line numbers survive), then report the pattern
  /// matches that are still standing. Wrap-count independent, and each reported
  /// line is one that genuinely still matches.
  const scanFile = (rel: string, src: string) => {
    const lines = stripComments(src).split('\n');
    const lineOfOffset: number[] = [];
    let flat = '';
    lines.forEach((line, i) => {
      // **Trimmed, not merely collapsed.** Indented JSX leaves a leading space
      // on every line, so joining produced a DOUBLE space at each boundary and
      // no recorded sentence could ever match across a wrap — the fix for
      // wrapping, broken by wrapping. Caught by re-running the probe that
      // found the window bug rather than trusting the rewrite.
      const norm = line.replace(/\s+/g, ' ').trim();
      for (let k = 0; k <= norm.length; k += 1) lineOfOffset[flat.length + k] = i + 1;
      flat += `${norm} `;
    });

    let masked = flat;
    for (const anchor of anchorsFor(rel)) {
      const needle = anchor.replace(/\s+/g, ' ').trim();
      if (!needle) continue;
      for (let at = masked.indexOf(needle); at !== -1; at = masked.indexOf(needle, at + needle.length)) {
        masked = masked.slice(0, at) + ' '.repeat(needle.length) + masked.slice(at + needle.length);
      }
    }

    const re = new RegExp(manifest.scan.pattern, 'gi');
    // Deduped by line: « immatriculée au RCCM » is two pattern matches on one
    // sentence, and listing the same line twice makes a checklist look longer
    // than the work it describes.
    const seen = new Map<number, { file: string; line: number; text: string }>();
    for (let m = re.exec(masked); m !== null; m = re.exec(masked)) {
      const line = lineOfOffset[m.index] ?? 1;
      if (!seen.has(line)) {
        seen.set(line, { file: rel, line, text: (lines[line - 1] ?? '').trim() });
      }
    }
    return [...seen.values()];
  };

  const unrecorded = manifest.scan.roots
    .flatMap((root) => walk(join(REPO, root)))
    .map((abs) => ({ rel: relative(REPO, abs), abs }))
    .filter((f) => !manifest.scan.allowedFiles.includes(f.rel))
    .flatMap((f) => scanFile(f.rel, readFileSync(f.abs, 'utf8')));

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

  it('an exemption must be a sentence, not a bare pattern token', () => {
    // **`allowedAnchors` was left unpinned because it is the one field that has
    // to grow on registration day — and that made it a kill switch.**
    // MEASURED: adding « immatricul » and « RCCM » as exemptions subtracts a
    // whole pattern alternative from every file in the tree, so a brand-new
    // unrecorded claim passes and the suite stays green. It is worse than
    // emptying `roots`, because `roots: []` reads in review as a suspicious
    // deletion while two plausible French tokens in an anchor list read as
    // recording wording — which is exactly what the failing test tells the
    // author to do.
    //
    // So the SHAPE is pinned rather than the value. The published wording
    // (« immatriculée au RCCM n° CI-ABJ-… », 40+ characters, six-plus words)
    // satisfies all three; a bare token satisfies none. Registration day is
    // untouched.
    for (const a of manifest.scan.allowedAnchors) {
      expect(anchorShapeProblems(a, manifest.scan.pattern), a).toEqual([]);
    }
    // The same floor on every declared `publishedAnchor`: a one-word one
    // asserts nothing, and a bare pattern token in `allowedAnchors` beside it
    // would blind the scan. Empty today — which is why the rule lives in a
    // helper with its own fixtures rather than only in this loop.
    for (const s of manifest.surfaces) {
      if (s.publishedAnchor) {
        expect(
          anchorShapeProblems(s.publishedAnchor, manifest.scan.pattern),
          `${s.file} publishedAnchor`,
        ).toEqual([]);
      }
    }
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

describe('the live-site probe is wired, and covers every published surface', () => {
  /// **Nothing pinned any of this.** The probe, its npm script, its job and its
  /// place in `report.needs` were referenced only by the stale-count guard,
  /// which reads those files as flat text and asserts nothing about them. Each
  /// could be deleted in a one-line edit with the whole suite green — and the
  /// commit that added it says an earlier audit had already caught exactly the
  /// `report.needs` omission once.

  it('runs on the cron and reaches the tracking issue', () => {
    const wf = readRepoFile('.github/workflows/production-checks.yml');

    // The JOB, not the file. `toContain('npm run check:legal')` was satisfied
    // by `run: echo skipped # npm run check:legal`, and said nothing about
    // `continue-on-error`, which makes a probe that cannot fail.
    const legal = yamlJob(wf, 'legal');
    expect(legal, 'no `legal` job in production-checks.yml').not.toBe('');
    expect(legal).toContain('npm run check:legal');
    expect(
      legal,
      'continue-on-error makes the probe incapable of opening the issue',
    ).not.toContain('continue-on-error');

    // Without this a red probe never opens the issue: `report` has
    // `if: failure()`, and failure() only sees jobs listed in `needs`. Anchored
    // to `report` and split on commas — the file-wide regex matched any job's
    // needs list, and `\blegal\b` matched `legal-preflight` besides.
    const report = yamlJob(wf, 'report');
    const needs = report.match(/needs:\s*\[([^\]]*)\]/)?.[1] ?? '';
    expect(
      needs.split(',').map((n) => n.trim()),
      'the legal job is not in report.needs, so a red probe opens nothing',
    ).toContain('legal');

    const pkg = JSON.parse(readRepoFile('web/package.json')) as {
      scripts: Record<string, string>;
    };
    expect(pkg.scripts['check:legal']).toContain(
      'tool/check-registration-claim.spec.ts',
    );
  });

  it('probes every surface a visitor can actually read', () => {
    // ROUTES in the spec is hand-maintained; the manifest is the source of
    // truth. A new legal page recorded as a surface must not go unprobed —
    // widening a list fixes the instance, not the blindness, so the list is
    // derived here rather than trusted.
    // Comment-stripped and quote-agnostic. Raw, a route COMMENTED OUT kept this
    // green while the probe stopped fetching that page — and a Prettier pass to
    // double quotes turned it red for nothing. The URL is checked too: it was
    // captured and thrown away, so repointing a probe at the homepage passed.
    const spec = stripComments(
      readRepoFile('web/tool/check-registration-claim.spec.ts'),
    );
    const entries = [
      ...spec.matchAll(/['"](web\/app\/[^'"]+)['"]:\s*['"]([^'"]+)['"]/g),
    ];
    const routed = entries.map((m) => m[1]);
    for (const [, file, url] of entries) {
      const slug = file.replace(/^web\/app\//, '').replace(/\/page\.tsx$/, '');
      expect(url, `${file} is probed at ${url}`).toBe(`/${slug}`);
    }
    const published = [
      ...new Set(
        manifest.surfaces
          .map((s) => s.file)
          .filter((f) => f.startsWith('web/app/')),
      ),
    ];
    expect(published.length).toBeGreaterThan(0);
    expect(
      published.filter((f) => !routed.includes(f)),
      'these surfaces are on pages a visitor can read, and the live probe never fetches them',
    ).toEqual([]);
  });
});

describe("the dead-man's switch, exercised rather than described", () => {
  /// The attestation monitor shipped with eight "watched red" mutations that
  /// nothing could repeat — an audit called that an unrepeatable manual claim,
  /// and it was right. This one is covered from the start.
  ///
  /// `MONITOR_RUNS_JSON` supplies the API's ANSWER, so these run offline and
  /// cannot be flaky on GitHub's availability. The seam can only ever be used
  /// to make the check fail, never to make a real run pass, and the script
  /// announces when it is reading fixture data.
  const SWITCH = join(REPO, 'infra/ci/99-verify-monitor-alive.mjs');
  const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString();
  const runsJson = (created: string | null) =>
    JSON.stringify({
      workflow_runs: created === null ? [] : [{ created_at: created, conclusion: 'success' }],
    });

  const run = (env: Record<string, string>) => {
    try {
      const out = execFileSync('node', [SWITCH], {
        env: { ...process.env, GH_REPO: '', GH_TOKEN: '', ...env },
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      return { code: 0, out };
    } catch (e) {
      const err = e as { status?: number; stdout?: string; stderr?: string };
      return { code: err.status ?? -1, out: `${err.stdout ?? ''}${err.stderr ?? ''}` };
    }
  };

  it('passes on a recent scheduled run, and on the exact boundary', () => {
    expect(run({ MONITOR_RUNS_JSON: runsJson(daysAgo(0)) }).code).toBe(0);
    expect(run({ MONITOR_RUNS_JSON: runsJson(daysAgo(3)) }).code).toBe(0);
  });

  it.each([
    ['one day past the fuse', runsJson(daysAgo(4)), 'last ran on its schedule'],
    ['a long silence', runsJson(daysAgo(70)), '70 days ago'],
    // The case GitHub actually produces when it disables a schedule.
    ['never scheduled at all', runsJson(null), 'NEVER run on its schedule'],
    ['a run dated in the future', runsJson(daysAgo(-5)), 'in the future'],
    ['an unreadable date', runsJson('not-a-date'), 'unreadable date'],
    ['an unexpected API shape', '{"nope":1}', 'no workflow_runs array'],
    ['a fixture that is not JSON', '{oops', 'not JSON'],
  ])('fails closed on %s, saying which', (_label, json, expected) => {
    const r = run({ MONITOR_RUNS_JSON: json });
    expect(r.code).toBe(1);
    expect(r.out).toContain(expected as string);
    expect(r.out).toContain('::error::');
    // An unhandled throw exits 1 too, but prints a stack and no annotation.
    expect(r.out).not.toMatch(/^\s+at /m);
  });

  it('refuses to run without the repo or the token, rather than skipping', () => {
    // A check that quietly passes when it cannot authenticate is the failure
    // this whole file exists about.
    const noRepo = run({ GH_TOKEN: 'x' });
    expect(noRepo.code).toBe(1);
    expect(noRepo.out).toContain('GH_REPO is not set');

    const noToken = run({ GH_REPO: 'owner/repo' });
    expect(noToken.code).toBe(1);
    expect(noToken.out).toContain('GH_TOKEN is not set');
  });

  it('rejects a fuse that is not a positive number', () => {
    const r = run({ MONITOR_MAX_AGE_DAYS: '0', MONITOR_RUNS_JSON: runsJson(daysAgo(0)) });
    expect(r.code).toBe(1);
    expect(r.out).toContain('positive number');
  });

  it('asks GitHub only for SCHEDULED runs', () => {
    // The way this check would pass for the wrong reason: `workflow_dispatch`
    // runs appear in the same list. Measured the day it was written —
    // production-checks.yml had four runs, three manual; deploy-backend.yml had
    // 59 runs and 0 scheduled. The filter is the assertion.
    // **Stripped, and matched on the query rather than the bare token.**
    // `event=schedule` appears twice in that file: once in the comment
    // explaining why it matters, once in the URL that does it. Removing the
    // filter left the comment behind and this assertion green — the repo's
    // most-cited footgun, in the file that exports `stripComments` for it.
    const src = stripComments(readRepoFile('infra/ci/99-verify-monitor-alive.mjs'));
    expect(src).toContain('runs?event=schedule');
  });

  it('is wired into CI with the permission it needs', () => {
    // `actions: read` is requested nowhere else in this repository, and without
    // it the API answers 403 — which the script reports rather than swallows,
    // but a job that always 403s is a job nobody keeps.
    const ci = readRepoFile('.github/workflows/ci.yml');
    expect(ci).toContain('monitor-alive:');
    expect(ci).toContain('infra/ci/99-verify-monitor-alive.mjs');
    // Scoped to the job, and comment-stripped. File-wide, this stayed green
    // when the grant was deleted from `monitor-alive` and added to an unrelated
    // job — leaving the switch to 403 forever, which reads as a broken check
    // the team removes rather than a working one.
    const job = yamlJob(ci, 'monitor-alive');
    expect(job, 'no monitor-alive job in ci.yml').not.toBe('');
    expect(job).toMatch(/^\s+actions: read$/m);
    expect(job).toContain('infra/ci/99-verify-monitor-alive.mjs');

    // **THE FUSE IS A POLICY CONSTANT, AND I DID NOT INHERIT MY OWN RULE.**
    // `attestationMaxAgeDays` is pinned to exactly 90 a few hundred lines up,
    // with the note « set it to 36500 and the monitor congratulates you for a
    // century ». The switch's fuse is read from the environment and was pinned
    // by nothing: MEASURED, `MONITOR_MAX_AGE_DAYS=36500` reports ✓ on a run 964
    // days old, and `MONITOR_RUNS_JSON` makes it pass unconditionally, forever.
    // One env line in this workflow disarms the whole design in a PR nothing
    // goes red on — the same kill-switch shape an earlier round found in
    // `allowedAnchors`, and it reads in review as configuration.
    for (const knob of ['MONITOR_MAX_AGE_DAYS', 'MONITOR_RUNS_JSON', 'MONITOR_WORKFLOW']) {
      // `SET`, not merely mentioned: the ban used `toContain` over the whole
      // file, so naming a knob in a comment failed the build with a message
      // that then said something untrue.
      expect(
        job,
        `${knob} is set in the monitor-alive job — that silences the switch`,
      ).not.toMatch(new RegExp(`^\\s+${knob}:`, 'm'));
    }
    // And the default it falls back to, which the ban does not reach.
    expect(
      readRepoFile('infra/ci/99-verify-monitor-alive.mjs'),
    ).toContain("?? 'production-checks.yml'");
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
