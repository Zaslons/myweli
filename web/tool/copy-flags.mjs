/// Copies the country flag SVGs into `public/flags/` before the build.
///
/// **Why this exists.** `react-phone-number-input` defaults `flagUrl` to
/// `https://purecatamphetamine.github.io/country-flag-icons/3x2/{XX}.svg` — a
/// GitHub Pages host. Measured on production 2026-08-21: loading
/// `/pro/inscription` with no interaction fetched a flag from
/// `purecatamphetamine.github.io`, disclosing the visitor's IP and user-agent to
/// GitHub. GitHub appears nowhere in the privacy policy's « Qui d'autre les
/// reçoit », and the page claims nothing is sent to a third party until the
/// visitor chooses one. Serving the flags ourselves makes the claim true rather
/// than rewriting it — the instruction the whole phase opened with.
///
/// **Copied rather than committed:** 267 files, 1.3 MB of vendor assets. They
/// are gitignored and regenerated from the locked dependency, so they cannot
/// drift from it.
///
/// **Fails loudly.** A silent miss here would put the flags back on GitHub in
/// the form of 404s and a broken control, so an empty copy is an error.
import { copyFile, mkdir, readdir, rm } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const src = resolve(here, '../node_modules/country-flag-icons/3x2');
const dest = resolve(here, '../public/flags');

let names;
try {
  names = (await readdir(src)).filter((f) => f.endsWith('.svg'));
} catch {
  console.error(
    `::error::cannot read ${src} — is country-flag-icons installed? ` +
      'Without it the phone field falls back to fetching flags from GitHub.',
  );
  process.exit(1);
}
if (names.length < 200) {
  console.error(`::error::only ${names.length} flag SVGs found; expected ~267.`);
  process.exit(1);
}

await rm(dest, { recursive: true, force: true });
await mkdir(dest, { recursive: true });
// The SVGs only. A recursive copy of the directory also drags in the package's
// own index files, so `public/` would hold two more entries than this script
// reports — a small lie, and the kind that makes a later count confusing.
await Promise.all(
  names.map((f) => copyFile(resolve(src, f), resolve(dest, f))),
);
console.log(`flags: copied ${names.length} SVGs to public/flags/`);
