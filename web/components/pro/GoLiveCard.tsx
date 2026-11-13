'use client';

import Link from 'next/link';
import { Card } from '../Card';
import { useEffect, useId, useState } from 'react';
import type { ProProfile } from '../../lib/api/pro';
import { getDepositPolicy, getKycStatus, publishSalon } from '../../lib/api/pro';
import { depositChosen } from '../../lib/pro/deposit';
import type { KycStatus } from '../../lib/pro/kyc';
import { salonRefusalMessage } from '../../lib/pro/team';
import {
  type ChecklistItem,
  canPublish,
  checklistProgress,
  progressLabel,
  publishChecklist,
} from '../../lib/pro/onboarding';
import {
  BANNER_TONE_CLASS,
  BILLING_POINTER,
  type GoLiveState,
  LEGACY_HINT,
  PUBLISH_LABEL,
  REQUEST_HINT,
  STATE_LINE,
  type SalonValidation,
  type StateBanner,
  goLiveState,
  requestSentLine,
  stateBanner,
} from '../../lib/pro/salon-validation';
import { useLocalities } from '../../lib/use-localities';
import { Button, buttonClasses } from '../Button';
import { SkeletonRows } from '../Skeleton';

/// What the publish answered, for the page: 200 = the salon IS live; 202 = a
/// request MyWeli will decide (B0.18 — docs/design/web-salon-validation.md
/// §4.1), with the 202 body's validation (undefined when unreadable).
export type PublishOutcome =
  | { kind: 'live' }
  | { kind: 'requested'; validation: SalonValidation | null | undefined };

/// The owner's go-live card on « Aujourd’hui » (docs/design/pro-salon-lifecycle.md
/// B2; the app's eight steps since web-pro-golive-signup-like-app.md), and,
/// since B0.18, where the salon stands with MyWeli's validation
/// (salon-go-live-approval.md §6.1–§6.2; web-salon-validation.md §4.1).
///
/// **Two servers.** `profile.validation` absent — a server before B0.18 — is
/// `legacy`: today's card, words and « Mettre en ligne », whose publish goes
/// live at once. Present, the card has one branch per state: a banner for
/// pending, refused, offline and suspended; the checklist in every draft state
/// (each step stays editable while pending); the state's action. The publish
/// answer decides what happened, whatever the card was loaded from: a 202
/// reaching a `legacy` card (the backend deployed in between) is a request.
///
/// The team, the deposit and the KYC are shown and never block — only the
/// server's five do. R8: « Profil de l’entreprise » reads the commune list the
/// server reads (`communeIsKnown`).
export function GoLiveCard({
  profile,
  onPublished,
  onStale,
}: {
  profile: ProProfile;
  onPublished: (outcome: PublishOutcome) => void;
  /// The card's state was older than the server's (409
  /// `validation_refused_final`): the page re-reads `/me/provider`.
  onStale?: () => void;
}) {
  const state = goLiveState(profile.provider.status, profile.validation);
  if (state === 'suspended') {
    // The owner's dashboard says it (owner, 2026-11-13 — §9 Q2): no
    // checklist and no button under it, the admin's restore decides.
    return (
      <Card as="section" className="mt-m">
        <SalonStateBanner banner={stateBanner(state, profile.validation)} />
        <PreviewLink className="mt-m" />
      </Card>
    );
  }
  return (
    <ChecklistCard
      profile={profile}
      state={state}
      onPublished={onPublished}
      onStale={onStale}
    />
  );
}

