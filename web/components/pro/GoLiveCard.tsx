'use client';

import Link from 'next/link';
import { Card } from '../Card';
import { useEffect, useId, useState } from 'react';
import type { ProProfile } from '../../lib/api/pro';
import { getDepositPolicy, getKycStatus, publishSalon } from '../../lib/api/pro';
import type { KycStatus } from '../../lib/pro/kyc';
import {
  type ChecklistItem,
  canPublish,
  checklistProgress,
  progressLabel,
  publishChecklist,
} from '../../lib/pro/onboarding';
import { Button } from '../Button';
import { SkeletonRows } from '../Skeleton';

/// The draft banner + go-live checklist (docs/design/pro-salon-lifecycle.md
/// B2): shown on the pro home while the salon is a DRAFT. « Mettre en ligne »
/// calls the server-authoritative publish gate. **No offer step** — the web
/// kept one until 2026-10-19 and it started the trial at the choice; now, as
/// in the app, the server starts it at the first publish
/// (docs/design/web-pro-access.md §12, pro-companion-path.md §5). The
/// `needsOffer` branch below remains for the one case the server still
/// refuses: a salon whose offer EXISTS and is no longer live.
///
/// **The app's eight steps** since docs/design/web-pro-golive-signup-like-app.md
/// (owner decision): its labels, its bar and « N étapes sur T terminées »; the
/// team, the deposit and the KYC are shown and never block — only the server's
/// five do. The deposit and KYC steps each take one read, as in the app; a
/// read that fails leaves its step « à faire ».
export function GoLiveCard({
  profile,
  onPublished,
}: {
  profile: ProProfile;
  onPublished: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [needsOffer, setNeedsOffer] = useState(false);

  const [extras, setExtras] = useState<{
    depositConfigured: boolean;
    kyc: KycStatus | null;
  } | null>(null);
  const progressId = useId();

  useEffect(() => {
    let active = true;
    void Promise.all([getDepositPolicy(profile.provider.id), getKycStatus()]).then(
      ([deposit, kyc]) => {
        if (!active) return;
        setExtras({
          depositConfigured: deposit.status === 200 && Boolean(deposit.policy),
          kyc: kyc.status === 200 ? (kyc.kyc ?? null) : null,
        });
      },
    );
    return () => {
      active = false;
    };
  }, [profile.provider.id]);

  const items = publishChecklist(profile.provider, {
    businessType: profile.account.businessType,
    depositConfigured: extras?.depositConfigured ?? false,
    kyc: extras?.kyc ?? null,
  });
  const ready = canPublish(items);
  const progress = checklistProgress(items);

  async function publish() {
    setBusy(true);
    setError(null);
    setNeedsOffer(false);
    const r = await publishSalon(profile.provider.id);
    setBusy(false);
    if (!r.ok) {
      if (r.status === 409 && r.missing?.includes('offer')) {
        setNeedsOffer(true);
        setError('Choisissez votre offre avant la mise en ligne.');
        return;
      }
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
    <Card as="section" className="mt-m">
      <p className="font-semibold text-textPrimary">
        Votre salon n’est pas encore en ligne
      </p>
      <p className="mt-xs text-bodyLarge text-textSecondary">
        Complétez votre profil pour apparaître dans les recherches et recevoir
        des réservations.
      </p>
      {extras ? (
        <>
          <p id={progressId} className="mt-m text-bodySmall text-textSecondary">
            {progressLabel(progress)}
          </p>
          <div
            role="progressbar"
            aria-labelledby={progressId}
            aria-valuenow={progress.done}
            aria-valuemin={0}
            aria-valuemax={progress.total}
            className="mt-xs h-2 overflow-hidden rounded-pill bg-surface"
          >
            <div
              className="h-full rounded-pill bg-primary"
              style={{
                width: `${progress.total === 0 ? 0 : (progress.done / progress.total) * 100}%`,
              }}
            />
          </div>
          <ul className="mt-m space-y-xs">
            {items.map((item) => (
              <StepRow key={item.key} item={item} />
            ))}
          </ul>
        </>
      ) : (
        <SkeletonRows count={4} className="mt-m" />
      )}
      <div className="mt-m flex flex-wrap items-center gap-m">
        <Button disabled={!ready || busy} onClick={publish}>
          {busy ? 'Mise en ligne…' : 'Mettre en ligne'}
        </Button>
        {/* See the salon exactly as a client will, before going live (B4). */}
        <Link href="/pro/apercu" className="text-bodyMedium text-textPrimary underline">
          Aperçu de ma page
        </Link>
      </div>
      <div>
        {!ready ? (
          // The app's sentence: not every step above is needed to go live.
          <p className="mt-xs text-bodySmall text-textTertiary">
            Complétez les étapes essentielles pour mettre votre profil en ligne.
          </p>
        ) : null}
        {error ? <p role="alert" className="mt-xs text-bodyMedium text-error">{error}</p> : null}
        {needsOffer ? (
          <Link
            href="/pro/abonnement"
            className="mt-xs inline-block text-bodyMedium text-textPrimary underline"
          >
            Choisir mon offre
          </Link>
        ) : null}
      </div>
    </Card>
  );
}

function StepRow({ item }: { item: ChecklistItem }) {
  const mark =
    item.status === 'done' ? '✓' : item.status === 'inProgress' ? '◐' : '○';
  return (
    <li className="flex items-center gap-s text-bodyMedium">
      <span
        aria-hidden="true"
        className={item.done ? 'text-success' : 'text-textTertiary'}
      >
        {mark}
      </span>
      <span className="min-w-0">
        <span className={item.done ? 'text-textSecondary' : 'text-textPrimary'}>
          {item.label}
        </span>
        {item.sublabel ? (
          <span className="block text-bodySmall text-textTertiary">
            {item.sublabel}
          </span>
        ) : null}
      </span>
      {!item.done ? (
        <Link
          href={item.href}
          className="ml-auto shrink-0 text-bodyMedium text-textPrimary underline"
        >
          Compléter
        </Link>
      ) : null}
    </li>
  );
}
