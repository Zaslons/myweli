import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { cleanup, render, screen } from '@testing-library/react';
import ts from 'typescript';
import { afterEach, describe, expect, it } from 'vitest';
import CguPage from '../app/cgu/page';
import MentionsPage from '../app/mentions-legales/page';
import ConfidentialitePage from '../app/politique-confidentialite/page';
import ProSuppressionPage from '../app/pro/suppression-compte/page';
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

/// B0.18 (docs/design/salon-go-live-approval.md §6.4, Q7 « Add the sentence »):
/// the CGU says, word for word as the owner approved it, that every salon is
/// validated before it goes live. « validé », not « vérifié »: that word is the
/// identity documents' (« uniquement à vérifier votre compte », the item above).
describe('CGU §7 — MyWeli validates every salon before it goes live', () => {
  const CLAUSE =
    'Avant sa mise en ligne, chaque salon est validé par MyWeli, qui peut refuser de le publier, notamment s’il n’est pas situé en Côte d’Ivoire.';

  it('the approved sentence, word for word, in §7', () => {
    const { container } = render(<CguPage />);
    // The JSX wraps the sentence over several lines: compare its rendered text,
    // whitespace collapsed as a browser does.
    const paragraphs = Array.from(container.querySelectorAll('p')).map((p) =>
      (p.textContent ?? '').replace(/\s+/g, ' ').trim(),
    );
    expect(paragraphs).toContain(CLAUSE);
    // In §7, after « Pour les professionnels », before « Disponibilité ».
    const text = (container.textContent ?? '').replace(/\s+/g, ' ');
    const at = text.indexOf(CLAUSE);
    expect(at).toBeGreaterThan(text.indexOf('7. Pour les professionnels'));
    expect(at).toBeLessThan(text.indexOf('8. Disponibilité'));
  });
});

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
    // Since the Cloudflare front door (2026-10-07) that IP is Cloudflare's; the
    // visitor's reaches Cloudflare — the B0.4 block below holds the wording.
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

// BACKLOG B0.4 (decision 3), measured 2026-10-26. Since 2026-10-07 every API
// call goes through the Cloudflare front door (api.myweli.com → a Worker →
// Cloud Run): 60 of 60 Cloud Run request logs sampled carried a Cloudflare
// address as `remoteIp`. So « Google Cloud enregistre … votre adresse IP » had
// become false — the visitor's address reaches Cloudflare, and our server reads
// it only to key the sign-in limiter, as a hash, pruned within two days.
describe('B0.4 — the policy says what the front door changed', () => {
  const policy = () => {
    const { container } = render(<ConfidentialitePage />);
    return (container.textContent ?? '').replace(/\s+/g, ' ');
  };
  const section = (title: RegExp) => {
    const { container } = render(<ConfidentialitePage />);
    const h = [...container.querySelectorAll('h2')].find((e) =>
      title.test(e.textContent ?? ''),
    );
    let text = '';
    let n = h?.nextElementSibling;
    while (n && n.tagName !== 'H2') {
      text += ` ${n.textContent ?? ''}`;
      n = n.nextElementSibling;
    }
    return text.replace(/\s+/g, ' ');
  };

  it('every API call passes through Cloudflare, which receives the IP', () => {
    const text = section(/journaux techniques/i);
    expect(text).toMatch(/Chaque appel à notre API[^.]*Cloudflare/);
    expect(text).toMatch(/Cloudflare, qui reçoit votre adresse IP/);
  });

  it('no longer says Google Cloud logs the visitor’s IP — it logs Cloudflare’s', () => {
    const text = section(/journaux techniques/i);
    expect(text).not.toMatch(/Google Cloud, enregistre[^.]*votre adresse IP/);
    expect(text).toMatch(/celle de Cloudflare, pas la vôtre/);
    expect(text).toMatch(/30 jours/);
  });

  it('the sign-in limiter keeps a hash, never the address, for two days at most', () => {
    const text = section(/journaux techniques/i);
    expect(text).toMatch(/empreinte, jamais l’adresse en clair/);
    expect(text).toMatch(/deux jours/);
  });

  it('names Cloudflare among the recipients, with its two roles', () => {
    expect(section(/qui d’autre les reçoit/i)).toMatch(
      /Cloudflare \(le passage de chaque appel à notre API, et le stockage des fichiers\)/,
    );
  });

  it('says the processors protect data at least as well as this page (5.1.1(i))', () => {
    expect(section(/qui d’autre les reçoit/i)).toMatch(
      /une protection au moins équivalente à celle que décrit cette page/,
    );
  });

  it('gives each app its own export path, as the apps label it', () => {
    const text = section(/vos droits/i);
    expect(text).toMatch(/MyWeli, depuis Profil → Exporter mes données/);
    expect(text).toMatch(
      /MyWeli Pro, le propriétaire du salon depuis Profil → Mes données/,
    );
  });

  it('dates the Google-script correction instead of pointing at the page date', () => {
    // The page date moved on 2026-08-22 and again since: « la date en haut de
    // cette page est celle de cette correction » stopped being true then.
    const text = policy();
    expect(text).not.toMatch(
      /la date en haut de cette page est celle de cette correction/,
    );
    expect(text).toMatch(/le 21 août 2026/);
  });
});

