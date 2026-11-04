# Hanken Grotesk, trimmed for the site

`hanken-grotesk-latin-400-600.woff2` is cut down from
`@fontsource-variable/hanken-grotesk@5.3.0`, `files/hanken-grotesk-latin-wght-normal.woff2`
(34,704 bytes, SHA-256 `e9201eddf1d41d0b62253295d869ce3cf65768f7102b797f02c7f8c876b4a9d5`).

**Why it is cut.** The full file added about 300 ms to the home page's LCP score and went over the 2,500 ms budget. Measurements: [web-swiss-direction.md](../../../docs/design/web-swiss-direction.md) §11.

With `fontTools`:

1. `instancer`: `wght` limited to 400–600, the three weights the site uses (a theme pin refuses the others).
2. `pyftsubset`, as woff2 with no hinting:
   - **Characters:** U+0020–7E, U+00A0–FF, U+0152–53 (Œ œ), U+2013–14, U+2018–19, U+201C–1D, U+2022, U+2026, U+2039–3A, U+20AC.
   - **Features:** `kern liga ccmp mark mkmk locl`.

**Licence.** `OFL.txt` travels with it. The licence names no Reserved Font Name, so a subset may keep the name.

**Not in the file:** U+202F, the narrow no-break space in every `Intl` French amount (the original lacks it too), « Ÿ », and ★ ♥ ✓ ✕ ← →. The browser draws those from the system stack.
