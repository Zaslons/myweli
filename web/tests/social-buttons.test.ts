import { describe, expect, it } from 'vitest';

import {
  gisOptions,
  SOCIAL_BUTTON_HEIGHT,
  SOCIAL_BUTTON_WIDTH,
} from '../components/auth/socialButton';

/// The Google button's options, pinned.
///
/// This exists because the three `renderButton` call sites drifted apart while
/// nobody was looking: two carried `locale: 'fr'` and the third did not, and
/// two carried no `text` at all — so GIS fell back to `signin_with` and web
/// rendered « Se connecter avec Google » beside « Continuer avec Apple », while
/// both apps said « Continuer avec ». Nothing failed; the copy was just wrong.
describe('gisOptions', () => {
  it('is one settled object, locale included', () => {
    expect(gisOptions('continue_with')).toEqual({
      theme: 'outline',
      shape: 'rectangular',
      size: 'large',
      text: 'continue_with',
      width: SOCIAL_BUTTON_WIDTH,
      locale: 'fr',
    });
  });

  it('differs by exactly one key between the login and signup surfaces', () => {
    // The pro registration form says « S'inscrire avec … » on mobile too, so
    // it keeps `signup_with` — the label is the ONLY thing allowed to vary.
    const login = gisOptions('continue_with');
    const signup = gisOptions('signup_with');
    const differing = Object.keys(login).filter(
      (k) =>
        login[k as keyof typeof login] !== signup[k as keyof typeof signup],
    );
    expect(differing).toEqual(['text']);
  });

  it('sizes in px, because GIS does', () => {
    // Numbers, not '20rem'. A rem-sized Apple button drifts away from Google's
    // px-sized iframe as soon as the user changes their root font size — the
    // exact mismatch the shared constants exist to prevent.
    expect(typeof SOCIAL_BUTTON_WIDTH).toBe('number');
    expect(typeof SOCIAL_BUTTON_HEIGHT).toBe('number');
    expect(SOCIAL_BUTTON_HEIGHT).toBeLessThan(48);
  });
});
