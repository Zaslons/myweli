import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { contactWhatsAppUrl } from '../lib/pro/subscription-plans';
import { supportWhatsAppUrl } from '../lib/support';

/// **The two WhatsApp links, and the case neither of them handled.**
///
/// Both built `https://wa.me/${number}?text=…` from an env var that is unset in
/// every build this repo produces — no workflow, no infra file and no build
/// script sets `NEXT_PUBLIC_MYWELI_WHATSAPP`. An empty number does not yield a
/// broken URL that fails loudly; it yields `https://wa.me/?text=…`, which is
/// WhatsApp's own landing page. The row looks like it worked.
///
/// That matters more here than it would elsewhere: three legal documents name
/// this path as the contact of record — the mentions légales for general
/// contact, the privacy policy for data-subject rights, and the CGU for deposit
/// disputes. The Flutter app has always degraded properly (« Contact bientôt
/// disponible. »); web was the surface that did not.
///
/// The configured case is covered by the e2e, which now sets a dummy number for
/// the same reason `NEXT_PUBLIC_GOOGLE_CLIENT_ID` is set there. This file covers
/// the case the e2e cannot: no number at all.
describe('the WhatsApp links degrade instead of pretending', () => {
  const KEY = 'NEXT_PUBLIC_MYWELI_WHATSAPP';
  let saved: string | undefined;

  beforeEach(() => {
    saved = process.env[KEY];
  });
  afterEach(() => {
    if (saved === undefined) delete process.env[KEY];
    else process.env[KEY] = saved;
  });

  describe.each([
    ['supportWhatsAppUrl', () => supportWhatsAppUrl()],
    ['contactWhatsAppUrl', () => contactWhatsAppUrl()],
  ])('%s', (_name, build) => {
    it('returns null when no number is configured', () => {
      delete process.env[KEY];
      expect(build()).toBeNull();
    });

    it('returns null for an empty or blank-ish value', () => {
      process.env[KEY] = '';
      expect(build()).toBeNull();
    });

    it('builds a real wa.me link when a number IS configured', () => {
      process.env[KEY] = '2250700000000';
      const url = build();
      expect(url).toBeTruthy();
      // The number has to be IN it — `toContain('wa.me/')` was the old
      // assertion and it passes just as happily on `wa.me/?text=…`, which is
      // the defect. That is why this names the digits.
      expect(url).toContain('wa.me/2250700000000');
      expect(url).toContain('text=');
    });
  });

  it('the two links carry different prefilled messages', () => {
    process.env[KEY] = '2250700000000';
    // Support is a customer asking for help; the pro CTA is a salon asking to
    // activate an offer. Collapsing them would send a salon's payment question
    // into the support queue as an account problem.
    expect(supportWhatsAppUrl()).not.toBe(contactWhatsAppUrl());
  });
});
