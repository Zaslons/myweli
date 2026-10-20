'use client';

import { useEffect, useRef, useState } from 'react';
import {
  type BrowserPushDeps,
  PUSH_ASKED_KEY,
  bandOffered,
  enableBrowserPush,
} from '../../lib/pro/browser-push';
import { getBrowserPushDeps } from '../../lib/pro/browser-push-deps';
import { Button } from '../Button';

const TITLE_ID = 'push-band-title';
/// How long « Notifications activées sur cet ordinateur. » stays.
const DONE_MS = 4000;

/// The Accueil's band (docs/design/web-pro-browser-push.md §2, owner Q2: like
/// the app). The app's sheet on its first dashboard visit, as a band: a
/// window on a computer's landing page would interrupt, the band says the
/// same and blocks nothing. Once per browser, whatever the answer; only
/// « Activer » asks the browser (a browser buries a question no gesture
/// asked for).
export function BrowserPushBand() {
  const deps = useRef<BrowserPushDeps | null>(null);
  const [phase, setPhase] = useState<'hidden' | 'offer' | 'busy' | 'failed' | 'done'>('hidden');

  // After mount only: the server renders no band (it cannot know this
  // browser), so the first client render must not either.
  useEffect(() => {
    deps.current = getBrowserPushDeps();
    if (bandOffered(deps.current)) setPhase('offer');
  }, []);

  useEffect(() => {
    if (phase !== 'done') return;
    const t = setTimeout(() => setPhase('hidden'), DONE_MS);
    return () => clearTimeout(t);
  }, [phase]);

  async function activate() {
    if (!deps.current) return;
    setPhase('busy');
    const outcome = await enableBrowserPush(deps.current);
    // Refused, or the question closed: the band goes — the Notifications
    // page says how to allow it again.
    setPhase(outcome === 'on' ? 'done' : outcome === 'failed' ? 'failed' : 'hidden');
  }

  function later() {
    deps.current?.store.set(PUSH_ASKED_KEY, '1');
    setPhase('hidden');
  }

  if (phase === 'hidden') return null;

  return (
    <div className="mt-l">
      {/* One live region for the whole life of the band, so the success is
          announced — a region inserted with its text often is not. */}
      <p role="status" className={phase === 'done' ? 'text-bodyMedium text-textPrimary' : 'sr-only'}>
        {phase === 'done' ? 'Notifications activées sur cet ordinateur.' : ''}
      </p>
      {phase === 'done' ? null : (
        <section
          aria-labelledby={TITLE_ID}
          className="rounded-xl border border-border bg-secondary p-m"
        >
          <h2 id={TITLE_ID} className="text-titleMedium font-semibold text-textPrimary">
            Activer les notifications
          </h2>
          <p className="mt-xs text-bodyMedium text-textSecondary">
            Soyez prévenu·e sur cet ordinateur dès qu’un client réserve, reporte, annule ou envoie
            son acompte, et ne manquez aucune demande.
          </p>
          {phase === 'failed' ? (
            <p role="alert" className="mt-s text-bodyMedium text-error">
              L’activation a échoué. Réessayez.
            </p>
          ) : null}
          <div className="mt-m flex flex-wrap gap-s">
            <Button isLoading={phase === 'busy'} onClick={() => void activate()}>
              Activer
            </Button>
            <Button variant="text" disabled={phase === 'busy'} onClick={later}>
              Plus tard
            </Button>
          </div>
        </section>
      )}
    </div>
  );
}
