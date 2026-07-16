import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';

/// The closed-theme firewall (docs/design/WEB-SYSTEM.md §2, §15 rows 6 + 7).
///
/// WHY THIS EXISTS, given `eslint-plugin-tailwindcss` already runs:
///
/// 1. **Tailwind does not error on an unknown utility — it emits nothing.** A
///    dead class is not a build failure, a type error or a test failure; it is an
///    element with no styling, shipped. So `next build` passing proves nothing.
/// 2. **The lint has a blind spot.** `no-custom-classname` only sees JSX
///    `className`/`class` attributes and configured callees. It CANNOT see a bare
///    `const base = 'rounded-full px-l …'` — and three such strings exist
///    (Button.tsx, TaxonomyLandingView.tsx, DayHoursEditor.tsx). B2a's
///    `rounded-full` → `rounded-pill` sweep had to be a TEXT replace, not an AST
///    codemod, for exactly this reason. An AST codemod would have left
///    TaxonomyLandingView's chip silently un-pilled and lint would have said green.
///
/// So: lint is the ergonomic gate (it fires in the editor), and this is the net.
/// The mirror of mobile's `test/unit/design_system_pin_test.dart`, shaped like
/// `time-pin.test.ts`'s rule table.

const ROOT = process.cwd();
const DIRS = ['app', 'components'];

function walk(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx|css)$/.test(name)) out.push(p);
  }
  return out;
}

/// Blank out comments, keeping line numbers intact.
///
/// This is load-bearing, and it was found the hard way: this very file's z-index
/// rule went red on B2a's own PROSE — `JournalPanel.tsx`'s comment explaining the
/// z-40 fix contains the text "`z-40`", and a backtick is one of the delimiters
/// the rule accepts. A pin that flags the documentation OF a fix punishes the
/// person who explains their work, so it would have been deleted within a month.
/// Classes in a comment ship nothing; only code counts.
function stripComments(src: string): string[] {
  const out: string[] = [];
  let inBlock = false;
  for (const raw of src.split('\n')) {
    let line = raw;
    if (inBlock) {
      const end = line.indexOf('*/');
      if (end === -1) { out.push(''); continue; }
      line = ' '.repeat(end + 2) + line.slice(end + 2);
      inBlock = false;
    }
    // Block comments opening on this line (incl. JSX `{/* … */}`).
    for (;;) {
      const start = line.indexOf('/*');
      if (start === -1) break;
      const end = line.indexOf('*/', start + 2);
      if (end === -1) { line = line.slice(0, start); inBlock = true; break; }
      line = line.slice(0, start) + ' '.repeat(end + 2 - start) + line.slice(end + 2);
    }
    // Line comments — but not the `//` of a URL.
    line = line.replace(/(^|[^:])\/\/.*$/, '$1');
    out.push(line);
  }
  return out;
}

const files = DIRS.flatMap((d) => walk(join(ROOT, d))).map((p) => {
  const content = readFileSync(p, 'utf8');
  return {
    rel: relative(ROOT, p),
    content,
    // Code only — see stripComments.
    lines: stripComments(content),
  };
});

