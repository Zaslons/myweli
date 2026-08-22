import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import CguPage from '../app/cgu/page';
import MentionsPage from '../app/mentions-legales/page';
import ConfidentialitePage from '../app/politique-confidentialite/page';
import SuppressionPage from '../app/suppression-compte/page';
import pkg from '../package.json';
import { COMPANY, LEGAL_ROUTES, LEGAL_UPDATED_AT } from '../lib/legal';

/// L1 — the four documents, at the unit level.
///
/// The e2e specs prove the routes resolve and are accessible. This file proves
/// the things a rendered page cannot show you: that all four read ONE date, that
/// the slugs the app links to are the slugs that exist, and that the marker
/// separating engineering facts from legal judgement never shipped.

// `globals` is off in `vitest.config.ts`, so RTL's auto-cleanup never runs and
// each `render` STACKS in the same document. Without this the h1 counts read
// 1 → 3 → 5 → 7 across the file — which is exactly how this was found: three
// pages "had" extra h1s that a DOM dump showed were the previous tests' renders.
// The house idiom (b6-rating-chip, add-salon, abonnement-setup) is explicit.
afterEach(cleanup);

const PAGES = [
  ['politique de confidentialité', ConfidentialitePage],
  ['CGU', CguPage],
  ['mentions légales', MentionsPage],
  ['suppression de compte', SuppressionPage],
] as const;

describe('the legal documents', () => {
  for (const [name, Page] of PAGES) {
    it(`${name} renders one h1 and the shared date`, () => {
      render(<Page />);
      expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
      // Not "a date" — THE date. Four documents that each carried their own
      // would drift the first time one was amended.
      expect(
        screen.getByText(new RegExp(LEGAL_UPDATED_AT.label)),
      ).toBeInTheDocument();
    });

    it(`${name} contains no counsel marker`, () => {
      // « à valider par un conseil » lives in docs/design/legal-l1.md, where it
      // marks the boundary between claims measured from the code and claims
      // that need a lawyer. Shipping it would publish an unfinished document.
      const { container } = render(<Page />);
      expect(container.textContent ?? '').not.toMatch(/à valider/i);
    });
  }

  it('reading copy is bodyLarge, per B8', () => {
    // WEB-SYSTEM §3 / web-b8-reading-text.md: « une phrase française posée
    // comme contenu → 16 ». Legal prose is unambiguously reading copy, and the
    // closed theme means a typo'd utility emits NOTHING rather than erroring —
    // so a page can ship unstyled with every other test green.
    const { container } = render(<ConfidentialitePage />);
    const paragraphs = Array.from(container.querySelectorAll('p'));
    expect(paragraphs.length).toBeGreaterThan(3);
    for (const p of paragraphs) {
      expect(p.className).toMatch(/text-body(Large|Medium)/);
    }
  });
});

