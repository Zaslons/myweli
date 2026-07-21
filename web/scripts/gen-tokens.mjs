#!/usr/bin/env node
// `npm run gen:tokens` — the healing tool for the token mirror (B3).
//
// Prints the five Dart-mirrored families (+ the two doc-pinned web-only
// families) rendered exactly in tokens.ts's value style. It writes NOTHING:
// tokens.ts is hand-owned — its comments carry the six drift histories, and
// the gate (tests/tokens.mirror.test.ts) is what enforces equality. When the
// gate goes red, run this, paste the VALUES into the existing structure, and
// keep the comments.

import {
  WEB_ONLY,
  expectedWebTokens,
} from './dart-tokens.mjs';

const t = expectedWebTokens();

const line = (k, v, indent = '  ') => `${indent}${k}: ${JSON.stringify(v).replace(/"/g, "'")},`;

console.log(`// Generated from mobile/lib/core/theme/ + the SYSTEM/WEB-SYSTEM §9 tables.
// Paste VALUES into web/styles/tokens.ts — the doctrine comments there are
// yours to keep. The gate: npx vitest run tests/tokens.mirror.test.ts
`);

console.log('export const colors = {');
for (const [k, v] of Object.entries(t.colors)) console.log(line(k, v));
console.log('} as const;\n');

console.log('export const spacing = {');
console.log(`  0: '0px', // WEB_ONLY: ${WEB_ONLY.spacing.join(', ')} — inset-0/pb-0 need the key`);
for (const [k, v] of Object.entries(t.spacing)) console.log(line(k, v));
console.log('} as const;\n');

console.log('export const radius = {');
for (const [k, v] of Object.entries(t.radius)) console.log(line(k, v));
console.log('} as const;\n');

console.log('export const type = {');
for (const [k, [size, opts]] of Object.entries(t.type)) {
  console.log(
    `  ${k}: ['${size}', { lineHeight: '${opts.lineHeight}', letterSpacing: '${opts.letterSpacing}' }],`,
  );
}
console.log('} satisfies Record<string, TypeToken>;\n');

console.log('export const icon = {');
for (const [k, v] of Object.entries(t.icon)) console.log(line(k, v));
console.log('} satisfies Record<string, string>;\n');

console.log('export const motion = {');
console.log(`  DEFAULT: '${t.motion.base}', // = base — every bare \`transition\` reads it`);
for (const [k, v] of Object.entries(t.motion)) console.log(line(k, v));
console.log('} as const;\n');

console.log('export const zIndex = {');
for (const [k, v] of Object.entries(t.zIndex)) console.log(line(k, v));
console.log(`  auto: 'auto', // the flex-item escape (WEB-SYSTEM §9)`);
console.log('} as const;');
