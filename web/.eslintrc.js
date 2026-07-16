const path = require('path');

// Why this is `.eslintrc.js` and not `.eslintrc.json`: eslint-plugin-tailwindcss
// resolves the `tailwindcss` package relative to `dirname(settings.tailwindcss.config)`.
// With the relative `'tailwind.config.ts'` that dirname is `.`, the resolve fails,
// and the plugin throws "Could not resolve tailwindcss". JSON cannot compute an
// absolute path; this can.
module.exports = {
  extends: ['next/core-web-vitals', 'plugin:tailwindcss/recommended'],
  settings: {
    tailwindcss: {
      config: path.join(__dirname, 'tailwind.config.ts'),
      // Not Tailwind classes and not drift. Four are hand-written CSS in
      // styles/globals.css; `myweli-marker` is the odd one out — it has no CSS
      // at all and exists purely as a test hook
      // (tests/e2e/discovery.spec.ts locates `.myweli-marker`), so it is
      // whitelisted for a different reason and should not be "cleaned up".
      // (Pointing the plugin at cssFiles would find the other four, but is slow.)
      whitelist: ['myweli-phone', 'myweli-pin', 'myweli-marker', 'myweli-user-dot', 'is-active'],
    },
  },
  rules: {
    // The two that matter (WEB-SYSTEM.md §2, §14). The theme is CLOSED, and
    // Tailwind emits NOTHING for an unknown utility rather than erroring — so a
    // typo'd or dead class ships as an unstyled element and no build, type check
    // or golden can see it. This rule is the gate that can.
    'tailwindcss/no-custom-classname': 'error',
    // Every arbitrary value is a token that should exist. Genuine one-offs carry
    // an eslint-disable with a `ds-ignore:` reason (mirrors SYSTEM.md §20's
    // `// ds-ignore`), and tokens.theme-pin.test.ts rejects an undocumented one.
    'tailwindcss/no-arbitrary-value': 'error',
    // Off deliberately: cosmetic, and would bury the slice in churn. These come
    // from `recommended` and say nothing about token discipline —
    // `h-16 w-16` → `size-16` is a style preference, not a design-system rule.
    'tailwindcss/classnames-order': 'off',
    'tailwindcss/migration-from-tailwind-2': 'off',
    'tailwindcss/enforces-shorthand': 'off',
  },
};