// JSX drops a line break that stands between text and an element: `sont`
// ⏎ `<strong>désactivées</strong>` renders « sontdésactivées ». The rendered
// policy read that way in four places — seen on the page, not in a test. The
// scan holds every legal page; the phrases hold the four that were glued.
describe('no word is glued to its neighbour by a JSX line break', () => {
  const PAGE_FILES = [
    'app/politique-confidentialite/page.tsx',
    'app/cgu/page.tsx',
    'app/mentions-legales/page.tsx',
    'app/suppression-compte/page.tsx',
    // B0.19: not a legal route, but the same shell and the same JSX habit.
    'app/pro/suppression-compte/page.tsx',
  ];

  it('no text line runs into an inline element on the next line, or back', () => {
    const glued: string[] = [];
    for (const file of PAGE_FILES) {
      const lines = readFileSync(join(__dirname, '..', file), 'utf8').split('\n');
      for (let i = 0; i < lines.length - 1; i++) {
        const a = lines[i].trimEnd();
        const b = lines[i + 1].trimStart();
        const textLine = !/^\s*(\/\/|<|\{|\})/.test(a);
        if (textLine && /[\w’.;:,»)]$/.test(a) && /^<(strong|A|em|a)\b/.test(b)) {
          glued.push(`${file}:${i + 1}`);
        }
        if (/<\/(strong|A|em|a)>$/.test(a) && /^[\wÀ-ÿ«(]/.test(b)) {
          glued.push(`${file}:${i + 1}`);
        }
      }
    }
    expect(glued).toEqual([]);
  });

  it('the policy reads the four that were glued as words', () => {
    const { container } = render(<ConfidentialitePage />);
    const text = container.textContent ?? '';
    for (const phrase of [
      'sont désactivées',
      'aujourd’hui. L’envoi',
      'sera Termii',
      'sont inaccessibles',
    ]) {
      expect(text).toContain(phrase);
    }
  });
});

// docs/design/backend-integrity-batch6.md §2.3 (B6.3, decision 17): what
// happens to a deleted owner's salon is said where a person looks for it.
describe('a deleted salon owner: the salon keeps its name, loses its numbers', () => {
  for (const [name, Page] of [
    ['the privacy policy', ConfidentialitePage],
    ['« Supprimer votre compte »', SuppressionPage],
  ] as const) {
    it(`${name} says so`, () => {
      const { container } = render(<Page />);
      const text = (container.textContent ?? '').replace(/\s+/g, ' ');
      expect(text).toMatch(/nom et son historique/);
      expect(text).toMatch(
        /numéros de téléphone, WhatsApp et Mobile Money et son adresse sont effacés/,
      );
    });
  }
});