function ChecklistCard({
  profile,
  state,
  onPublished,
  onStale,
}: {
  profile: ProProfile;
  state: GoLiveState;
  onPublished: (outcome: PublishOutcome) => void;
  onStale?: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [needsOffer, setNeedsOffer] = useState(false);
  const localities = useLocalities();

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
          // A choice SAVED, not an answer (B7.7).
          depositConfigured:
            deposit.status === 200 && !!deposit.policy && depositChosen(deposit.policy),
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
    // An unread list never blocks: the server decides (R8, §5).
    localities: localities.loading || localities.error ? null : localities.tree,
  });
  const ready = canPublish(items);
  const progress = checklistProgress(items);
  const banner = stateBanner(state, profile.validation);

  async function publish() {
    setBusy(true);
    setError(null);
    setNeedsOffer(false);
    const r = await publishSalon(profile.provider.id);
    setBusy(false);
    if (r.ok) {
      onPublished(
        r.status === 202
          ? { kind: 'requested', validation: r.validation }
          : { kind: 'live' },
      );
      return;
    }
    if (r.status === 409 && r.error === 'validation_refused_final') {
      // The card was older than the decision: said here (a write never fails
      // in silence, even if the re-read fails), and the page re-reads — the
      // banner then gives the final refusal's reason.
      setError(STATE_LINE.refusedFinal);
      onStale?.();
      return;
    }
    if (r.status === 409 && r.missing?.includes('offer')) {
      setNeedsOffer(true);
      setError('Choisissez votre offre avant la mise en ligne.');
      return;
    }
    setError(
      r.status === 409
        ? 'Certaines étapes ne sont pas terminées. Vérifiez la liste.'
        : salonRefusalMessage(r.status, r.error, 'La mise en ligne a échoué. Réessayez.'),
    );
  }

  const label = publishLabel(state);
  const hint =
    state === 'legacy' ? LEGACY_HINT : state === 'neverAsked' || state === 'refused' ? REQUEST_HINT : null;
  const sentLine =
    state === 'pending'
      ? requestSentLine(profile.validation?.submittedAt, profile.provider.timezone)
      : null;

  return (
    <Card as="section" className="mt-m">
      {banner ? (
        <SalonStateBanner banner={banner} />
      ) : (
        <>
          <p className="font-semibold text-textPrimary">
            Votre salon n’est pas encore en ligne
          </p>
          <p className="mt-xs text-bodyLarge text-textSecondary">
            Complétez votre profil pour apparaître dans les recherches et recevoir
            des réservations.
          </p>
        </>
      )}
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
        {state === 'legacy' ? (
          // Today's button, word for word: against a server before B0.18 the
          // publish does put the salon online.
          <Button disabled={!ready || busy} onClick={publish}>
            {busy ? 'Mise en ligne…' : PUBLISH_LABEL.legacy}
          </Button>
        ) : label ? (
          <Button disabled={!ready} isLoading={busy} onClick={publish}>
            {label}
          </Button>
        ) : null}
        {sentLine ? <p className="text-bodyMedium text-textSecondary">{sentLine}</p> : null}
        {state === 'offlineUnpaid' ? (
          // The billing pointer (§6.1): payment is manual, from « Mon abonnement ».
          <Link href="/pro/abonnement" className={buttonClasses('primary')}>
            {BILLING_POINTER}
          </Link>
        ) : null}
        {/* See the salon exactly as a client will, before going live (B4). */}
        <PreviewLink />
      </div>
      <div>
        {label && !ready && hint ? (
          // The app's sentence: not every step above is needed to go live.
          <p className="mt-xs text-bodySmall text-textTertiary">{hint}</p>
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

/// The state's button — none while pending, after a final refusal, offline
/// unpaid (the billing pointer instead) or suspended.
function publishLabel(state: GoLiveState): string | null {
  switch (state) {
    case 'legacy':
      return PUBLISH_LABEL.legacy;
    case 'neverAsked':
      return PUBLISH_LABEL.neverAsked;
    case 'refused':
      return PUBLISH_LABEL.refused;
    case 'offlineRepublish':
      return PUBLISH_LABEL.offlineRepublish;
    default:
      return null;
  }
}

/// The state's banner — the KYC page's (`VerificationClient`): a tinted box,
/// its title, then each line (a refusal's note on its own line, plain text —
/// React escapes it; a long word wraps).
export function SalonStateBanner({ banner }: { banner: StateBanner | null }) {
  if (!banner) return null;
  return (
    <div className={`rounded-xl border p-m ${BANNER_TONE_CLASS[banner.tone]}`}>
      <p className="font-semibold">{banner.title}</p>
      {banner.lines.map((line, i) => (
        <p key={i} className="mt-xs whitespace-pre-line break-words text-bodyLarge">
          {line}
        </p>
      ))}
    </div>
  );
}

/// 48px tall (SYSTEM §13): on the suspended card it is the only control.
function PreviewLink({ className = '' }: { className?: string }) {
  return (
    <Link
      href="/pro/apercu"
      className={`inline-flex min-h-12 items-center text-bodyMedium text-textPrimary underline ${className}`}
    >
      Aperçu de ma page
    </Link>
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
