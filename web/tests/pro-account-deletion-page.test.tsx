import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { cleanup, render } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import Page, { metadata } from '../app/pro/suppression-compte/page';
import { LEGAL_ROUTES } from '../lib/legal';
import { PRO_ACCOUNT_DELETION } from '../lib/proAccountDeletion';
import { signInMethods } from '../lib/pro/signInMethods';
import { isStoreLinkedPage, STORE_LINKED_PATHS } from '../lib/storeLinkedPages';

/// `/pro/suppression-compte` (B0.19, docs/design/web-pro-account-deletion.md
/// §10 #1–#10 and #19). The page is a published representation to salons and
/// to Google Play: each test below ties a sentence to the code that makes it
/// true, and each was watched red by the mutation its comment names.

const WEB = join(__dirname, '..');
const REPO = join(WEB, '..');
const read = (rel: string) => readFileSync(join(REPO, rel), 'utf8');

afterEach(() => {
  cleanup();
  vi.unstubAllEnvs();
});

/// Whitespace folded as a browser lays it out — but never U+00A0, which the
/// page writes before « ; : ? ! » on purpose (JavaScript's `\s` would fold it).
const norm = (s: string) => s.replace(/[ \t\n\r]+/g, ' ').trim();
const text = (el: Element | null | undefined) => norm(el?.textContent ?? '');
const page = () => render(<Page />).container;
const h2s = (c: HTMLElement) => [...c.querySelectorAll('h2')];
/// The text from an h2 to the next one: the FAQ h2s sit inside a `<div>` each,
/// so the walk climbs to the h2's own block before reading its siblings.
const section = (c: HTMLElement, title: RegExp) => {
  const h = h2s(c).find((e) => title.test(e.textContent ?? ''));
  expect(h, `the « ${title.source} » heading`).toBeTruthy();
  let out = '';
  for (let n = h!.nextElementSibling; n && n.tagName !== 'H2' && !n.querySelector('h2'); n = n.nextElementSibling) {
    out += ` ${n.textContent ?? ''}`;
  }
  return norm(out);
};

/// Source as code, comments out: a label in a comment is not on any screen.
const tsCode = (src: string) => src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
/// Dart as code: comments out, and adjacent literals joined
/// (`'… avant de ' 'supprimer …'` is one string on the screen).
const dartCode = (src: string) =>
  src
    .replace(/^\s*\/\/.*$/gm, '')
    .replace(/'\s*\n\s*'/g, '')
    .replace(/'\s+'/g, '');

describe('#1 — one h1, the route record’s', () => {
  it('reads « Supprimer votre compte MyWeli Pro »', () => {
    const c = page();
    const h1 = [...c.querySelectorAll('h1')];
    expect(h1).toHaveLength(1);
    expect(text(h1[0])).toBe(PRO_ACCOUNT_DELETION.h1);
    expect(PRO_ACCOUNT_DELETION.h1).toBe('Supprimer votre compte MyWeli Pro');
  });
});

describe('#2 — it names the app exactly as its Play listing does', () => {
  it('the « Nom de l’app » of play-store-forms §1, in the lead, before the first h2', () => {
    const listing = /\*\*Nom de l'app\*\* : `([^`]+)`/.exec(read('docs/design/play-store-forms.md'))?.[1];
    expect(listing, 'the listing name was not found in play-store-forms.md').toBeTruthy();
    expect(listing).toBe('MyWeli Pro — Gestion de salon');
    const order = [...page().querySelectorAll('p, h2')];
    const lead = order.findIndex((e) => e.tagName === 'P' && (e.textContent ?? '').includes(listing!));
    expect(lead, 'no paragraph names the listing').toBeGreaterThanOrEqual(0);
    expect(lead).toBeLessThan(order.findIndex((e) => e.tagName === 'H2'));
  });
});

