'use client';

import Link from 'next/link';
import { useState } from 'react';
import type { ProProfile } from '../../lib/api/pro';
import { publishSalon } from '../../lib/api/pro';
import { canPublish, publishChecklist } from '../../lib/pro/onboarding';
import { Button } from '../Button';

/// The draft banner + go-live checklist (docs/design/pro-salon-lifecycle.md
/// B2): shown on the pro home while the salon is a DRAFT. Mirrors the app's
/// onboarding checklist; « Mettre en ligne » calls the server-authoritative
/// publish gate.
export function GoLiveCard({
  profile,
  onPublished,
}: {
  profile: ProProfile;
  onPublished: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const items = publishChecklist(profile.provider);
  const ready = canPublish(items);

  async function publish() {
    setBusy(true);
    setError(null);
    const r = await publishSalon(profile.provider.id);
    setBusy(false);
    if (!r.ok) {
      setError(
        r.status === 409
          ? 'Certaines étapes ne sont pas terminées. Vérifiez la liste.'
          : 'La mise en ligne a échoué. Réessayez.',
      );
      return;
    }
    onPublished();
  }

  return (
    <section className="mt-m rounded-xl border border-border bg-secondary p-l">
      <p className="font-semibold text-textPrimary">
        Votre salon n’est pas encore en ligne
      </p>
      <p className="mt-xs text-sm text-textSecondary">
        Complétez votre profil pour apparaître dans les recherches et recevoir
        des réservations.
      </p>
      <ul className="mt-m space-y-xs">
        {items.map((item) => (
          <li key={item.key} className="flex items-center gap-s text-sm">
            <span
              aria-hidden="true"
              className={item.done ? 'text-success' : 'text-textTertiary'}
            >
              {item.done ? '✓' : '○'}
            </span>
            <span
              className={item.done ? 'text-textSecondary' : 'text-textPrimary'}
            >
              {item.label}
            </span>
            {!item.done ? (
              <Link
                href={item.href}
                className="ml-auto shrink-0 text-sm text-textPrimary underline"
              >
                Compléter
              </Link>
            ) : null}
          </li>
        ))}
      </ul>
      <div className="mt-m flex flex-wrap items-center gap-m">
        <Button disabled={!ready || busy} onClick={publish}>
          {busy ? 'Mise en ligne…' : 'Mettre en ligne'}
        </Button>
        {/* See the salon exactly as a client will, before going live (B4). */}
        <Link href="/pro/apercu" className="text-sm text-textPrimary underline">
          Aperçu de ma page
        </Link>
      </div>
      <div>
        {!ready ? (
          <p className="mt-xs text-xs text-textTertiary">
            Terminez les étapes ci-dessus pour mettre votre salon en ligne.
          </p>
        ) : null}
        {error ? <p className="mt-xs text-sm text-error">{error}</p> : null}
      </div>
    </section>
  );
}