const RULES: { name: string; pattern: RegExp; allow: string[]; hint: string }[] =
  [
    {
      name: 'no default palette',
      // The theme is closed, so these emit NOTHING — they are invisible, not red.
      pattern:
        /\b(?:bg|text|border|fill|stroke|ring|divide|from|to|via)-(?:white|black|gray|slate|zinc|neutral|stone|red|blue|green|yellow|amber|emerald|indigo|purple|pink|orange|teal|cyan|lime|violet|fuchsia|rose|sky)(?:-\d{2,3})?\b/,
      allow: [],
      hint: 'use a token (styles/tokens.ts). `black`/`white` are `primary`/`secondary`',
    },
    {
      name: 'no default radius',
      // `rounded-full` and bare `rounded` were Tailwind's own keys and are gone.
      pattern: /\brounded(?:-(?:full|none|2xl|3xl))?(?=[\s"'`}]|$)/,
      allow: [],
      hint: 'use rounded-sm|md|lg|xl|xxl|pill (radius, styles/tokens.ts)',
    },
    {
      name: 'z-index is a named LAYER, never a number',
      // WEB-SYSTEM §9. Numbers were how `z-[1100]` and the JournalPanel/drawer
      // 40/40 tie happened: a number carries no intent, so nobody could see the
      // collision.
      // `(?![\w-])`, NOT `\b`: a `\b` after `]` requires a word char next, and
      // `z-[1100]` is always followed by a quote or space — so the arbitrary
      // branch silently never fired. This pin shipped blind to the exact value
      // its own comment names, until the review proved it.
      pattern: /(?:^|[\s"'`:])-?z-(?:\[[^\]]*\]|\d+)(?![\w-])/,
      allow: [],
      hint: 'use z-base|sticky|dropdown|overlay|modal|toast|auto',
    },
    {
      name: 'no default duration',
      pattern: /(?:^|[\s"'`:])duration-\d+\b/,
      allow: [],
      hint: 'use duration-stagger|fast|base|emphasis|slow (SYSTEM.md §9 motion)',
    },
    {
      name: 'rhythm is a token — no numeric padding/margin/gap',
      // NOTE the sizing keys (w-/h-/min-*/max-h/inset/translate) are deliberately
      // NOT here: they are carved out of the closed theme until B2c gives the web
      // a sizing scale (see tailwind.config.ts). `p-4` is dead; `w-60` is not.
      // `-0` is exempt: `0` is a real token key (spacing.0) — `inset-0`/`lg:pb-0`
      // are legal. So match `px`, any decimal, or any number with a non-zero
      // digit — but never a bare `0`.
      pattern:
        /(?:^|[\s"'`:])-?(?:p|px|py|pt|pr|pb|pl|m|mx|my|mt|mr|mb|ml|gap|gap-x|gap-y|space-x|space-y)-(?:px|\d+\.\d+|0*[1-9]\d*)(?=[\s"'`}]|$)/,
      allow: [],
      hint: 'use the rhythm tokens: xs|s|sm|m|l|xl|xxl|xxxl (or 0)',
    },
  ];

describe('the closed theme holds (WEB-SYSTEM §2)', () => {
  for (const rule of RULES) {
    it(rule.name, () => {
      const offenders = files
        .filter((f) => !rule.allow.includes(f.rel))
        .flatMap((f) =>
          f.lines
            .map((line, i) => ({ line, n: i + 1 }))
            .filter(({ line }) => rule.pattern.test(line))
            .map(({ n }) => `${f.rel}:${n}`),
        );
      expect(
        offenders,
        `${rule.hint}\n${offenders.join('\n')}`,
      ).toEqual([]);
    });
  }
});

describe('every arbitrary value is DECLARED (WEB-SYSTEM §2)', () => {
  // The escape hatch has to stay visible or it stops being an exception and
  // becomes the norm. Mirrors SYSTEM.md §20's `// ds-ignore` for the Flutter pin:
  // a disable without a written reason is not a decision, it is a silencer.
  it('a tailwindcss eslint-disable carries a ds-ignore reason', () => {
    const offenders: string[] = [];
    for (const f of files) {
      const lines = f.content.split('\n');
      lines.forEach((line, i) => {
        if (!/eslint-disable(?:-next-line)?\s+tailwindcss\//.test(line)) return;
        // The reason sits ABOVE the directive, because `-next-line` binds to the
        // line that follows it — a reason on the same line would push the
        // directive away from the class it exempts.
        const window = lines.slice(Math.max(0, i - 6), i + 1).join('\n');
        if (!/ds-ignore:\s*\S/.test(window)) offenders.push(`${f.rel}:${i + 1}`);
      });
    }
    expect(
      offenders,
      `an eslint-disable for a tailwindcss rule needs a "// ds-ignore: <why>" line\nabove it (within 6 lines) saying why no token can express this:\n${offenders.join('\n')}`,
    ).toEqual([]);
  });
});