/// #3 — every label the page quotes exists, as written, on the screen it names
/// (§5.2). « En cours de validation » is the website's word only (none in the app).
const LABELS: [label: string, web: string | null, app: string | null][] = [
  ['Continuer avec Google', 'web/components/auth/GoogleSignInButton.tsx', 'mobile/lib/screens/provider/auth/pro_login_screen.dart'],
  ['Continuer avec Apple', 'web/components/auth/AppleSignInButton.tsx', 'mobile/lib/screens/provider/auth/pro_login_screen.dart'],
  ['Continuer avec e-mail', 'web/components/pro/ProLoginOptions.tsx', 'mobile/lib/screens/provider/auth/pro_login_screen.dart'],
  ['Votre e-mail', 'web/components/pro/ProLoginOptions.tsx', 'mobile/lib/screens/provider/auth/pro_login_screen.dart'],
  ['Espace Pro', 'web/app/pro/connexion/page.tsx', null],
  ['Accueil', null, 'mobile/lib/screens/provider/dashboard/dashboard_screen.dart'],
  ['Profil', 'web/lib/pro/nav.ts', 'mobile/lib/screens/provider/staff/staff_home_screen.dart'],
  ['Compte', 'web/components/pro/CompteDangerSection.tsx', null],
  ['Supprimer mon compte', 'web/components/pro/CompteDangerSection.tsx', 'mobile/lib/screens/provider/profile/pro_profile_screen.dart'],
  ['SUPPRIMER', 'web/components/pro/CompteDangerSection.tsx', 'mobile/lib/screens/provider/profile/pro_profile_screen.dart'],
  ['Supprimer définitivement', 'web/components/pro/CompteDangerSection.tsx', 'mobile/lib/screens/provider/profile/pro_profile_screen.dart'],
  ['Pensez à exporter vos données avant', 'web/components/pro/CompteDangerSection.tsx', 'mobile/lib/screens/provider/profile/pro_profile_screen.dart'],
  ['Mes données', null, 'mobile/lib/screens/provider/profile/pro_profile_screen.dart'],
  ['Exporter (JSON)', 'web/components/pro/CompteDangerSection.tsx', null],
  ['En cours de validation', 'web/lib/pro/salon-validation.ts', null],
  ['Clients', 'web/lib/pro/nav.ts', null],
];

describe('#3 — each quoted label is the one on screen', () => {
  // Both social buttons drawn, as on a production build that has both ids
  // (#19 covers the builds that do not).
  beforeEach(() => {
    vi.stubEnv('NEXT_PUBLIC_GOOGLE_CLIENT_ID', 'g.apps.googleusercontent.com');
    vi.stubEnv('NEXT_PUBLIC_APPLE_CLIENT_ID', 'com.myweli.signin');
  });
  for (const [label, web, app] of LABELS) {
    it(label, () => {
      expect(text(page())).toContain(label);
      if (web) expect(tsCode(read(web)), `${web} no longer shows « ${label} »`).toContain(label);
      if (app) expect(dartCode(read(app)), `${app} no longer shows « ${label} »`).toContain(label);
    });
  }

  it('the app’s Profil: Accueil’s account icon is labelled « Profil », staff have the tab', () => {
    const dash = dartCode(read('mobile/lib/screens/provider/dashboard/dashboard_screen.dart'));
    expect(dash).toContain("ScreenTitle('Accueil')");
    expect(dash).toContain("tooltip: 'Profil'");
    expect(dartCode(read('mobile/lib/screens/provider/staff/staff_home_screen.dart'))).toContain("label: 'Profil'");
  });

  it('« Tapez SUPPRIMER » and « Code à 6 chiffres » on both sides', () => {
    expect(tsCode(read('web/components/pro/CompteDangerSection.tsx'))).toContain('Tapez SUPPRIMER pour confirmer');
    expect(dartCode(read('mobile/lib/widgets/common/confirm_dialog.dart'))).toContain("'Tapez ${widget.confirmWord} pour confirmer'");
    expect(dartCode(read('mobile/lib/screens/provider/profile/pro_profile_screen.dart'))).toContain("confirmWord: 'SUPPRIMER'");
    expect(tsCode(read('web/components/pro/ProLoginOptions.tsx'))).toContain('Code à 6 chiffres');
    expect(dartCode(read('mobile/lib/screens/provider/auth/pro_login_screen.dart'))).toContain('Code à 6 chiffres');
    expect(text(page())).toContain('un code à 6 chiffres');
  });
});

describe('#4 — the refusal sentence is the one the server’s refusal shows', () => {
  it('the quote in the callout equals the website’s and the app’s string', () => {
    const c = page();
    const quoted = /vous lisez\u00a0: «\u00a0([^»]+?)\u00a0»/.exec(c.textContent ?? '')?.[1];
    expect(quoted, 'the callout no longer quotes the refusal').toBeTruthy();
    const web = /case 'future_bookings':\s*return '([^']+)';/.exec(tsCode(read('web/components/pro/CompteDangerSection.tsx')))?.[1];
    const app = /'future_bookings' =>\s*'([^']+)',/.exec(dartCode(read('mobile/lib/screens/provider/profile/pro_profile_screen.dart')))?.[1];
    expect(web).toBe(quoted);
    expect(app).toBe(quoted);
  });
});

