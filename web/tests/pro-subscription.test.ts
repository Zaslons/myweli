import { describe, expect, it } from 'vitest';
import {
  type SalonOffer,
  BUSINESS_ANCHOR_MONTHLY_FCFA,
  OFFER_CARDS,
  PRO_ANCHOR_MONTHLY_FCFA,
  SETUP_HEADLINE,
  TRIAL_KEPT_LINE,
  contactWhatsAppUrl,
  offerBanner,
  tierName,
} from '../lib/pro/subscription-plans';

/// The offer ladder (team access R5a — the pricing pivot). Pure display
/// helpers; the API stays the authority on tier/status/seats/dates.

function offer(over: Partial<SalonOffer> = {}): SalonOffer {
  return {
    tier: 'pro',
    status: 'trial',
    trialEndsAt: '2026-10-12T00:00:00.000Z',
    paidUntil: null,
    graceEndsAt: '2026-10-19T00:00:00.000Z',
    unpublishedForBilling: false,
    seats: { cap: 5, used: 1 },
    ...over,
  };
}

describe('offer cards', () => {
  it('are the three tiers with the right anchors & seats', () => {
    expect(OFFER_CARDS.map((c) => c.tier)).toEqual([
      'pro',
      'business',
      'reseau',
    ]);
    const [pro, business, reseau] = OFFER_CARDS;
    expect(pro.anchorFcfa).toBe(PRO_ANCHOR_MONTHLY_FCFA);
    expect(business.anchorFcfa).toBe(BUSINESS_ANCHOR_MONTHLY_FCFA);
    expect(reseau.anchorFcfa).toBeNull(); // « Sur devis »
    expect(pro.seatsLabel).toMatch(/5/);
    expect(business.seatsLabel).toMatch(/15/);
    // Only Pro carries the ROI line.
    expect(pro.roiLine).toBeTruthy();
    expect(business.roiLine).toBeUndefined();
    // R6: multi-salons is LIVE on Réseau.
    expect(reseau.entitlements.join(' ')).toMatch(/ajoutez des salons/i);
    expect(reseau.notes?.join(' ')).toMatch(/propre offre/i);
  });

  it('the setup headline promises the 3 free months', () => {
    expect(SETUP_HEADLINE).toMatch(/3 mois offerts/);
    expect(TRIAL_KEPT_LINE).toMatch(/essai/i);
  });
});

describe('offerBanner', () => {
  it('trial → days-left title, not urgent', () => {
    const b = offerBanner(offer());
    expect(b.kind).toBe('trial');
    expect(b.title).toMatch(/Essai gratuit/);
    expect(b.urgent).toBe(false);
  });

  it('paid → active title', () => {
    const b = offerBanner(
      offer({ status: 'paid', paidUntil: '2027-01-01T00:00:00.000Z' }),
    );
    expect(b.kind).toBe('paid');
    expect(b.title).toMatch(/active/i);
    expect(b.urgent).toBe(false);
  });

  it('grace → urgent, warns about unpublish', () => {
    const b = offerBanner(offer({ status: 'grace' }));
    expect(b.kind).toBe('grace');
    expect(b.urgent).toBe(true);
    expect(b.title).toMatch(/expiré/i);
    expect(b.subtitle).toMatch(/dépublication/i);
  });

  it('expired + unpublished → the salon-dépublié copy', () => {
    const b = offerBanner(
      offer({ status: 'expired', unpublishedForBilling: true }),
    );
    expect(b.kind).toBe('expired');
    expect(b.urgent).toBe(true);
    expect(b.title).toMatch(/dépublié/i);
    expect(b.subtitle).toMatch(/n’est plus visible|réactiver/i);
  });

  it('expired but still published → the plain expired copy', () => {
    const b = offerBanner(offer({ status: 'expired' }));
    expect(b.kind).toBe('expired');
    expect(b.title).toMatch(/expirée/i);
  });
});

describe('misc', () => {
  it('tierName maps the tiers to French', () => {
    expect(tierName('pro')).toBe('Pro');
    expect(tierName('business')).toBe('Business');
    expect(tierName('reseau')).toBe('Réseau');
  });

  it('contact URL carries the prefilled message', () => {
    expect(contactWhatsAppUrl()).toContain('wa.me/');
    expect(contactWhatsAppUrl()).toContain('text=');
  });
});