// B0.23 (docs/design/web-privacy-pro-deletion.md, decision 143): the policy
// tells a Pro the truth about deletion. It sent Pros to the client « Mon compte »
// on the web, said nothing of a deleted owner's salon, its photos or the team's
// log, and called /suppression-compte an itemised list. The eight sentences are
// the owner's, word for word; these pins hold the ones a later edit could undo.
//
// Each section is read from its h2 to the next one, because `section()` in the
// B0.4 block joins every sibling up to the next h2: a check written as « not
// followed by a full stop » must be unanchored, or it would pass on a page that
// still sends Pros to « Mon compte ».
describe('B0.23 — the policy tells a Pro the truth about deletion', () => {
  const nodesOf = (container: HTMLElement, title: RegExp): Element[] => {
    const h = [...container.querySelectorAll('h2')].find((e) =>
      title.test(e.textContent ?? ''),
    );
    expect(h, `the « ${title.source} » heading`).toBeTruthy();
    const out: Element[] = [];
    for (let n = h!.nextElementSibling; n && n.tagName !== 'H2'; n = n.nextElementSibling) {
      out.push(n);
    }
    return out;
  };
  const flat = (nodes: Element[]) =>
    nodes
      .map((n) => n.textContent ?? '')
      .join(' ')
      .replace(/\s+/g, ' ');
  const sectionText = (title: RegExp) => {
    const { container } = render(<ConfidentialitePage />);
    return flat(nodesOf(container, title));
  };

  it('« Vos droits » sends a Pro to Profil → Compte, not to the client « Mon compte »', () => {
    const text = sectionText(/vos droits/i);
    expect(text).toContain('Mon compte pour un compte client');
    expect(text).toContain(
      'Profil → Compte une fois connecté avec votre compte professionnel',
    );
    expect(text).toContain('l’export y est réservé au propriétaire du salon');
    expect(text).not.toMatch(/sur le web, depuis Mon compte\./);
  });

  it('« Vos droits » sends a locked-out person to « Aide & Support » (R2 (b))', () => {
    const { container } = render(<ConfidentialitePage />);
    const nodes = nodesOf(container, /vos droits/i);
    const text = flat(nodes);
    expect(text).toContain('nous vous répondrons pour vérifier');
    // Decision 145: the check comes from the account's own address, and the
    // confirmation only after it — never promised to someone who lost it.
    expect(text).toContain(
      'pour vérifier, depuis l’adresse e-mail de votre compte, qu’il s’agit bien de votre compte',
    );
    expect(text).toContain(
      'cette vérification faite, nous confirmerons sa suppression',
    );
    expect(text).not.toContain('de votre compte et confirmer sa suppression');
    expect(text).toContain(
      'aux mêmes conditions que si vous la faisiez vous-même',
    );
    // A link to the page, never the address: printing it widens the page at
    // 200 % text (WEB-SYSTEM §15 row 38).
    const support = nodes.flatMap((n) => [...n.querySelectorAll('a')]).filter(
      (a) => a.getAttribute('href') === '/support',
    );
    expect(support.map((a) => a.textContent)).toEqual(['Aide & Support']);
    // « sans nous écrire » stays: R2 (b) adds a path, it does not take one away.
    expect(text).toContain('sans nous écrire');
  });

  it('« Vos droits » no longer calls /suppression-compte an itemised list', () => {
    const text = sectionText(/vos droits/i);
    expect(text).not.toMatch(/poste par poste/);
    expect(text).toContain('décrit en détail ce qui est supprimé');
  });

  it('the Pro paragraph names the documents, the replacement and a deleted owner’s salon', () => {
    const { container } = render(<ConfidentialitePage />);
    const p = [...container.querySelectorAll('p')].find((e) =>
      (e.textContent ?? '').startsWith('Si vous êtes professionnel'),
    );
    expect(p, 'the « Si vous êtes professionnel » paragraph').toBeTruthy();
    const text = (p!.textContent ?? '').replace(/\s+/g, ' ');
    for (const phrase of [
      'des pièces d’identité et d’immatriculation, une photo de votre visage et un justificatif d’adresse',
      'un document que vous remplacez l’est dès son remplacement',
      'Cet effacement est fait au mieux',
      'ou lorsque vous remplacez ou renvoyez un document',
      'chaque salon dont vous êtes propriétaire est retiré du public',
      'ainsi que son point sur la carte',
    ]) {
      expect(text).toContain(phrase);
    }
  });

  it('« Conservation » names what a deleted Pro leaves behind, with no limit set (options A and B)', () => {
    const text = sectionText(/conservation/i);
    for (const phrase of [
      // the salon, kept and hidden (decision 138)
      'chaque salon dont vous étiez propriétaire reste dans notre base, caché du public',
      'ainsi que sa commune et sa ville',
      'Les membres de son équipe y gardent accès',
      // its photos (Q12 (d))
      'restent accessibles à leur adresse existante',
      // option A
      'Le journal des décisions de notre équipe',
      'avec le motif écrit d’un refus',
      'Restent aussi, jusqu’à ce qu’ils soient retirés',
      'une invitation qu’un autre salon vous avait envoyée',
      'votre fiche de collaborateur dans l’équipe d’un salon dont vous étiez seulement membre',
      // sentence 7, and option B at its end
      'recherches faites dans sa liste de clients',
      'il n’est pas effacé à la suppression d’un compte',
      'Le texte recherché peut être le nom ou le numéro d’un client',
    ]) {
      expect(text).toContain(phrase);
    }
  });

  it('« Conservation » says no limit is set of the salon and of the team log, each in its own paragraph (decision 138)', () => {
    // Pinned per paragraph: the phrase is written twice, so one check against
    // the whole section stayed green when either copy was deleted.
    const { container } = render(<ConfidentialitePage />);
    const paragraphs = nodesOf(container, /conservation/i).map((n) =>
      (n.textContent ?? '').replace(/\s+/g, ' ').trim(),
    );
    for (const opening of [
      'Si vous supprimez un compte professionnel',
      'Le journal des actions de l’équipe d’un salon',
    ]) {
      const p = paragraphs.find((t) => t.startsWith(opening));
      expect(p, `the « ${opening} » paragraph`).toBeTruthy();
      expect(p).toContain('Aucune durée de conservation n’est fixée à ce jour');
    }
  });

  it('the shared date moved with the text (a floor, so the merge day can only be later)', () => {
    // B0.23 is a substantive change under legal.ts's rule. The PR sets the date
    // to its merge day; a later merge raises it, and this floor still holds.
    expect(LEGAL_UPDATED_AT.iso >= '2026-11-14').toBe(true);
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
    // **Derived from the constant, not from today's wording.** This used to
    // pin the literal « Registre du Commerce ». That phrase leaves the constant
    // at registration, so the assertion would stop discriminating: still green,
    // but no longer proving anything about a hard-coded copy. Slicing the
    // constant keeps it honest in whatever world we are in.
    // Whitespace-normalised on both sides: a hard-coded copy in JSX is
    // Prettier-wrapped across lines, so a raw `toContain` of a 40-char slice
    // can never match one — the control replaced a stale literal with a
    // vacuous check.
    const flat = (t: string) => t.replace(/\s+/g, ' ');
    expect(flat(src)).not.toContain(flat(COMPANY.registration).slice(0, 40));
  });

  it('names all three hosts, because mentions légales must name the host', () => {
    // **`COMPANY.hosts.length > 0`** was the same tautology this file records
    // against the vendor table above: true of any non-empty list, including a
    // wrong one. Where MyWeli runs is a disclosure, so moving it has to touch
    // this line and be reviewed.
    expect([...COMPANY.hosts]).toEqual([
      'Google Cloud — serveurs applicatifs et base de données, Paris (France)',
      'Vercel Inc. — site web, États-Unis',
      'Cloudflare Inc. — stockage des fichiers (R2) et passage des appels à l’API',
    ]);
    const { container } = render(<MentionsPage />);
    for (const h of COMPANY.hosts) {
      expect(container.textContent ?? '').toContain(h);
    }
  });

  it('the slugs mobile hard-codes are the slugs that exist', () => {
    // `AppConfig.privacyUrl` and friends build these paths into the app binary,
    // and no mobile test can reach the web — so this list and
    // `mobile/lib/core/config/app_config.dart` are one contract reviewed in one
    // PR, and this is the web half of it. `store-linked-pages.test.tsx` reads the
    // Dart half against the same paths. Change a slug here and you must change it
    // there, in the same commit.
    expect(LEGAL_ROUTES.map((r) => r.slug).sort()).toEqual([
      '/cgu',
      '/mentions-legales',
      '/politique-confidentialite',
      '/suppression-compte',
    ]);
  });
});