describe('#5 — the links', () => {
  it('the CTA is a plain <a> to /pro/connexion?suite=profil', () => {
    const c = page();
    const cta = [...c.querySelectorAll('a')].find((a) => text(a) === 'Se connecter à l’Espace Pro');
    expect(cta, 'the CTA').toBeTruthy();
    expect(cta!.getAttribute('href')).toBe('/pro/connexion?suite=profil');
  });

  it('the client page and the policy are linked; Profil itself never is', () => {
    const hrefs = [...page().querySelectorAll('a[href]')].map((a) => a.getAttribute('href'));
    expect(hrefs).toContain('/suppression-compte');
    expect(hrefs).toContain('/politique-confidentialite');
    // Signed out, /pro/profil bounces to the sign-in and lands on /pro: the
    // CTA's ?suite=profil is the only way the sign-in comes back to Profil.
    expect(hrefs.filter((h) => h?.startsWith('/pro/profil'))).toEqual([]);
  });

  it('every support link is the published address with no subject', () => {
    const mail = [...page().querySelectorAll('a[href^="mailto:"]')];
    expect(mail.map((a) => a.getAttribute('href'))).toEqual([
      'mailto:support@myweli.com',
      'mailto:support@myweli.com',
      'mailto:support@myweli.com',
    ]);
    for (const a of mail) expect(text(a)).toBe('support@myweli.com');
  });
});

describe('#6 — outside the five, outside the legal footer', () => {
  it('not a store-linked page, not a legal route, in any spelling', () => {
    expect(STORE_LINKED_PATHS as readonly string[]).not.toContain(PRO_ACCOUNT_DELETION.slug);
    expect(LEGAL_ROUTES.map((r) => r.slug)).not.toContain(PRO_ACCOUNT_DELETION.slug);
    for (const spelling of [
      '/pro/suppression-compte',
      '/pro/suppression-compte/',
      '/pro%2Fsuppression-compte',
      '/pro/%73uppression-compte',
      '//pro/suppression-compte?x=1#y',
    ]) {
      expect(isStoreLinkedPage(spelling), spelling).toBe(false);
    }
  });
});

