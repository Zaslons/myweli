import { describe, expect, it } from 'vitest';
import {
  type Subscription,
  contactWhatsAppUrl,
  isTrialing,
  subscriptionSubtitle,
  subscriptionTitle,
} from '../lib/pro/subscription-plans';

describe('pro subscription helpers', () => {
  it('trialing → days-left title + end date subtitle', () => {
    const sub: Subscription = {
      tier: 'pro',
      status: 'trial',
      trialEndsAt: '2026-09-26T00:00:00.000Z',
      trialDaysLeft: 90,
    };
    expect(isTrialing(sub)).toBe(true);
    expect(subscriptionTitle(sub)).toBe('Essai gratuit — 90 jours restants');
    expect(subscriptionSubtitle(sub)).toMatch(/Se termine le/);
  });

  it('singular day', () => {
    expect(
      subscriptionTitle({ tier: 'pro', status: 'trial', trialDaysLeft: 1 }),
    ).toBe('Essai gratuit — 1 jour restant');
  });

  it('trial ended → free copy', () => {
    const sub: Subscription = { tier: 'free', status: 'free' };
    expect(isTrialing(sub)).toBe(false);
    expect(subscriptionTitle(sub)).toBe('Essai terminé — offre Gratuite');
    expect(subscriptionSubtitle(sub)).toMatch(/Découverte/);
  });

  it('contact URL carries the prefilled message', () => {
    expect(contactWhatsAppUrl()).toContain('wa.me/');
    expect(contactWhatsAppUrl()).toContain('text=');
  });
});