// B0.19 (docs/design/web-pro-account-deletion.md §10 #11): /pro/suppression-compte.
//
// **Spacing, as the five write it.** `&nbsp;` before « ; : ? ! » and inside « »
// (SYSTEM §17.1). A plain space there lets the browser break the line before a
// colon or leave a guillemet alone at a line's end. Read from the page's copy —
// its JSX text and its string literals, through the TypeScript AST, so code
// (`a ? b : c`, `{ key: value }`) is never mistaken for French — and again on
// the rendered page, where a JSX line break shows up as the plain space it becomes.
//
// **The pins hold the choices the owner made** (decisions 137–139 and the
// 2026-11-13 reviews): each is a sentence a well-meant edit could soften.
describe('B0.19 — /pro/suppression-compte: spacing and the pinned choices', () => {
  const FILE = 'app/pro/suppression-compte/page.tsx';

  /// The copy of a TSX file: JSX text (entities decoded) and string literals,
  /// imports and attribute values left out, each with its line.
  const copyOf = (file: string) => {
    const src = readFileSync(join(__dirname, '..', file), 'utf8');
    const sf = ts.createSourceFile(file, src, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
    const out: { line: number; text: string }[] = [];
    const add = (n: ts.Node, text: string) =>
      out.push({ line: sf.getLineAndCharacterOfPosition(n.getStart(sf)).line + 1, text });
    const visit = (n: ts.Node) => {
      if (ts.isJsxText(n)) {
        add(n, n.getFullText(sf).replace(/&nbsp;/g, '\u00a0').replace(/&amp;/g, '&'));
      } else if (
        (ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n) || ts.isTemplateLiteralToken(n)) &&
        !ts.isImportDeclaration(n.parent) &&
        !ts.isJsxAttribute(n.parent)
      ) {
        add(n, n.text);
      }
      ts.forEachChild(n, visit);
    };
    visit(sf);
    return out;
  };

  /// What breaks the five's convention in one piece of copy.
  const badSpacing = (text: string) => [
    ...(/ [;:?!]/.test(text) ? ['a plain space before ; : ? !'] : []),
    ...(/\n[ \t]*[;:?!]/.test(text) ? ['a line break before ; : ? !'] : []),
    ...(/«[ \n]/.test(text) ? ['a plain space or a line break after «'] : []),
    ...(/[ \n]»/.test(text) ? ['a plain space or a line break before »'] : []),
  ];

  it('the scan reads the copy, and only the copy', () => {
    const copy = copyOf(FILE).map((c) => c.text).join(' ');
    expect(copy).toContain('Supprimer définitivement');
    expect(copy).toContain('Puis-je supprimer mon compte MyWeli Pro');
    expect(copy).not.toContain('../../../components/legal/LegalPage');
    // The rule catches each of its four shapes.
    expect(badSpacing('compte :')).toHaveLength(1);
    expect(badSpacing('lisez\n:')).toHaveLength(1);
    expect(badSpacing('« Supprimer')).toHaveLength(1);
    expect(badSpacing('compte. »')).toHaveLength(1);
    expect(badSpacing('compte\u00a0: «\u00a0Supprimer\u00a0»')).toEqual([]);
  });

  it('the page’s copy: no plain space before ; : ? ! and none inside « »', () => {
    const found = copyOf(FILE).flatMap((c) => badSpacing(c.text).map((why) => `${FILE}:${c.line} ${why}`));
    expect(found).toEqual([]);
  });

  it('the rendered page: every ; : ? ! follows a no-break space, and « » hold one', () => {
    const { container } = render(<ProSuppressionPage />);
    // The shell's own « Dernière mise à jour : » line is the four legal pages'
    // too, and they must render byte-identical: the scan starts after it.
    const date = [...container.querySelectorAll('main > p')].find((p) =>
      (p.textContent ?? '').startsWith('Dernière mise à jour'),
    );
    expect(date, 'the date line').toBeTruthy();
    let text = '';
    for (let n = date!.nextElementSibling; n; n = n.nextElementSibling) text += `\n${n.textContent ?? ''}`;
    expect(text.length).toBeGreaterThan(1000);
    const bad = [...text.matchAll(/(.{0,24})(?:[^\u00a0\n]([;:?!])|«[^\u00a0]|[^\u00a0]»)/g)].map((m) => m[0]);
    expect(bad).toEqual([]);
  });

  const page = () => {
    const { container } = render(<ProSuppressionPage />);
    return (container.textContent ?? '').replace(/[ \t\n\r]+/g, ' ');
  };
  const section = (title: RegExp) => {
    const { container } = render(<ProSuppressionPage />);
    const h = [...container.querySelectorAll('h2')].find((e) => title.test(e.textContent ?? ''));
    expect(h, `the « ${title.source} » heading`).toBeTruthy();
    let out = '';
    for (let n = h!.nextElementSibling; n && n.tagName !== 'H2' && !n.querySelector('h2'); n = n.nextElementSibling) {
      out += ` ${n.textContent ?? ''}`;
    }
    return out.replace(/[ \t\n\r]+/g, ' ');
  };

  it('the salon: hidden in minutes, its address and its pin erased, its team kept in (decision 137)', () => {
    const text = section(/^Ce que devient votre salon$/);
    expect(text).toContain('est retiré du public en quelques minutes');
    expect(text).toContain(
      'ses numéros de téléphone, WhatsApp et Mobile Money, son adresse et son point sur la carte sont effacés',
    );
    expect(text).toContain(
      'Les autres membres de son équipe gardent leur accès au salon dans MyWeli Pro, selon leur rôle.',
    );
  });

  it('what is kept: the history with its description, the commune and the city, no limit set (decision 138)', () => {
    const text = section(/^Ce qui est conservé/);
    expect(text).toContain('son nom, sa description, ses prestations');
    expect(text).toContain(
      'Aucune durée de conservation n’est fixée à ce jour\u00a0: il n’est pas effacé automatiquement',
    );
    expect(text).toContain('sa commune et sa ville restent avec lui, cachées du public');
  });

  it('the photos: off the public pages, still at their address, still seen by the team (Q12 (d))', () => {
    const text = section(/^Ce qui est conservé/);
    expect(text).toContain('ne sont plus affichées au public sur MyWeli');
    expect(text).toContain('les membres de l’équipe les voient toujours dans MyWeli Pro');
    expect(text).toContain('restent accessibles à leur adresse existante pour qui la connaît');
  });

  it('the documents: (a)’s widened caveat ships, (b)’s never does (§11’s rule)', () => {
    const text = section(/^Ce qui est supprimé$/);
    expect(text).toContain(
      'si notre stockage est indisponible lors de la suppression, ou lorsque vous avez remplacé ou renvoyé un document',
    );
    expect(text).not.toContain('enregistrés sur votre compte au moment de la suppression');
    expect(text).not.toContain('n’est pas effacé');
    expect(page()).not.toContain('enregistrés sur votre compte au moment de la suppression');
  });

  it('the logs and the copies that stay: the team’s actions, our decisions, the e-mails, the profile, the invitations', () => {
    const text = section(/^Ce qui est conservé/);
    for (const phrase of [
      'les recherches faites dans Clients, sans votre nom ni votre adresse e-mail',
      'vérification d’identité acceptée ou refusée, avec le motif écrit d’un refus',
      'les e-mails reçus par notre équipe lorsqu’un salon validé a changé d’adresse, de téléphone ou de point sur la carte restent dans notre messagerie',
      'votre fiche de collaborateur dans l’équipe d’un salon dont vous êtes seulement membre (nom, photo) appartient à ce salon et reste affichée tant qu’il ne la retire pas',
      'les invitations qu’un autre salon vous avait envoyées et que vous n’aviez pas acceptées restent dans sa liste, avec votre adresse e-mail',
    ]) {
      expect(text).toContain(phrase);
    }
  });

  it('the app’s path names Accueil’s icon; the e-mail path follows the screen’s order', () => {
    expect(section(/^Dans l’application MyWeli Pro$/)).toContain('l’icône de compte en haut de l’Accueil, ou l’onglet Profil');
    expect(section(/^Vous ne pouvez plus vous connecter/)).toContain(
      'dans Votre e-mail, puis choisissez Continuer avec e-mail',
    );
  });

  it('the two support paths, and the first FAQ’s « Oui, si… » (decision 139)', () => {
    const cannot = section(/^Vous ne pouvez plus vous connecter/);
    expect(cannot).toContain(
      'Si vous n’avez plus accès à cette adresse, écrivez-nous à support@myweli.com avec le nom de votre salon\u00a0: nous vous répondrons pour vérifier qu’il s’agit bien de votre compte.',
    );
    const revoked = section(/^Votre accès à l’équipe d’un salon a été retiré/);
    expect(revoked).toContain('(ou ne vous montre que vos invitations)');
    expect(revoked).toContain(
      'Écrivez-nous à support@myweli.com depuis l’adresse e-mail de votre compte\u00a0: nous vous répondrons pour confirmer la suppression.',
    );
    expect(page()).toContain('Oui, si vous pouvez vous connecter à l’Espace Pro\u00a0:');
  });
});

/// docs/design/web-pro-account-deletion.md §12, R3: `llms.txt` said « no crash
/// reporting » while the policy discloses Sentry — the stale denial the block
/// « the privacy policy does not deny what we actually ship » exists for, in
/// the file AI engines read instead of the page.
describe('llms.txt does not deny what we ship either', () => {
  const llms = readFileSync(join(__dirname, '..', 'public/llms.txt'), 'utf8').replace(/\s+/g, ' ');
  const deps = Object.keys(pkg.dependencies ?? {});

  it('Sentry ships, so llms.txt says error reports go to it, and never « no crash reporting »', () => {
    expect(deps.some((d) => d.includes('sentry'))).toBe(true);
    expect(llms).not.toMatch(/no crash report/i);
    expect(llms).toMatch(/error reports?[^.]*Sentry/i);
  });

  it('still denies analytics and advertising, as the policy does', () => {
    expect(llms).toMatch(/no analytics/i);
    expect(llms).toMatch(/no advertising SDK/i);
  });
});
