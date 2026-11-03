import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ComponentType } from 'react';
import { renderToString } from 'react-dom/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

const nav = vi.hoisted(() => ({ pathname: '/' }));
vi.mock('next/navigation', () => ({
  usePathname: () => nav.pathname,
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), refresh: vi.fn(), back: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

import CguPage from '../app/cgu/page';
import MentionsPage from '../app/mentions-legales/page';
import ConfidentialitePage from '../app/politique-confidentialite/page';
import SuppressionPage from '../app/suppression-compte/page';
import SupportPage from '../app/support/page';
import { SiteChrome } from '../components/SiteChrome';
import { SiteFooter } from '../components/SiteFooter';
import { LEGAL_ROUTES } from '../lib/legal';
import { SOCIAL_PROFILES } from '../lib/social';
import { isStoreLinkedPage, STORE_LINKED_PATHS } from '../lib/storeLinkedPages';

/// The five pages the apps open carry no direct way to sign-up, the Espace pro or the
/// offers: docs/design/app-review-round-2.md §5, decision 3.
///
/// **This reads the server's render**, chrome, body and footer together, because that is
/// what a page is. `tests/e2e/store-linked-pages.spec.ts` reads the built HTML, which
/// also holds the RSC payload; this file cannot see that.

const FIVE: [path: string, Page: ComponentType][] = [
  ['/support', SupportPage],
  ['/politique-confidentialite', ConfidentialitePage],
  ['/cgu', CguPage],
  ['/mentions-legales', MentionsPage],
  ['/suppression-compte', SuppressionPage],
];
const SALON_LINKS = ['/professionnels', '/pro/inscription', '/pro/connexion'];

const serve = (pathname: string, Page?: ComponentType) => {
  nav.pathname = pathname;
  const html = renderToString(
    <>
      <SiteChrome />
      {Page ? <Page /> : null}
      <SiteFooter />
    </>,
  );
  return new DOMParser().parseFromString(html, 'text/html');
};
const hrefs = (root: ParentNode) =>
  [...root.querySelectorAll('a[href]')].map((a) => a.getAttribute('href') as string);
const toSalons = (href: string) =>
  href === '/pro' || href.startsWith('/pro/') || href.startsWith('/professionnels');

afterEach(() => {
  nav.pathname = '/';
});

describe('isStoreLinkedPage: exact, whatever the spelling', () => {
  it('holds the five the owner named, each with a page', () => {
    expect([...STORE_LINKED_PATHS].sort()).toEqual([
      '/cgu',
      '/mentions-legales',
      '/politique-confidentialite',
      '/support',
      '/suppression-compte',
    ]);
    const web = join(dirname(fileURLToPath(import.meta.url)), '..');
    for (const path of STORE_LINKED_PATHS) {
      expect(existsSync(join(web, 'app', path, 'page.tsx')), `${path} has a page`).toBe(true);
    }
  });

  it('reads every page of the list below: a new one cannot be classified and left unread', () => {
    expect(FIVE.map(([path]) => path).sort()).toEqual([...STORE_LINKED_PATHS].sort());
  });

  it.each(STORE_LINKED_PATHS.flatMap((p) => [p, `${p}/`, `${p}?utm_source=x`, `${p}/?a=b`, `${p}#top`]))(
    '%s: yes',
    (path) => {
      expect(isStoreLinkedPage(path)).toBe(true);
    },
  );

  it.each(['/%63gu', '/mentions%2Dlegales', '/%73upport/', '/%63gu?a=b'])(
    '%s: yes, the server answers it with the same page',
    (path) => {
      expect(isStoreLinkedPage(path)).toBe(true);
    },
  );

  it.each([
    '',
    '/',
    '/professionnels',
    '/pro',
    '/pro/connexion',
    '/pro/inscription',
    '/recherche',
    '/connexion',
    '/mon-compte',
    '/cgu/x',
    '/cgux',
    '/x/cgu',
    '/supports',
    '/support/x',
    '/CGU',
    '/%63gux',
    '/%2Fcgu',
    '/%zz',
    '/%E0%A4%A',
  ])('%s: no', (path) => {
    expect(isStoreLinkedPage(path)).toBe(false);
  });
});

describe.each(FIVE)('%s, as the server renders it', (path, Page) => {
  it('has no link to the salons’ pages anywhere: header, body or footer', () => {
    const page = serve(path, Page);
    expect(hrefs(page).filter(toSalons)).toEqual([]);
  });

  it('does not offer them in words either', () => {
    const text = serve(path, Page).body.textContent ?? '';
    for (const words of ['Espace pro', 'Inscrire mon salon', 'MyWeli Pro pour les salons', 'Connexion Espace']) {
      expect(text).not.toContain(words);
    }
  });

  it('still goes home, by the logo and the breadcrumb', () => {
    const page = serve(path, Page);
    expect(page.querySelector('a[aria-label="MyWeli — accueil"]')?.getAttribute('href')).toBe('/');
    expect(hrefs(page.querySelector('nav[aria-label="Fil d’Ariane"]') as Element)).toEqual(['/']);
  });

  it('keeps « Mon compte », the legal links and the social links', () => {
    const page = serve(path, Page);
    expect(hrefs(page.querySelector('header') as Element)).toContain('/mon-compte');
    const footer = hrefs(page.querySelector('footer') as Element);
    expect(footer).toEqual([...LEGAL_ROUTES.map((r) => r.slug), ...SOCIAL_PROFILES.map((s) => s.url)]);
  });

  it('names no offer, plan or price', () => {
    // A salon's own prices are in the CGU (« vos prestations, prix »), and they are not
    // ours to sell, so « prix » is not on this list. If a legal edit needs one of these
    // words, that is a decision for the owner, not a line to take out of this test.
    const text = serve(path, Page).body.textContent ?? '';
    expect(text).not.toMatch(/abonnement|facturation|\boffres?\b|\btarifs?\b|FCFA/i);
  });

  it('starts the two groups at the columns’ top: no title beside them, so no drop', () => {
    const page = serve(path, Page);
    for (const label of ['Liens légaux', 'Réseaux sociaux']) {
      const group = page.querySelector(`nav[aria-label="${label}"]`) as Element;
      expect(group.className).not.toContain('lg:pt-xxl');
      expect(group.className).toContain('lg:col-span-4');
    }
  });
});

/// The control. Without it « no link » is also what a footer that lost its group
/// everywhere would report, and that is the owner's other choice, the one refused.
describe.each(['/', '/recherche', '/professionnels', '/connexion', '/cgu/x', '/supports'])(
  '%s keeps everything',
  (path) => {
    it('« Espace pro » in the header', () => {
      const header = serve(path).querySelector('header') as Element;
      expect(hrefs(header)).toContain('/professionnels');
      expect(header.textContent).toContain('Espace pro');
    });

    it('the salons’ group in the footer, on the same line as the other two', () => {
      const page = serve(path);
      const group = page.querySelector('nav[aria-labelledby="footer-pro"]') as Element;
      expect(hrefs(group)).toEqual(SALON_LINKS);
      expect(group.querySelector('#footer-pro')?.textContent).toBe('Professionnels');
      for (const label of ['Liens légaux', 'Réseaux sociaux']) {
        expect((page.querySelector(`nav[aria-label="${label}"]`) as Element).className).toContain('lg:pt-xxl');
      }
    });
  },
);

describe('/support’s salon line', () => {
  it('says what the page helps with, without the offers', () => {
    const page = serve('/support', SupportPage);
    expect(page.body.textContent).toContain('Mise en ligne et équipe. Indiquez le nom du salon.');
  });
});

/// **The two halves of one contract, in two languages.** The app holds a list of pages of
/// our site; this file's module says what those pages may carry. A sixth page in the app
/// would be a page Apple can read that nobody cleaned, so it fails here until it is
/// classified: on the consumer app as well as Pro, because `pro_site_links_test.dart`
/// reads only Pro's closure. CI's web job has no path filter, so this runs on a
/// mobile-only PR.
describe('the app and this list: every page of ours the app holds, and no other', () => {
  const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const LIB = join(REPO_ROOT, 'mobile/lib');
  const CONFIG = join(LIB, 'core/config/app_config.dart');
  const code = stripDartComments(readFileSync(CONFIG, 'utf-8'));

  it('every path built on siteBaseUrl is in the five, and every one of the five is built', () => {
    const paths = [...code.matchAll(/(['"])\$\{?siteBaseUrl\}?(\/[^'"]*)\1/g)].map((m) => m[2]);
    expect(
      paths.sort(),
      'a new link from the app to the site: add the page to lib/storeLinkedPages.ts, or drop the link (app-review-round-2.md §5)',
    ).toEqual([...STORE_LINKED_PATHS].sort());
  });

  it('siteBaseUrl is used in no other form this test cannot read', () => {
    const uses = [...code.matchAll(/siteBaseUrl/g)].length;
    const read = [...code.matchAll(/(['"])\$\{?siteBaseUrl\}?\/[^'"]*\1/g)].length;
    expect(uses - read, 'its declaration, and nothing else').toBe(1);
    expect(code).toMatch(/static const String siteBaseUrl\s*=/);
  });

  it('no other file of the app builds a link to the site', () => {
    const files = dartFiles(LIB);
    // A pin whose walk finds nothing is green about nothing.
    expect(files.length).toBeGreaterThan(300);
    const offenders: string[] = [];
    for (const file of files) {
      if (file === CONFIG) continue;
      const source = stripDartComments(readFileSync(file, 'utf-8'));
      if (/siteBaseUrl/.test(source)) offenders.push(`${relative(LIB, file)}: siteBaseUrl`);
      for (const host of hostsOfTheSite(source)) {
        // The API's host, which no one reads as a page.
        if (host !== 'api.myweli.com') offenders.push(`${relative(LIB, file)}: ${host}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('the config itself names the site once, as the default of its base', () => {
    expect(hostsOfTheSite(code)).toEqual(['myweli.com']);
  });

  it('a host is a host however it is written', () => {
    expect(hostsOfTheSite(`'https://MyWeli.com/pro/inscription'`)).toEqual(['myweli.com']);
    expect(hostsOfTheSite(`'HTTPS://MYWELI.COM/pro'`)).toEqual(['myweli.com']);
    expect(hostsOfTheSite(`'https://myweli' '.com/pro'`)).toEqual(['myweli.com']);
    expect(hostsOfTheSite(`'https://my' + r'weli.com/pro'`)).toEqual(['myweli.com']);
    expect(hostsOfTheSite(`'https://API.myweli.com/x'`)).toEqual(['api.myweli.com']);
    expect(hostsOfTheSite(`'https://myweli.test/x', 'myweli', '.com'`)).toEqual([]);
  });

  describe('the comment stripper, or the above would be reading nothing', () => {
    it('leaves a URL in a string and an interpolation alone', () => {
      expect(stripDartComments(`const a = 'https://myweli.com'; // gone`)).toBe(`const a = 'https://myweli.com'; `);
      expect(stripDartComments(`f('$\{a['b']}//kept'); /* gone /* nested */ gone */`)).toBe(`f('$\{a['b']}//kept'); `);
    });

    it('removes a getter that only lives in a comment', () => {
      expect(stripDartComments(`/// '$siteBaseUrl/x'\n// '$siteBaseUrl/y'\n/* '$siteBaseUrl/z' */`)).not.toContain('siteBaseUrl');
    });

    it('throws rather than read past a string it lost', () => {
      expect(() => stripDartComments(`const a = 'open`)).toThrow();
    });
  });
});

/// Every host of our domain in Dart code, in lower case. The brand is written MyWeli, and a
/// host means the same in any case, so a case-sensitive read lets the likeliest spelling
/// through. Adjacent literals are one string to Dart, so they are one here: the join
/// `mobile/test/support/dart_source.dart`'s `asCopy` makes, for the same reason.
function hostsOfTheSite(code: string): string[] {
  const joined = code.replace(/['"](?:\s+|\s*\+\s*)r?['"]/g, '');
  return [...joined.matchAll(/[\w.@-]*myweli\.com/gi)].map((m) => m[0].toLowerCase());
}

function dartFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return dartFiles(path);
    return name.endsWith('.dart') ? [path] : [];
  });
}

/// `mobile/test/support/dart_source.dart`'s scanner, for the same reason it is a scanner:
/// `https://` in a string is not a comment, Dart's block comments nest, and an
/// interpolation holds code, quotes included, inside a string. Getting any of those wrong
/// strips code, so a pin passes on something it never saw. The regex version other pins
/// here use is fine for one constant; this one reads every file of the app.
function stripDartComments(source: string): string {
  type Ctx = { quote: string | null; raw: boolean; interpolation: boolean; depth: number };
  const code = (interpolation: boolean): Ctx => ({ quote: null, raw: false, interpolation, depth: 0 });
  const stack: Ctx[] = [code(false)];
  let out = '';
  let i = 0;
  const at = (token: string) => source.startsWith(token, i);

  while (i < source.length) {
    const ctx = stack[stack.length - 1];
    if (ctx.quote !== null) {
      if (at(ctx.quote)) {
        out += ctx.quote;
        i += ctx.quote.length;
        stack.pop();
      } else if (!ctx.raw && at('\\') && i + 1 < source.length) {
        out += source.slice(i, i + 2);
        i += 2;
      } else if (!ctx.raw && at('${')) {
        out += '${';
        i += 2;
        stack.push(code(true));
      } else {
        out += source[i];
        i++;
      }
      continue;
    }

    if (at('//')) {
      const end = source.indexOf('\n', i);
      if (end === -1) break;
      i = end;
      continue;
    }
    if (at('/*')) {
      let depth = 0;
      while (i < source.length) {
        if (at('/*')) {
          depth++;
          i += 2;
        } else if (at('*/')) {
          depth--;
          i += 2;
          if (depth === 0) break;
        } else {
          i++;
        }
      }
      continue;
    }
    const raw =
      at('r') &&
      (i === 0 || !/[A-Za-z0-9_$]/.test(source[i - 1])) &&
      (source[i + 1] === "'" || source[i + 1] === '"');
    const start = i + (raw ? 1 : 0);
    const opening = ["'''", '"""', "'", '"'].find((q) => source.startsWith(q, start));
    if (opening) {
      out += source.slice(i, start + opening.length);
      i = start + opening.length;
      stack.push({ quote: opening, raw, interpolation: false, depth: 0 });
      continue;
    }
    if (ctx.interpolation && at('{')) {
      ctx.depth++;
    } else if (ctx.interpolation && at('}')) {
      if (ctx.depth === 0) stack.pop();
      else ctx.depth--;
    }
    out += source[i];
    i++;
  }
  if (stack.length !== 1) throw new Error('the comment stripper ended inside a string: fix the scanner');
  return out;
}
