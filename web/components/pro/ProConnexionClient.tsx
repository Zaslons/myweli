'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useEffect } from 'react';
import { getMyProvider } from '../../lib/api/pro';
import { gateExitMessage, teamErrorMessage } from '../../lib/pro/team';
import { SALON_ID_PATTERN } from '../../lib/pro/notifications';
import { ProLoginOptions } from './ProLoginOptions';

/// The salon login client. `?motif=acces-retire` (team access R5b) is the
/// revoked-mid-session landing — a generic banner, no salon name in the URL.
/// `&raison=` (the rejoin gate, docs/design/pro-rejoin-gate.md S3 → S6) says
/// why the gate's last invitation went when the server decided it — the
/// expiry or « introuvable » sentence the app's root snack carries onto its
/// sign-in. `?suite=profil` (B0.19) lands on Profil. Only fixed codes and a
/// salon id are read; a URL never injects text.
export function ProConnexionClient() {
  const router = useRouter();
  const params = useSearchParams();
  const revoked = params.get('motif') === 'acces-retire';
  const why = revoked ? gateExitMessage(params.get('raison')) : null;
  // A notice's salon, carried through the login (B0.18 — the decision's
  // e-mail opens `/pro?salon={id}`; docs/design/web-salon-validation.md
  // §4.5). Only a salon id is read, never text.
  const salon = params.get('salon');
  // B0.19, decision 140 (docs/design/web-pro-account-deletion.md §7): the
  // deletion page's « Se connecter à l’Espace Pro » opens `?suite=profil`, so
  // the sign-in lands on Profil, where « Supprimer mon compte » is. A fixed
  // code compared for equality, never a URL: anything else is today's landing.
  const home =
    params.get('suite') === 'profil'
      ? '/pro/profil'
      : salon && SALON_ID_PATTERN.test(salon)
        ? `/pro?salon=${salon}`
        : '/pro';

  // A salon already signed in is not asked to sign in again
  // (docs/design/web-pro-access.md §7) — « J’ai déjà un compte » and the
  // footer link both land here. Only a 200 forwards: no session (401), a
  // revoked member (403) or no answer keep the login.
  useEffect(() => {
    let live = true;
    void getMyProvider().then((r) => {
      if (live && r.status === 200) router.replace(home);
    });
    return () => {
      live = false;
    };
  }, [router, home]);

  return (
    <div className="flex flex-col gap-s">
      {revoked ? (
        <div
          role="alert"
          className="rounded-lg border border-error/40 bg-error/10 p-m text-bodyMedium text-error"
        >
          <p>{teamErrorMessage('not_a_member')}</p>
          {why ? <p className="mt-xs">{why}</p> : null}
        </div>
      ) : null}
      <ProLoginOptions onSuccess={() => router.replace(home)} />
    </div>
  );
}
