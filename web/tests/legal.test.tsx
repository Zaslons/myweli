import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import CguPage from '../app/cgu/page';
import MentionsPage from '../app/mentions-legales/page';
import ConfidentialitePage from '../app/politique-confidentialite/page';
import SuppressionPage from '../app/suppression-compte/page';
import { COMPANY, LEGAL_ROUTES, LEGAL_UPDATED_AT } from '../lib/legal';

/// L1 — the four documents, at the unit level.
///
/// The e2e specs prove the routes resolve and are accessible. This file proves
/// the things a rendered page cannot show you: that all four read ONE date, that
/// the slugs the app links to are the slugs that exist, and that the marker
/// separating engineering facts from legal judgement never shipped.

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

describe('lib/legal.ts is the single source of truth', () => {
  it('declares exactly the four routes, each with a leading slash', () => {
    expect(LEGAL_ROUTES).toHaveLength(4);
    for (const r of LEGAL_ROUTES) {
      expect(r.slug).toMatch(/^\/[a-z-]+$/);
      expect(r.h1.length).toBeGreaterThan(0);
      expect(r.description.length).toBeGreaterThan(0);
    }
  });

  it('carries the mentions-légales facts, and admits the missing ones', () => {
    // The entity is not registered yet (owner decision), so the page says so
    // rather than inventing an RCCM. When registration lands this object is the
    // ONE edit — which is only true if the page reads it from here.
    expect(COMPANY.tradingName).toBe('Myweli');
    expect(COMPANY.registration).toMatch(/en cours d’immatriculation/i);
    expect(COMPANY.hosts.length).toBeGreaterThan(0);
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
