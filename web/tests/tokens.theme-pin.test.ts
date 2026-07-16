import { readFileSync, readdirSync, statSync } from 'node:fs';
import ts from 'typescript';
import { join, relative } from 'node:path';
import resolveConfig from 'tailwindcss/resolveConfig';
import { describe, expect, it } from 'vitest';

import tailwindConfig from '../tailwind.config';
import { colors, icon, type } from '../styles/tokens';

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
    else if (/\.tsx?$/.test(name)) out.push(p);
  }
  return out;
}

/// Every string literal in a .ts/.tsx file, with its line number.
///
/// This walks the TypeScript AST rather than regexing the source, and that is
/// load-bearing twice over:
///
/// 1. **Comments are never visited.** The z-index rule once went red on B2a's own
///    PROSE — a comment explaining the `z-40` fix contains the text "`z-40`", and a
///    backtick is one of the rule's delimiters. A pin that flags the documentation
///    OF a fix punishes the person who explains their work, so it gets deleted.
/// 2. **Strings are not comments.** The regex stripper this replaces treated the
///    `/*` inside `accept="image/*"` as a block-comment opener with no close — so
///    the pin went BLIND from that line to end-of-file in MediasClient.tsx (x2) and
///    DepositProof.tsx. It shipped that way in B2a. Any violation below those lines
///    was invisible. A parser cannot make that mistake; a regex always can.
///
/// It also reaches the places a `className=`-anchored scan cannot: bare `const`
/// strings (Button.tsx, TaxonomyLandingView.tsx, DayHoursEditor.tsx) and default
/// parameter values (SalonTimeHint.tsx) — which is exactly ESLint's blind spot and
/// the reason this file exists.
function literalsOf(file: string, content: string): { text: string; line: number }[] {
  const src = ts.createSourceFile(
    file,
    content,
    ts.ScriptTarget.Latest,
    /* setParentNodes */ true,
    file.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
  );
  const out: { text: string; line: number }[] = [];
  const visit = (node: ts.Node): void => {
    if (
      ts.isStringLiteral(node) ||
      ts.isNoSubstitutionTemplateLiteral(node) ||
      ts.isTemplateHead(node) ||
      ts.isTemplateMiddle(node) ||
      ts.isTemplateTail(node)
      // NOT isJsxText: that re-admits prose. `<p>use text-sm here</p>` is text a
      // user reads, not a class — and flagging it is the same mistake the regex
      // stripper made with comments.
    ) {
      const { line } = src.getLineAndCharacterOfPosition(node.getStart(src));
      out.push({ text: node.text, line: line + 1 });
    }
    ts.forEachChild(node, visit);
  };
  visit(src);
  return out;
}

const files = DIRS.flatMap((d) => walk(join(ROOT, d))).map((p) => {
  const content = readFileSync(p, 'utf8');
  const rel = relative(ROOT, p);
  return {
    rel,
    content,
    literals: literalsOf(p, content),
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
      name: 'type is a token — no default size, no raw px (§3, §4)',
      // The mirror of mobile's rule ("never TextStyle(fontSize:) — pick a scale
      // entry"), and as blunt: any hit fails. A class must say what the text IS
      // (`text-bodyMedium`), not how big it happens to be (`text-sm`).
      //
      // `text-` is heavily overloaded — `text-primary`, `text-textSecondary`,
      // `text-center`, `text-ellipsis` are all legal and must not match. The
      // lookbehind/lookahead pin it to exactly the default size scale.
      //
      // `text-[Npx]` is banned too: the 11px floor is not negotiable (§4 — "there
      // is no 10px token and there will not be one"), and an arbitrary size also
      // emits font-size with NO line-height, silently dropping the baked one.
      pattern: /(?<![\w-])text-(?:xs|sm|base|lg|xl|[2-9]xl|\[[^\]]*\])(?![\w-])/,
      allow: [],
      hint: 'use a scale entry: text-labelSmall|bodySmall|labelMedium|bodyMedium|titleSmall|labelLarge|bodyLarge|titleMedium|titleLarge|headlineSmall|headlineMedium|headlineLarge',
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
          f.literals
            .filter(({ text }) => rule.pattern.test(text))
            .map(({ line }) => `${f.rel}:${line}`),
        );
      expect(
        offenders,
        `${rule.hint}\n${offenders.join('\n')}`,
      ).toEqual([]);
    });
  }
});

