'use client';

import { useEffect, useRef, useState } from 'react';
import { loadScript } from '../../lib/loadScript';
import { GoogleMark } from './GoogleMark';
import {
  SOCIAL_BUTTON_HEIGHT,
  SOCIAL_BUTTON_WIDTH,
  gisOptions,
  type GisText,
} from './socialButton';

/// « Continuer avec Google », loaded **only when the visitor asks for it**.
///
/// **The defect this replaces.** All three sign-in surfaces used to fetch
/// `accounts.google.com/gsi/client` from a mount-time `useEffect`. Measured on
/// production, with zero interaction:
///
/// ```
///   /           third-party hosts: (none)          cookies: (none)   ← control
///   /connexion  third-party hosts: accounts.google.com, fonts.gstatic.com
///               cookies: g_state@myweli.com
/// ```
///
/// So merely opening the sign-in page disclosed the visitor's IP and
/// user-agent to Google and let Google set a JS-readable cookie — before any
/// consent, before any sign-in, and before the visitor had chosen Google at
/// all. The privacy policy's « tout ce qui précède est strictement nécessaire »
/// could not survive that, and an earlier attempt to fix the sentence instead
/// of the software left the claim false.
///
/// **Why two taps, and why it cannot be one.** Google's rendered button is not
/// decoration we may replace: `docs/design/web-auth-social.md` §"Le bouton"
/// records that `renderButton` is required by Google's branding rules *and* is
/// the only source of the ID token `GoogleIdTokenVerifier` accepts — a custom
/// button would need the auth-code flow, a client secret we do not hold, and a
/// new exchange endpoint. So the first tap is ours (it activates the
/// integration); the second is Google's own button. This is the ordinary
/// two-click pattern for third-party embeds, and the cost falls only on people
/// who choose Google.
///
/// **It also makes the CLS reservation honest.** The slot used to be an empty
/// `min-h-12` div holding space for an iframe that arrived late — production
/// measured CLS 0.131 against a 0.1 budget. Now a real button occupies the slot
/// from the first paint and Google's iframe replaces it at the same size.
declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (config: {
            client_id: string;
            callback: (r: { credential: string }) => void;
          }) => void;
          renderButton: (
            el: HTMLElement,
            options: {
              theme?: string;
              size?: string;
              width?: number;
              locale?: string;
              /// GIS button text variant (e.g. 'signup_with' → « S'inscrire »).
              text?: string;
            },
          ) => void;
        };
      };
    };
  }
}

export const GSI_SRC = 'https://accounts.google.com/gsi/client';

export function GoogleSignInButton({
  clientId,
  text,
  onCredential,
  onUnavailable,
  disabled,
}: {
  clientId: string;
  text: GisText;
  onCredential: (credential: string) => void | Promise<void>;
  /// Called when the script cannot be fetched. Separate from a failed sign-in,
  /// which is the caller's business — this only reports "Google is not here".
  onUnavailable?: () => void;
  disabled?: boolean;
}) {
  const slot = useRef<HTMLDivElement>(null);
  const [phase, setPhase] = useState<'facade' | 'loading' | 'ready'>('facade');

  /// **The closure-freshness fix, and it is load-bearing.** The pro
  /// registration form's old effect listed every business field in its dep
  /// array, so the GIS callback was re-registered on each keystroke and always
  /// saw current values. A callback registered once, on click, would otherwise
  /// capture whatever the fields held at that instant and submit *those*.
  /// Reading through a ref keeps one registration correct.
  const latest = useRef(onCredential);
  latest.current = onCredential;

  async function activate() {
    if (phase !== 'facade' || disabled) return;
    setPhase('loading');
    try {
      await loadScript(GSI_SRC);
      // The loader resolving is not the same as the global existing — this is
      // the guard the Apple path has always had, for the same reason.
      if (!window.google) throw new Error('gsi_unavailable');
      setPhase('ready');
    } catch {
      setPhase('facade');
      onUnavailable?.();
    }
  }

  // `renderButton` runs only once the slot is actually visible: GIS measures
  // the element it is handed, and a `display: none` parent yields a zero-width
  // button that never appears.
  useEffect(() => {
    if (phase !== 'ready' || !slot.current || !window.google) return;
    window.google.accounts.id.initialize({
      client_id: clientId,
      callback: ({ credential }) => void latest.current(credential),
    });
    window.google.accounts.id.renderButton(slot.current, gisOptions(text));
  }, [phase, clientId, text]);

  return (
    <div className="flex min-h-12 justify-center">
      {phase === 'ready' ? null : (
        <button
          type="button"
          onClick={activate}
          disabled={disabled || phase === 'loading'}
          aria-busy={phase === 'loading'}
          className="flex min-h-12 w-full items-center justify-center disabled:opacity-50"
        >
          <span
            className="flex items-center justify-center gap-s rounded-sm border border-divider bg-surface text-labelLarge font-medium text-textPrimary"
            style={{ height: SOCIAL_BUTTON_HEIGHT, width: SOCIAL_BUTTON_WIDTH }}
          >
            <GoogleMark />
            {phase === 'loading' ? 'Chargement…' : 'Continuer avec Google'}
          </span>
        </button>
      )}
      {/* Announced, because the control the visitor just pressed is replaced by
          a different one they must press again — a change a sighted user sees
          and a screen-reader user would otherwise not be told about. */}
      <div
        ref={slot}
        aria-live="polite"
        className={phase === 'ready' ? '' : 'hidden'}
      />
    </div>
  );
}
