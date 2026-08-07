'use client';

import { AppleMark } from './AppleMark';
import { SOCIAL_BUTTON_HEIGHT, SOCIAL_BUTTON_WIDTH } from './socialButton';

/// « Continuer avec Apple », built to match the Google button beside it.
///
/// **Why this is not the shared `Button`.** Google's button is rendered by
/// Google's own script inside a cross-origin iframe at 40px — `size: 'large'`
/// is the tallest GIS offers. `Button` bakes in `min-h-12` (48px), the tap
/// target floor, and that floor is pinned by `button.test.tsx`. Matching Google
/// exactly and honouring the floor are in direct conflict, so neither a
/// `className` override nor a `variant="social"` opt-out is honest here: the
/// first cannot lower `min-h-12`, and the second would weaken the floor on the
/// one component that proves it.
///
/// The resolution is the doctrine the tap-target spec already states — grow the
/// target, not the glyph. The `<button>` is a **48px** hit box; the `<span>`
/// inside is the **40 × 320** painted surface. Visually identical to Google's
/// button, with 4px of invisible target above and below.
///
/// Sized from the shared constants in px, not rem: see `socialButton.ts`.
export function AppleSignInButton({
  onClick,
  disabled,
}: {
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="flex min-h-12 w-full items-center justify-center disabled:opacity-50"
    >
      <span
        className="flex items-center justify-center gap-s rounded-sm bg-primary text-labelLarge font-medium text-secondary"
        style={{ height: SOCIAL_BUTTON_HEIGHT, width: SOCIAL_BUTTON_WIDTH }}
      >
        <AppleMark />
        Continuer avec Apple
      </span>
    </button>
  );
}