describe('the tokens are actually WIRED, not just spelled', () => {
  // Every rule above is a PROHIBITION, and a prohibition cannot see the worst
  // failure this design system has. It happened during B2b: the call sites were
  // migrated to `text-bodyMedium` before `fontSize: type` was wired into the
  // config, so for a window every one of the 555 type classes emitted NOTHING and
  // the whole site rendered at the browser default — while this file passed 6/6
  // green, because the old tokens it bans were indeed gone.
  //
  // "No forbidden classes" is not the same claim as "the classes we use exist".
  // This is the second claim.
  it('every type role and icon size survives into the resolved theme', () => {
    // `fontSize` carries BOTH scales: the type roles (§4) and the icon sizes
    // (§7), because every icon on the web is a text character and its size IS a
    // font-size. This went red the moment B2c added `icon` — which is the rule
    // working: it is the only assertion that notices a token that isn't wired.
    const resolved = resolveConfig(tailwindConfig as never);
    expect(Object.keys(resolved.theme!.fontSize!).sort()).toEqual(
      [...Object.keys(type), ...Object.keys(icon)].sort(),
    );
  });

  // Catches a typo'd token — `text-bodyMedum` — which Tailwind renders as nothing
  // at all. ESLint catches it on a `className=` attribute; it cannot see the four
  // bare `const`/default-param strings, and this can.
  it('every token-shaped `text-*` is a real token, not a typo', () => {
    // `text-` is overloaded four ways: a TYPE role (`text-bodyMedium`), a COLOUR
    // (`text-textSecondary`), and Tailwind's own alignment/overflow/wrap
    // utilities, which are not tokens at all. An offender is one that is none of
    // those — i.e. a name shaped like a token that does not exist, which Tailwind
    // renders as nothing.
    const TAILWIND_TEXT_UTILS = [
      'left', 'center', 'right', 'justify', 'start', 'end', // text-align
      'ellipsis', 'clip', // text-overflow
      'wrap', 'nowrap', 'balance', 'pretty', // text-wrap
    ];
    const known = new Set([
      ...Object.keys(type),
      ...Object.keys(icon),
      ...Object.keys(colors),
      // CSS keywords added at the CONFIG level ({transparent, current, ...colors}
      // in tailwind.config.ts), not in tokens.ts — they are not colours and
      // cannot drift, but they are real classes (Button's isLoading spinner uses
      // text-transparent to keep its accessible name while hiding the label).
      'transparent',
      'current',
      ...TAILWIND_TEXT_UTILS,
    ]);
    const offenders: string[] = [];
    for (const f of files) {
      for (const { text, line } of f.literals) {
        // NOT `[a-z]+[A-Z]…`: requiring a capital let an all-lowercase typo
        // (`text-bodymedium`) through BOTH gates — the pin skipped it for having
        // no capital, and ESLint cannot see a bare const at all. Match any
        // alphabetic suffix and let the known-set decide.
        for (const m of text.matchAll(/(?<![\w-])text-([A-Za-z]{3,})(?![\w-])/g)) {
          if (!known.has(m[1])) offenders.push(`${f.rel}:${line} — text-${m[1]}`);
        }
      }
    }
    expect(
      offenders,
      `these look like a token but are in neither the type scale nor the palette,\nso Tailwind emits NOTHING for them:\n${offenders.join('\n')}`,
    ).toEqual([]);
  });
});

describe('every arbitrary value is DECLARED (WEB-SYSTEM §2)', () => {
  // The escape hatch has to stay visible or it stops being an exception and
  // becomes the norm. Mirrors SYSTEM.md §20's `// ds-ignore` for the Flutter pin:
  // a disable without a written reason is not a decision, it is a silencer.
  it('a tailwindcss OR jsx-a11y eslint-disable carries a ds-ignore reason', () => {
    // Extended in B4 when jsx-a11y strict landed: an a11y disable without prose
    // is the exact silencer-not-decision failure this rule exists for. B4 itself
    // shipped with ZERO of either (the 16 strict errors were all fixed for real).
    const offenders: string[] = [];
    for (const f of files) {
      const lines = f.content.split('\n');
      lines.forEach((line, i) => {
        if (!/eslint-disable(?:-next-line)?\s+(?:tailwindcss\/|jsx-a11y\/)/.test(line)) return;
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
