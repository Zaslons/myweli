import { cleanup, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import ProfessionnelsPage, { metadata } from '../app/professionnels/page';
import { PRO_LANDING } from '../lib/pro/landing';

/// The public page for salons — « MyWeli Pro pour les salons »
/// (docs/design/web-pro-access.md §4). Indexable, server-rendered, one
/// filled action, six benefits that exist today, a FAQ in JSON-LD, and no
/// price (the owner's decision, 2026-10-19).

afterEach(cleanup);

describe('/professionnels', () => {
  it('one h1, saying what it is and for whom', () => {
    render(<ProfessionnelsPage />);
    const h1s = screen.getAllByRole('heading', { level: 1 });
    expect(h1s).toHaveLength(1);
    expect(h1s[0]).toHaveTextContent(
      'Le logiciel de réservation des salons de beauté en Côte d’Ivoire',
    );
  });

  it('two choices — sign up, or sign in — and the trial line', () => {
    render(<ProfessionnelsPage />);
    const signUps = screen.getAllByRole('link', { name: 'Inscrire mon salon' });
    expect(signUps.length).toBeGreaterThanOrEqual(1);
    for (const l of signUps) expect(l).toHaveAttribute('href', '/pro/inscription');
    expect(screen.getByRole('link', { name: 'J’ai déjà un compte' })).toHaveAttribute(
      'href',
      '/pro/connexion',
    );
    expect(screen.getByText('3 mois offerts — sans carte bancaire.')).toBeInTheDocument();
  });

  it('the six benefits, each a heading under the section', () => {
    render(<ProfessionnelsPage />);
    const section = screen.getByRole('region', { name: 'Tout ce qu’il faut pour votre salon' });
    const titles = within(section).getAllByRole('heading', { level: 3 }).map((h) => h.textContent);
    expect(titles).toEqual([
      'Votre agenda, tenu tout seul',
      'Votre vitrine sur myweli.com',
      'Votre clientèle, enregistrée d’elle-même',
      'Vos acomptes, sans intermédiaire',
      'Moins de rendez-vous manqués',
      'Votre équipe',
    ]);
  });

  it('the FAQ renders, and the same four questions ship as FAQPage JSON-LD', () => {
    const { container } = render(<ProfessionnelsPage />);
    for (const q of PRO_LANDING.faq) expect(screen.getByText(q.question)).toBeInTheDocument();
    const ld = [...container.querySelectorAll('script[type="application/ld+json"]')]
      .map((s) => JSON.parse(s.textContent ?? '{}'))
      .find((d) => d['@type'] === 'FAQPage');
    expect(ld?.mainEntity.map((e: { name: string }) => e.name)).toEqual(
      PRO_LANDING.faq.map((q) => q.question),
    );
    expect(PRO_LANDING.faq).toHaveLength(4);
  });

  it('claims only what the WEB Pro does (parity audit 2026-10-19 §2)', () => {
    // No week view on the web; the app's word « semaine » went with it.
    expect(PRO_LANDING.benefits[0].body).toBe(
      'Les clients réservent sur vos créneaux réels ; vous ajoutez les rendez-vous pris au téléphone ou au comptoir. Vue du jour par membre d’équipe, calendrier du mois et liste.',
    );
    // « tout se gère » overclaimed (alerts with the tab closed, split hours).
    // Alerts without the app now arrive by e-mail — and it says so
    // (docs/design/salon-email-alerts.md Q3).
    expect(PRO_LANDING.faq[2].answer).toBe(
      'Non : réservations, agenda, clientèle, équipe et acomptes se gèrent depuis myweli.com, sur ordinateur comme sur téléphone. Sans l’app, les alertes vous arrivent par e-mail.',
    );
  });

  it('no price anywhere on the page (owner decision, 2026-10-19)', () => {
    const { container } = render(<ProfessionnelsPage />);
    expect(container.textContent).not.toMatch(/FCFA|\/mois|Sur devis|70 000|120 000/);
  });

  it('is indexable, with its own title, description and canonical', () => {
    expect(metadata.title).toBe(
      'MyWeli Pro — logiciel de réservation pour salons de beauté en Côte d’Ivoire',
    );
    expect(String(metadata.description).length).toBeLessThanOrEqual(160);
    expect(metadata.alternates?.canonical).toBe('/professionnels');
    expect(metadata.robots).toBeUndefined();
  });
});