/// The guard that did not exist on 2026-08-18, when the live privacy policy was
/// found to contain two false statements.
///
/// Both had been true when written. « pas de Sentry » was made false by adding
/// Sentry months later, and « aucun journal applicatif » by migrating to Cloud
/// Run. Nothing failed, because **nothing was checking**: the page's own doc
/// comment promised every claim was traceable to the code, and no test held it
/// to that.
///
/// The asymmetry is the whole point. A *description* that goes stale is merely
/// incomplete; a *denial* that goes stale is a false statement to users and to
/// the App Store privacy questionnaire. So the denials are what get pinned.
describe('the privacy policy does not deny what we actually ship', () => {
  // Imported rather than read from disk: the path then resolves relative to
  // THIS file, so the test cannot be silently defeated by the working directory
  // the runner happens to use.
  const deps = Object.keys(pkg.dependencies ?? {});

  // Left column: how the page would name the vendor in French. Right column:
  // how it appears in package.json. Add a row when a new telemetry vendor is
  // considered — that is cheaper than remembering to re-read the policy.
  const VENDORS: ReadonlyArray<readonly [string, string]> = [
    ['Sentry', 'sentry'],
    ['Crashlytics', 'crashlytics'],
    ['Google Analytics', 'gtag'],
    ['PostHog', 'posthog'],
    ['Mixpanel', 'mixpanel'],
    ['Amplitude', 'amplitude'],
    ['Segment', 'segment'],
    // Added 2026-08-21. The table had no row for the one vendor this project
    // is most likely to acquire by accident: we deploy on Vercel, where
    // `@vercel/analytics` is one dependency and one import away, and
    // docs/LAUNCH.md's own analytics decision names it explicitly. `analytics`
    // is deliberately a broad token — it also catches `@segment/analytics-next`
    // and `firebase_analytics` — and `gtm` catches the modern Google install
    // path (`@next/third-parties`) that none of the rows above would match.
    ['Vercel Analytics', 'vercel'],
    ['Plausible', 'plausible'],
    ['Google Tag Manager', 'gtm'],
    ['un outil de mesure d’audience', 'analytics'],
  ];

  /// **This scoping hid a false sentence, and that is the lesson to keep.** The
  /// note below is right that a guard which cannot tell a denial from a
  /// description gets disabled the first time it is wrong. But it then resolved
  /// the ambiguity by ASSUMING « nous n'envoyons aucun rapport à Sentry lorsque
  /// rien n'a échoué » was true, and it was false: a clean page load sent three
  /// session envelopes carrying the session id, the release and the full
  /// user-agent.
  ///
  /// Measuring beats scoping. `web/tool/check-privacy-promise.spec.ts` runs
  /// against a DEPLOYED url and fails if any envelope leaves on a clean load —
  /// the only place this class of defect has ever lived.
  ///
  /// The text of « Ce que nous ne faisons pas » ONLY — from that heading to the
  /// next one.
  ///
  /// Scoping matters more than it looks. A first version of this test searched
  /// the whole page for `aucun … Sentry` and failed on a sentence that is
  /// **true**: « nous n'envoyons aucun rapport à Sentry lorsque rien n'a
  /// échoué ». A guard that cannot tell a denial from an accurate description
  /// gets disabled the first time it is wrong, and then guards nothing.
  function denials(): string {
    const { container } = render(<ConfidentialitePage />);
    const start = Array.from(container.querySelectorAll('h2')).find((h) =>
      /ce que nous ne faisons pas/i.test(h.textContent ?? ''),
    );
    // Not a soft skip: if the section is renamed away, this test silently stops
    // checking anything, which is the failure mode it exists to prevent.
    expect(start, 'the « Ce que nous ne faisons pas » heading').toBeTruthy();
    let text = '';
    for (let n = start!.nextElementSibling; n && n.tagName !== 'H2'; n = n.nextElementSibling) {
      text += ` ${n.textContent ?? ''}`;
    }
    expect(text.length).toBeGreaterThan(50);
    return text;
  }

  for (const [label, token] of VENDORS) {
    const shipped = deps.some((d) => d.toLowerCase().includes(token));
    it(`${shipped ? 'does not deny' : 'may keep denying'} ${label}`, () => {
      if (shipped) {
        // The page may still *describe* what we send to a vendor elsewhere —
        // it must simply not claim, here, that we do not use it.
        expect(denials()).not.toMatch(new RegExp(label, 'i'));
      } else {
        // **This branch used to be `expect(shipped).toBe(false)`** — a
        // tautology restating the `if` it is inside. Six of the seven rows took
        // it, so the table read as coverage while asserting nothing at all.
        //
        // Now it asserts the thing that is actually load-bearing: the page
        // still SAYS SO. A silent deletion of « aucun outil de mesure
        // d'audience » would otherwise pass every check here while the
        // no-consent-banner posture quietly lost its stated justification.
        expect(
          denials().length,
          'the denials section must still be making claims',
        ).toBeGreaterThan(50);
      }
    });
  }

  /// The `else` branch above proves the denials SECTION survives; this proves
  /// the one sentence the whole no-consent-banner posture rests on survives.
  /// Deleting « aucun outil de mesure d'audience » while shipping no analytics
  /// package would otherwise pass every row in the table.
  it('still denies audience measurement, which is what justifies no banner', () => {
    expect(denials()).toMatch(/aucun outil de mesure d’audience/i);
  });

  it('discloses request logging rather than denying it', () => {
    // Cloud Run logs the IP, the user agent and the request URL of every call,
    // and no code in this repo can prove that — it is a property of the host.
    // So the guard is a PRESENCE check: the disclosure must be on the page.
    // Deleting it is how the old false claim would come back.
    const { container } = render(<ConfidentialitePage />);
    const text = container.textContent ?? '';
    expect(text).toMatch(/adresse IP/i);
    expect(text).toMatch(/30 jours/i);
    // And the specific sentence that was false must never return.
    expect(text).not.toMatch(/aucun journal applicatif/i);
  });
});

