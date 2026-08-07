/// Shared geometry for the two social sign-in buttons.
///
/// Google's button is rendered by Google's own script inside a cross-origin
/// iframe, so its size is not ours to choose — we pick the closest preset and
/// then build the Apple button to match. Both read these constants, which is
/// what keeps them matched as either side changes.
///
/// Design: docs/design/web-auth-social.md.

/// px, NOT rem. GIS sizes its iframe in absolute pixels that a root-font change
/// cannot reach, so a rem-sized Apple button would silently drift away from it
/// under Chrome's font-size preference — the exact mismatch these constants
/// exist to remove.
export const SOCIAL_BUTTON_WIDTH = 320;

/// GIS `size: 'large'` renders 40px and offers nothing taller. The Apple
/// button paints at this height inside a 48px-tall hit target — see
/// AppleSignInButton.
export const SOCIAL_BUTTON_HEIGHT = 40;

/// The label GIS renders. `continue_with` on the login surfaces to match the
/// apps' « Continuer avec … »; `signup_with` on the pro registration form,
/// which says « S'inscrire avec … » on mobile too.
export type GisText = "continue_with" | "signup_with";

/// The one options object all three `renderButton` call sites use. Sharing it
/// is what closed the `locale: 'fr'` drift, where two files had it and the
/// third did not.
export function gisOptions(text: GisText) {
  return {
    theme: "outline" as const,
    shape: "rectangular" as const,
    size: "large" as const,
    text,
    width: SOCIAL_BUTTON_WIDTH,
    locale: "fr",
  };
}
