import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from '@playwright/test';

/// **Does the DEPLOYED site still say what the manifest says it says?**
///
///   npm run check:legal                        # production
///   PRIVACY_URL=https://staging… npm run check:legal
///
/// **Why this exists.** Every other guard on the registration claim reads the
/// repository: the merge gate holds `infra/legal/registration-manifest.json` to
/// the source, and the cron asks whether anyone has re-confirmed the fact. None
/// of them can see myweli.com. There is no deploy workflow for `web/` — the
/// site is whatever Vercel last promoted — so **a rollback to a pre-registration
/// deployment would restore « société en cours d'immatriculation » to the live
/// mentions légales with the entire suite green.** That is guardrail 3, « the
/// manifest is not the deployment », left open by four audit rounds.
///
/// It is a MONITOR, not a gate: a failure here means production is already
/// wrong, and there is no merge to block.
///
/// **It reads `registered` rather than pinning today's wording.** While the
/// claim is pending the published page must carry the pending sentences; once
/// registered it must carry the published ones and none of the old. The first
/// version of the merge gate pinned today's world and went red on the day the
/// claim was corrected — five times, in different costumes. This one cannot.

type Surface = {
  file: string;
  anchor: string;
  what: string;
  atRegistration: string;
  publishedAnchor?: string;
};

// `npm run check:legal` and the workflow's `working-directory: web` both put
// cwd at web/, the same assumption tests/registration-claim.test.ts makes.
const manifest: {
  registered: boolean;
  surfaces: Surface[];
} = JSON.parse(
  readFileSync(
    join(process.cwd(), '..', 'infra/legal/registration-manifest.json'),
    'utf8',
  ),
);

const target = process.env.PRIVACY_URL ?? 'https://myweli.com';

test.use({ baseURL: target });

/// The two pages a visitor can actually read the claim on. `docs/` and `lib/`
/// surfaces have no url, so they are the merge gate's business, not this file's.
const ROUTES: Record<string, string> = {
  'web/app/mentions-legales/page.tsx': '/mentions-legales',
  'web/app/politique-confidentialite/page.tsx': '/politique-confidentialite',
};

/// The rendered wording, whitespace-normalised. A published sentence is
/// Prettier-wrapped in the source and re-flowed by the browser, so comparing
/// raw text would fail on line breaks that mean nothing — the same defect that
/// cost the merge gate two rounds.
async function visibleText(page: import('@playwright/test').Page, path: string) {
  await page.goto(path, { waitUntil: 'domcontentloaded' });
  const body = await page.locator('body').innerText();
  return body.replace(/\s+/g, ' ');
}

for (const [file, path] of Object.entries(ROUTES)) {
  const surfaces = manifest.surfaces.filter((s) => s.file === file);

  test(`${path} publishes the claim the manifest records`, async ({ page }) => {
    // A control first: an empty or error page trivially satisfies « the old
    // wording is absent », which is the assertion that matters once registered.
    const text = await visibleText(page, path);
    expect(
      text.length,
      `${path} rendered almost nothing — the assertions below would pass on a 404`,
    ).toBeGreaterThan(500);
    expect(surfaces.length, `no surface recorded for ${file}`).toBeGreaterThan(0);

    for (const s of surfaces) {
      const anchor = s.anchor.replace(/\s+/g, ' ');
      if (!manifest.registered) {
        expect(
          text,
          `${path} no longer publishes « ${anchor} », which the manifest still ` +
            `records as pending. Either production is serving an older ` +
            `deployment, or the repo and the site have diverged.`,
        ).toContain(anchor);
      } else {
        expect(
          text,
          `${path} still publishes « ${anchor} » after registration — a stale ` +
            `deployment, or a rollback.`,
        ).not.toContain(anchor);
        const published = (s.publishedAnchor ?? '').replace(/\s+/g, ' ');
        expect(
          published.length,
          `${file} records no publishedAnchor; the merge gate should have caught this`,
        ).toBeGreaterThan(0);
        expect(
          text,
          `${path} does not publish « ${published} » — the registered wording ` +
            `is in the repo and not on the site.`,
        ).toContain(published);
      }
    }
  });
}