describe('lib/legal.ts is the single source of truth', () => {
  it('declares exactly the four routes, each with a leading slash', () => {
    expect(LEGAL_ROUTES).toHaveLength(4);
    for (const r of LEGAL_ROUTES) {
      expect(r.slug).toMatch(/^\/[a-z-]+$/);
      expect(r.h1.length).toBeGreaterThan(0);
      expect(r.description.length).toBeGreaterThan(0);
    }
  });

  it('the mentions légales render COMPANY, not a second copy of it', () => {
    // **This assertion used to be `COMPANY.registration` matching
    // /en cours d’immatriculation/i** — a guard aimed at the wrong end of the
    // fact. It went red the day someone CORRECTED the claim and stayed green
    // forever while it went stale, which is the opposite of what a guard on a
    // published legal claim is for.
    //
    // What the comment above it always said it wanted was the WIRING — « this
    // object is the ONE edit, which is only true if the page reads it from
    // here » — so that is what is asserted now. The claim itself is guarded by
    // tests/registration-claim.test.ts against
    // infra/legal/registration-manifest.json, which also records that the
    // « one edit » was never true — the claim has surfaces in several files,
    // listed in infra/legal/registration-manifest.json. The number is not
    // written here on purpose: two rounds of this fix shipped a wrong one.
    expect(COMPANY.tradingName).toBe('MyWeli');

    const { container } = render(<MentionsPage />);
    expect(container.textContent ?? '').toContain(COMPANY.registration);

    // Rendering the same words proves nothing on its own — a hard-coded copy
    // would read identically today and diverge at the first edit. The
    // discriminating half is that the page has no copy to diverge.
    const src = readFileSync(
      join(process.cwd(), 'app/mentions-legales/page.tsx'),
      'utf8',
    );
    expect(src).toContain('{COMPANY.registration}');
    expect(src).not.toContain('Registre du Commerce');
  });

  it('names all three hosts, because mentions légales must name the host', () => {
    // **`COMPANY.hosts.length > 0`** was the same tautology this file records
    // against the vendor table above: true of any non-empty list, including a
    // wrong one. Where MyWeli runs is a disclosure, so moving it has to touch
    // this line and be reviewed.
    expect([...COMPANY.hosts]).toEqual([
      'Google Cloud — serveurs applicatifs et base de données, Paris (France)',
      'Vercel Inc. — site web, États-Unis',
      'Cloudflare Inc. — stockage des fichiers (R2)',
    ]);
    const { container } = render(<MentionsPage />);
    for (const h of COMPANY.hosts) {
      expect(container.textContent ?? '').toContain(h);
    }
  });

  it('the slugs mobile hard-codes are the slugs that exist', () => {
    // `AppConfig.privacyUrl` and friends build these paths into the app binary,
    // and **no mobile test can reach the web** — so this list and
    // `mobile/lib/core/config/app_config.dart` are one contract reviewed in one
    // PR, and this is the web half of it. Change a slug here and you must change
    // it there, in the same commit.
    expect(LEGAL_ROUTES.map((r) => r.slug).sort()).toEqual([
      '/cgu',
      '/mentions-legales',
      '/politique-confidentialite',
      '/suppression-compte',
    ]);
  });
});
