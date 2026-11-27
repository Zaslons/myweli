'use client';

import { type ReactNode, useCallback, useEffect, useState } from 'react';
import {
  type ProNotificationPrefs,
  getProNotificationPrefs,
  setProEmailAlerts,
} from '../../lib/api/pro';
import { writeFailureMessage } from '../../lib/api/network';
import { loadFailure, loadFailureMessage, type LoadFailure } from '../../lib/api/load-failure';
import { ErrorState } from '../ErrorState';
import { PrefSwitch } from '../PrefSwitch';
import { SkeletonRows } from '../Skeleton';
import { EmailSeams } from '../BreakableEmail';

const TITLE_ID = 'pref-email-alerts-title';
const ALERTS_LEAD =
  'Si une notification de l’app MyWeli Pro ne peut pas vous parvenir (nouvelle demande, report, annulation, justificatif d’acompte), nous vous écrivons à';

/// « Alertes par e-mail » — under the salon's notifications
/// (docs/design/salon-email-alerts.md §4, the owner's words). When no
/// notification of the MyWeli Pro app can reach this member, the server
/// writes to them; each member sets their own (the preference is the
/// account's). On by default.
///
/// Its own states, below the list: the feed above never waits for it, and a
/// failure here never hides the feed.
export function EmailAlertsPreference({
  email,
  leading = null,
}: {
  email: string | null;
  /// Rows above this one in the same « Préférences » — « Notifications du
  /// navigateur » (docs/design/web-pro-browser-push.md §2). With one, the
  /// section shows even on an API older than this switch.
  leading?: ReactNode;
}) {
  const [prefs, setPrefs] = useState<ProNotificationPrefs | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'absent'>('loading');
  const [failure, setFailure] = useState<LoadFailure | false>(false);
  const [writeError, setWriteError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setFailure(false);
    setState('loading');
    const r = await getProNotificationPrefs();
    if (r.status !== 200) {
      setFailure(loadFailure(r.status));
      return;
    }
    if (!r.prefs) {
      // An API older than the switch: nothing it could save.
      setState('absent');
      return;
    }
    setPrefs(r.prefs);
    setState('ready');
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function toggle() {
    if (!prefs) return;
    const before = prefs;
    setPrefs({ emailAlerts: !before.emailAlerts });
    setWriteError(null);
    const r = await setProEmailAlerts(!before.emailAlerts);
    if (!r.ok) {
      setPrefs(before); // revert
      setWriteError(writeFailureMessage(r.status, 'L’enregistrement a échoué. Réessayez.'));
    } else if (r.prefs) {
      setPrefs(r.prefs);
    }
  }

  if (state === 'absent' && !leading) return null;

  return (
    <section aria-labelledby="pref-section-title" className="mt-xl">
      <h2
        id="pref-section-title"
        className="text-titleLarge font-semibold text-textPrimary"
      >
        Préférences
      </h2>
      {leading}
      {state === 'absent' ? null : failure ? (
        <ErrorState
          className="mt-m"
          message={loadFailureMessage(failure)}
          onRetry={() => void load()}
        />
      ) : state === 'loading' || !prefs ? (
        <SkeletonRows count={1} className="mt-m" />
      ) : (
        <>
          <div className="mt-m flex items-center justify-between gap-m rounded-xl border border-border bg-secondary p-m">
            {/* `min-w-0`: beside the switch this column is a flex item, and
                only with it can a long address narrow it (web-email-seams.md). */}
            <div className="min-w-0">
              <p id={TITLE_ID} className="text-bodyLarge text-textPrimary">
                Alertes par e-mail
              </p>
              {/* The address ends the sentence, on a line of its own, in ink,
                  with no period drawn; a screen reader hears the sentence whole,
                  period included (§9, web-email-seams.md §4, which reorders
                  salon-email-alerts.md §4's words to let it end it). */}
              <p className="mt-xs text-bodySmall text-textTertiary">
                {email ? (
                  <>
                    <span className="sr-only">{`${ALERTS_LEAD} ${email}.`}</span>
                    <span aria-hidden="true">
                      {ALERTS_LEAD}
                      <span className="block break-words text-textPrimary">
                        <EmailSeams address={email} />
                      </span>
                    </span>
                  </>
                ) : (
                  `${ALERTS_LEAD} votre adresse e-mail.`
                )}
              </p>
            </div>
            <PrefSwitch
              checked={prefs.emailAlerts}
              labelledBy={TITLE_ID}
              onToggle={() => void toggle()}
            />
          </div>
          {writeError ? (
            <p role="alert" className="mt-s text-bodyMedium text-error">
              {writeError}
            </p>
          ) : null}
        </>
      )}
    </section>
  );
}