describe('#7 — metadata, and a date of its own', () => {
  it('canonical, OG and an indexable robots (decision 140)', () => {
    expect(metadata.title).toBe('Supprimer votre compte MyWeli Pro');
    expect(metadata.description).toBe(PRO_ACCOUNT_DELETION.description);
    expect(metadata.alternates?.canonical).toBe('/pro/suppression-compte');
    expect((metadata.openGraph as { url?: string } | undefined)?.url).toMatch(/\/pro\/suppression-compte$/);
    const robots = metadata.robots as { index?: boolean; follow?: boolean } | undefined;
    expect(robots?.index, 'every other /pro page is noindex; this one is the exception').toBe(true);
    expect(robots?.follow).toBe(true);
  });

  const MONTHS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  const isoOfLabel = (label: string) => {
    const m = /^(\d{1,2}) (\S+) (\d{4})$/.exec(label);
    if (!m) return null;
    const month = MONTHS.indexOf(m[2]) + 1;
    return `${m[3]}-${String(month).padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  };
  const shown = (c: HTMLElement) => {
    const line = [...c.querySelectorAll('p')].map(text).find((t) => t.startsWith('Dernière mise à jour'));
    return line?.replace(/^Dernière mise à jour : /, '') ?? '';
  };
  const ldOf = (c: HTMLElement, type: string) =>
    [...c.querySelectorAll('script[type="application/ld+json"]')]
      .map((s) => JSON.parse(s.textContent ?? '{}'))
      .find((d) => d['@type'] === type);

  it('(i) the JSON-LD dateModified is the date the page shows', () => {
    const c = page();
    const label = shown(c);
    expect(isoOfLabel(label), `« ${label} » is not a French date`).not.toBeNull();
    expect(ldOf(c, 'WebPage').dateModified).toBe(isoOfLabel(label));
  });

  it('(ii) neither the page nor the shell it calls reads LEGAL_UPDATED_AT', () => {
    expect(tsCode(read('web/app/pro/suppression-compte/page.tsx'))).not.toContain('LEGAL_UPDATED_AT');
    expect(read('web/lib/proAccountDeletion.ts').replace(/^\s*\/\/.*$/gm, '')).not.toContain('LEGAL_UPDATED_AT');
    const shell = read('web/components/legal/LegalPage.tsx');
    const body = shell.slice(shell.indexOf('export function DocumentPage('), shell.indexOf('/// A section heading.'));
    expect(body.length, 'DocumentPage was not found').toBeGreaterThan(100);
    expect(body).not.toContain('LEGAL_UPDATED_AT');
  });

  it('(iii) moving the shared legal date does not move this page’s', async () => {
    vi.resetModules();
    vi.doMock('../lib/legal', async (importOriginal) => ({
      ...(await importOriginal<typeof import('../lib/legal')>()),
      LEGAL_UPDATED_AT: { iso: '1999-01-02', label: '2 janvier 1999' },
    }));
    try {
      const { default: Moved } = await import('../app/pro/suppression-compte/page');
      const c = render(<Moved />).container;
      expect(shown(c)).not.toBe('2 janvier 1999');
      expect(ldOf(c, 'WebPage').dateModified).not.toBe('1999-01-02');
      // The control: the mock reached the shell, or this proves nothing.
      const { default: Cgu } = await import('../app/cgu/page');
      expect(text(render(<Cgu />).container)).toContain('2 janvier 1999');
    } finally {
      vi.doUnmock('../lib/legal');
      vi.resetModules();
    }
  });

  it('JSON-LD: WebPage, BreadcrumbList, and an FAQPage made of the FAQ h2s', () => {
    const c = page();
    expect(ldOf(c, 'BreadcrumbList').itemListElement.map((i: { name: string }) => i.name)).toEqual([
      'Accueil',
      PRO_ACCOUNT_DELETION.h1,
    ]);
    const faq = ldOf(c, 'FAQPage');
    const questions = faq.mainEntity.map((q: { name: string }) => q.name);
    expect(questions).toHaveLength(2);
    const headings = h2s(c).map(text);
    for (const q of questions) expect(headings).toContain(norm(q));
    // The visible answers say what the JSON-LD says.
    for (const q of faq.mainEntity as { name: string; acceptedAnswer: { text: string } }[]) {
      const h = h2s(c).find((e) => text(e) === norm(q.name))!;
      expect(text(h.nextElementSibling)).toBe(norm(q.acceptedAnswer.text));
    }
  });
});

describe('#8 — durations: only the published log retention', () => {
  it('every « N jours » is the logging manifest’s maxRetentionDays, and there is one', () => {
    const manifest = JSON.parse(read('infra/gcp/logging-manifest.json'));
    const days = JSON.stringify(manifest).match(/"maxRetentionDays":\s*(\d+)/)?.[1];
    expect(days, 'maxRetentionDays not found').toBeTruthy();
    const figures = [...text(page()).matchAll(/(\d+)\s*jours?/g)].map((m) => m[1]);
    expect(figures.length).toBeGreaterThan(0);
    expect(new Set(figures)).toEqual(new Set([days]));
  });
});

describe('#9 — no subscription, offer, trial or price word (decision 138)', () => {
  it('none', () => {
    expect(text(page())).not.toMatch(/abonnement|offre|essai|tarif|FCFA/i);
  });
});

describe('#10 — no className in the page file', () => {
  it('the closed theme’s defence: LegalPage.tsx carries every class', () => {
    expect(tsCode(read('web/app/pro/suppression-compte/page.tsx'))).not.toMatch(/className/);
  });
});

describe('#19 — step 1 names a social button exactly when this build draws it', () => {
  /// Step 1's sentence, without its drawn number before it or the CTA below it.
  const step1 = (c: HTMLElement) => {
    // `main > ol`: the breadcrumb is an <ol> too, inside its <nav>. `Ol` draws
    // each item as the number, then the step's own `<div>`.
    const body = c.querySelector('main > ol > li > div')!.cloneNode(true) as HTMLElement;
    body.querySelectorAll('div').forEach((d) => d.remove());
    return text(body);
  };
  it.each([
    ['both', 'g.apps.googleusercontent.com', 'com.myweli.signin'],
    ['Google only', 'g.apps.googleusercontent.com', ''],
    ['Apple only', '', 'com.myweli.signin'],
    ['neither', '', ''],
  ])('%s', (_name, google, apple) => {
    vi.stubEnv('NEXT_PUBLIC_GOOGLE_CLIENT_ID', google);
    vi.stubEnv('NEXT_PUBLIC_APPLE_CLIENT_ID', apple);
    const m = signInMethods();
    const s = step1(page());
    expect(s.includes('Continuer avec Google')).toBe(Boolean(m.google));
    expect(s.includes('Continuer avec Apple')).toBe(Boolean(m.apple));
    // E-mail is unconditional on /pro/connexion, so always named.
    expect(s).toContain('Continuer avec e-mail');
    expect(s).toMatch(/^Connectez-vous à l’Espace Pro avec la même méthode que dans l’application\u00a0: /);
  });

  it('with both, the approved sentence word for word', () => {
    vi.stubEnv('NEXT_PUBLIC_GOOGLE_CLIENT_ID', 'g.apps.googleusercontent.com');
    vi.stubEnv('NEXT_PUBLIC_APPLE_CLIENT_ID', 'com.myweli.signin');
    expect(step1(page())).toMatch(
      /^Connectez-vous à l’Espace Pro avec la même méthode que dans l’application\u00a0: Continuer avec Google, Continuer avec Apple ou Continuer avec e-mail\.$/,
    );
  });
});
