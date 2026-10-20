'use client';

import { useEffect, useRef, useState } from 'react';
import {
  type BrowserPushDeps,
  type PushRowState,
  disableBrowserPush,
  enableBrowserPush,
  rowStateOf,
} from '../../lib/pro/browser-push';
import { getBrowserPushDeps } from '../../lib/pro/browser-push-deps';
import { PrefSwitch } from '../PrefSwitch';

const TITLE_ID = 'pref-browser-push-title';

/// Whether this page has the row at all — after mount (the server cannot
/// know), and only when the Firebase web app is configured. The section's
/// heading follows it: never « Préférences » over nothing.
export function useBrowserPushRow(): boolean {
  const [present, setPresent] = useState(false);
  useEffect(() => setPresent(getBrowserPushDeps() !== null), []);
  return present;
}

/// « Notifications du navigateur » — above « Alertes par e-mail » on the
/// salon's Notifications page (docs/design/web-pro-browser-push.md §3, the
/// owner's words §9). It is THIS browser's setting (one token per browser),
/// not the account's — hence « sur cet ordinateur ».
///
/// Only a computer gets the switch (Q3); a phone, a browser that cannot, and
/// a browser that blocked us get the sentence that applies — never a switch
/// a page could not honour.
export function BrowserPushPreference() {
  const deps = useRef<BrowserPushDeps | null>(null);
  // Null until mount: the server cannot know this browser.
  const [state, setState] = useState<PushRowState | null>(null);
  const [pending, setPending] = useState<boolean | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    deps.current = getBrowserPushDeps();
    setState(rowStateOf(deps.current));
  }, []);

  if (state === null || state === 'hidden') return null;

  async function toggle() {
    const d = deps.current;
    if (!d || pending !== null) return;
    const turnOn = state !== 'on';
    setError(null);
    setPending(turnOn); // optimistic, as « Alertes par e-mail »
    if (turnOn) {
      if ((await enableBrowserPush(d)) === 'failed') setError('L’activation a échoué. Réessayez.');
    } else if ((await disableBrowserPush(d)) === 'failed') {
      setError('L’enregistrement a échoué. Réessayez.');
    }
    setPending(null);
    setState(rowStateOf(d));
  }

  const switchable = state === 'on' || state === 'off';

  return (
    <>
      <div className="mt-m flex items-center justify-between gap-m rounded-xl border border-border bg-secondary p-m">
        <div>
          <p id={TITLE_ID} className="text-bodyLarge text-textPrimary">
            Notifications du navigateur
          </p>
          {state === 'blocked' ? (
            <>
              <p className="mt-xs text-bodyMedium text-textPrimary">
                Notifications bloquées pour ce navigateur
              </p>
              <p className="mt-xs break-words text-bodySmall text-textTertiary">
                Autorisez myweli.com dans les réglages du site (l’icône à gauche de l’adresse), puis
                rechargez la page, pour être prévenu·e des réservations, reports, annulations et
                acomptes de vos clients.
              </p>
            </>
          ) : (
            <p className="mt-xs break-words text-bodySmall text-textTertiary">
              {state === 'phone'
                ? 'Sur téléphone, les notifications passent par l’app MyWeli Pro.'
                : state === 'unsupported'
                  ? 'Ce navigateur ne peut pas afficher de notifications.'
                  : 'Sur cet ordinateur, même quand MyWeli n’est pas ouvert, tant que votre navigateur l’est : nouvelle demande, report, annulation, justificatif d’acompte.'}
            </p>
          )}
        </div>
        {switchable ? (
          <PrefSwitch
            checked={pending ?? state === 'on'}
            busy={pending !== null}
            labelledBy={TITLE_ID}
            onToggle={() => void toggle()}
          />
        ) : null}
      </div>
      {error ? (
        <p role="alert" className="mt-s text-bodyMedium text-error">
          {error}
        </p>
      ) : null}
    </>
  );
}
