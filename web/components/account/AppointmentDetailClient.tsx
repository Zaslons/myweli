"use client";

import Image from "next/image";
import Link from "next/link";
import type { ReactNode } from "react";
import { chipLinkClasses } from "../Chip";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import {
  type Appointment,
  canAttachDeposit,
  canCancel,
  cancellationNotice,
  canReschedule,
  isUpcoming,
  salonIsLive,
  salonStoppedMessage,
  rebookHref,
  clientStatusSentence,
  depositState,
  hasPosition,
  salonAddressLines,
} from "../../lib/account/appointments";
import { buildIcs, googleCalendarUrl } from "../../lib/account/calendar";
import { canRebook, canReview } from "../../lib/account/extras";
import {
  cancelAppointment,
  getAppointment,
  rescheduleAppointment,
} from "../../lib/api/account";
import { countryName } from "../../lib/localities";
import { fetchSlots } from "../../lib/booking/client";
import {
  DEFAULT_HORIZON_DAYS,
  DEFAULT_NOTICE_MINUTES,
  conflictMessage,
  lastBookableDay,
} from "../../lib/booking/window";
import { SlotsEmpty } from "../booking/SlotsEmpty";
import { formatDateLongFr, formatFcfa } from "../../lib/format";
import { directionsTo } from "../../lib/provider-summary";
import { salonDayKey, salonFormatter, salonToday } from "../../lib/time";
import { useLocalities } from "../../lib/use-localities";
import { Button, buttonClasses } from "../Button";
import { Card } from "../Card";
import { ClientStatusChip } from "./ClientStatusChip";
import { ButtonLink } from "../ButtonLink";
import { ErrorState } from "../ErrorState";
import { Loading } from "../Loading";
import { TextField } from "../TextField";
import { SalonTimeHint } from "../SalonTimeHint";
import { DepositProof } from "../booking/DepositProof";
import { ReviewForm } from "./ReviewForm";
import { loadFailure, loadFailureMessage, type LoadFailure } from "../../lib/api/load-failure";
import { UNNAMED_SALON, salonNameOr } from '../../lib/salon-name';

export function AppointmentDetailClient({ id }: { id: string }) {
  const router = useRouter();
  // Multi-pays MP3: the SALON's clock/currency ride the appointment's
  // carriers; the tree only resolves the hint's country label (best-effort).
  const { tree } = useLocalities();
  const [appt, setAppt] = useState<Appointment | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  // Any other failed read (no network, a 5xx): « Réessayer », never
  // « introuvable » (docs/design/web-consumer-network-failure.md §3.2).
  // Why the read failed (docs/design/app-failure-messages.md §2.2): no answer
  // says « Pas de connexion » under the title; a server that answered, the
  // error state's own sentence.
  const [loadFailed, setLoadFailed] = useState<LoadFailure | false>(false);
  const [cancelError, setCancelError] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  // « Reporter » (parity 1.1) — the app's slot-picker flow, inline.
  const [rescheduling, setRescheduling] = useState(false);
  const [reschedDate, setReschedDate] = useState("");
  const [slots, setSlots] = useState<string[]>([]);
  // A14d — web's fourth state: « we could not ask » is not « nothing is free ».
  const [slotsFailed, setSlotsFailed] = useState(false);
  // A14d — the salon's window, so an empty day can say WHY.
  //
  // **It rides the appointment now** (Decision C). It used to be fetched from
  // the public `GET /providers/{id}` when the pane opened, and fell back to
  // 365 days / 60 minutes on any failure — so a salon that stopped being
  // publicly readable got a year-wide picker and the client was told « Ce
  // salon n'a plus de disponibilité à cette date », which was not the reason.
  // The server stamps the salon's real numbers (and substitutes the defaults
  // itself when the salon set none), so there is nothing left to fall back to.
  const [slotsLoading, setSlotsLoading] = useState(false);
  const [pickedSlot, setPickedSlot] = useState<string | null>(null);
  const [reschedError, setReschedError] = useState<string | null>(null);
  const [rescheduled, setRescheduled] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setLoadFailed(false);
    const r = await getAppointment(id);
    if (r.status === 401) {
      router.replace(`/connexion?returnTo=/mon-compte/${id}`);
      return;
    }
    // 404 = absent, 403 = someone else's (BACKEND §3.3): « introuvable » —
    // and only those. A dropped connection used to land here too, and told
    // the client their booking did not exist.
    if (r.status === 404 || r.status === 403) {
      setNotFound(true);
      setLoading(false);
      return;
    }
    if (r.status !== 200 || !r.appt) {
      setLoadFailed(loadFailure(r.status));
      setLoading(false);
      return;
    }
    setAppt(r.appt);
    setLoading(false);
  }, [id, router]);

  useEffect(() => {
    load();
  }, [load]);

  async function loadSlots(a: Appointment, date: string) {
    setSlotsLoading(true);
    setPickedSlot(null);
    const r = await fetchSlots({
      providerId: a.providerId,
      date,
      serviceIds: a.serviceIds ?? [],
      durationMinutes: a.durationMinutes ?? 30,
      artistId: a.artistId ?? null,
    });
    setSlots(r.slots);
    setSlotsFailed(!r.ok);
    setSlotsLoading(false);
  }

  function openReschedule(a: Appointment) {
    setRescheduling(true);
    setReschedError(null);
    setRescheduled(false);
    const tz = a.providerTimezone ?? undefined;
    const day = salonDayKey(new Date(a.appointmentDate), tz);
    const today = salonToday(new Date(), tz);
    const initial = day > today ? day : today;
    setReschedDate(initial);
    loadSlots(a, initial);
  }

  async function confirmReschedule() {
    if (!pickedSlot || !appt) return;
    setBusy(true);
    setReschedError(null);
    const r = await rescheduleAppointment(appt.id, pickedSlot);
    setBusy(false);
    if (!r.ok) {
      // A14d: was branching on the STATUS alone and discarding `r.error`, so
      // a window breach said someone had taken the slot. It had not been taken.
      setReschedError(
        conflictMessage(r.error, {
          audience: "client",
          taken: "Ce créneau vient d’être pris. Choisissez-en un autre.",
          fallback: "Le report a échoué. Réessayez.",
        }),
      );
      return;
    }
    setRescheduling(false);
    setRescheduled(true);
    await load();
  }

  async function cancel() {
    setBusy(true);
    setCancelError(false);
    const r = await cancelAppointment(id);
    setBusy(false);
    setConfirming(false);
    if (!r.ok) {
      setCancelError(true);
      return;
    }
    await load();
  }

  if (loading) return <Loading className="mt-l" />;
  if (loadFailed) {
    // The page's h1 survives the error (§4), and a way back (§12).
    return (
      <div>
        <ErrorState
          title="Rendez-vous"
          message={loadFailureMessage(loadFailed)}
          onRetry={() => void load()}
        />
        <p className="mt-m">
          <Link href="/mon-compte" className="text-bodyMedium underline">
            ← Mes rendez-vous
          </Link>
        </p>
      </div>
    );
  }
  if (notFound || !appt) {
    // A persistent state is a page: it needs the h1 and a way out
    // (SYSTEM §12 — an error state without one is a dead end).
    return (
      <div>
        <h1 className="text-titleLarge font-semibold text-textPrimary">
          Rendez-vous introuvable
        </h1>
        <p role="alert" className="mt-s text-bodyLarge text-error">
          Ce rendez-vous n’existe pas ou n’est plus accessible.
        </p>
        <p className="mt-m">
          <Link href="/mon-compte" className="text-bodyMedium underline">
            ← Mes rendez-vous
          </Link>
        </p>
      </div>
    );
  }

  // The salon's market (multi-pays): booking-stamped currency first (the
  // Fresha rule), then the provider carrier; timezone from the carrier.
  const tz = appt.providerTimezone ?? undefined;
  const currency = appt.currency ?? appt.providerCurrency ?? undefined;
  // One instant per render (web-account-bookings-truth.md §2.1, §2.7): the
  // chip, « Reporter », the calendar block, the cancel sentence and
  // « Réserver à nouveau » all ask it, so they cannot disagree. Per RENDER,
  // not per load: before A1w `isUpcoming` read the clock on every render, and
  // the cancel sentence still must — a client who opens the page at 09:59 and
  // taps « Annuler » at 10:01 is told the time has passed, and the chip and
  // « Reporter » beside it now say the same.
  const now = new Date();

  // The detail's sections (appointment-detail-complete.md §2.2): the same
  // order as the app. Each is left out when it has nothing to show.
  const deposit = depositState(appt, now);
  const sentence = clientStatusSentence(appt, now);
  const stopped = salonStoppedMessage(appt);
  const photo = httpsOrNull(appt.providerPhotoUrl);
  const addressLines = salonAddressLines(appt);
  const services = appt.serviceNames ?? [];
  const time = (iso: string) =>
    salonFormatter({ hour: "2-digit", minute: "2-digit" }, tz).format(new Date(iso));
  const end =
    appt.durationMinutes && appt.durationMinutes > 0
      ? new Date(
          Date.parse(appt.appointmentDate) + appt.durationMinutes * 60_000,
        ).toISOString()
      : null;
  // No duration in words: the two surfaces' formatters disagree, and the end
  // time already says it (§2.4).
  const hours = end
    ? `${time(appt.appointmentDate)} – ${time(end)}`
    : time(appt.appointmentDate);
  const salonButtons = [
    hasPosition(appt) ? (
      <a
        key="itineraire"
        href={directionsTo(appt.providerLatitude!, appt.providerLongitude!)}
        target="_blank"
        rel="noopener noreferrer"
        className={buttonClasses("secondary")}
      >
        Itinéraire
      </a>
    ) : null,
    appt.providerPhone ? (
      <a
        key="appeler"
        href={`tel:${appt.providerPhone.replace(/\s/g, "")}`}
        className={buttonClasses("secondary")}
      >
        Appeler
      </a>
    ) : null,
    appt.providerWhatsapp ? (
      <a
        key="whatsapp"
        href={`https://wa.me/${appt.providerWhatsapp.replace(/[^0-9]/g, "")}`}
        target="_blank"
        rel="noopener noreferrer"
        className={buttonClasses("secondary")}
      >
        WhatsApp
      </a>
    ) : null,
    // Withheld for a stopped salon: after Decision C that page 404s.
    appt.providerSlug && salonIsLive(appt) ? (
      <ButtonLink key="salon" href={`/${appt.providerSlug}`} variant="secondary">
        Voir le salon
      </ButtonLink>
    ) : null,
  ].filter(Boolean);

  return (
    <div>
      <Link href="/mon-compte" className="text-bodyMedium text-textTertiary">
        ← Mes rendez-vous
      </Link>

      {/* The header (§2.3): the cover, the name, the client's chip and its
          sentence, and the stopped-salon sentence. */}
      <section className="mt-m overflow-hidden rounded-xl border border-border bg-secondary">
        {photo ? (
          // 3:2, the salon cover's own shape (web-swiss-salon.md §1), cut at
          // `object-subject` as the card is. Decoration: the name below says
          // the same. `priority`: the page's largest element.
          <div className="relative aspect-cover w-full bg-surfaceVariant">
            <Image
              src={photo}
              alt=""
              fill
              priority
              sizes="(min-width: 672px) 640px, calc(100vw - 32px)"
              className="object-cover object-subject after:absolute after:inset-0 after:bg-surfaceVariant"
            />
          </div>
        ) : null}
        <div className="p-m">
          {/* B11: the heading here is a SALON NAME, unbounded user data,
              beside a status chip — both are allowed to wrap. */}
          <div className="flex flex-wrap items-center justify-between gap-m">
            <h1 className="text-titleLarge font-semibold text-textPrimary">
              {salonNameOr(appt.providerName, UNNAMED_SALON)}
            </h1>
            {/* The client rule's words and tone (decisions 165–166, 196),
                drawn as the list draws them — settling what A1w left to A2. */}
            <ClientStatusChip appt={appt} now={now} />
          </div>
          {sentence ? (
            <p className="mt-s text-bodyMedium text-textSecondary">{sentence}</p>
          ) : null}
          {/* The salon stopped taking appointments (§12, §6 cell 6): stated
              once, above the controls it explains. */}
          {stopped ? (
            <p
              role="status"
              className="mt-m rounded-lg bg-surfaceVariant px-m py-s text-bodyMedium text-textPrimary"
            >
              {stopped}{" "}
              <Link href="/" className="underline">
                Découvrir des salons
              </Link>
            </p>
          ) : null}
          {appt.salonEntered ? (
            <p className="mt-s text-bodySmall text-textTertiary">
              Réservé par votre salon.
            </p>
          ) : null}
        </div>
      </section>

      <DetailSection title="Le rendez-vous">
        <dl className="space-y-xs text-bodyMedium">
          <Row label="Date" value={formatDateLongFr(appt.appointmentDate, tz)} />
          <Row label="Heure" value={hours} />
          {appt.artistName ? (
            <Row label="Spécialiste" value={appt.artistName} />
          ) : null}
        </dl>
        <SalonTimeHint
          date={appt.appointmentDate}
          tz={appt.providerTimezone}
          countryLabel={countryName(tree, appt.providerCountryCode)}
        />
        {/* Parity 1.2 — add the booking to a calendar (upcoming only).
            `isUpcoming`, not `canReschedule`: a stopped salon keeps its
            calendar entry, it just cannot be moved. */}
        {isUpcoming(appt, now) ? (
          <div className="mt-m flex flex-wrap gap-s">
            <a
              href={googleCalendarUrl(appt)}
              target="_blank"
              rel="noopener noreferrer"
              className={buttonClasses("secondary")}
            >
              Ajouter au calendrier (Google)
            </a>
            <button
              type="button"
              onClick={() => {
                const blob = new Blob([buildIcs(appt)], {
                  type: "text/calendar",
                });
                const url = URL.createObjectURL(blob);
                const el = document.createElement("a");
                el.href = url;
                el.download = "rendez-vous-myweli.ics";
                el.click();
                URL.revokeObjectURL(url);
              }}
              className={buttonClasses("secondary")}
            >
              Fichier .ics
            </button>
          </div>
        ) : null}
      </DetailSection>

      {services.length > 0 ? (
        <DetailSection title="Prestations">
          <ul className="space-y-xs text-bodyMedium text-textPrimary">
            {services.map((name, i) => (
              <li key={`${i}-${name}`}>{name}</li>
            ))}
          </ul>
        </DetailSection>
      ) : null}

      {addressLines.length > 0 || salonButtons.length > 0 ? (
        <DetailSection title="Le salon">
          {addressLines.map((line) => (
            <p key={line} className="text-bodyMedium text-textSecondary">
              {line}
            </p>
          ))}
          {salonButtons.length > 0 ? (
            <div className={`flex flex-wrap gap-s ${addressLines.length > 0 ? "mt-m" : ""}`}>
              {salonButtons}
            </div>
          ) : null}
        </DetailSection>
      ) : null}

      <DetailSection title="Paiement">
        <dl className="space-y-xs text-bodyMedium">
          {typeof appt.totalPrice === "number" ? (
            <Row label="Total" value={formatFcfa(appt.totalPrice, currency)} />
          ) : null}
          {deposit ? (
            <Row
              label={deposit.label}
              value={formatFcfa(appt.depositAmount ?? 0, currency)}
            />
          ) : null}
        </dl>
        {/* The proof form carries its own heading, sentence and button, so
            the row above shows the amount alone (§2.7). */}
        {deposit?.action !== "send" && deposit?.sentence ? (
          <p className="mt-xs text-bodySmall text-textTertiary">
            {deposit.sentence}
          </p>
        ) : null}
        {deposit?.action === "send" && canAttachDeposit(appt, now) ? (
          <div className="mt-m">
            <DepositProof
              appointmentId={appt.id}
              amount={appt.depositAmount ?? 0}
              operator={appt.depositMobileMoneyOperator}
              number={appt.depositMobileMoneyNumber}
              currency={currency}
              onAttached={load}
            />
          </div>
        ) : null}
        {deposit?.action === "viewProof" ? (
          <div className="mt-s">
            <a
              href={`/api/appointments/${appt.id}/deposit-screenshot?redirect=1`}
              target="_blank"
              rel="noopener noreferrer"
              className={buttonClasses("secondary")}
            >
              Voir ma capture
            </a>
          </div>
        ) : null}
        {deposit?.showBalance && typeof appt.balanceDue === "number" ? (
          <dl className="mt-s text-bodyMedium">
            <Row
              label="Solde à régler au salon"
              value={formatFcfa(appt.balanceDue, currency)}
            />
          </dl>
        ) : null}
      </DetailSection>

      {appt.notes ? (
        <DetailSection title="Notes">
          <p className="text-bodyMedium text-textPrimary">{appt.notes}</p>
        </DetailSection>
      ) : null}

      {/* The actions (§2.8): one primary per state. */}
      <div className="mt-l">
        {cancelError ? (
          <p role="alert" className="mt-s text-bodyMedium text-error">
            L’annulation a échoué. Réessayez.
          </p>
        ) : null}

        {rescheduled ? (
          <p className="mt-m text-bodyMedium text-textSecondary">
            Rendez-vous reporté ✓
          </p>
        ) : null}

        {/* « Reporter » (parity 1.1) — the app's slot-picker flow. */}
        {canReschedule(appt, now) ? (
          <div className="mt-l">
            {!rescheduling ? (
              <Button
                variant={deposit?.action === "send" ? "secondary" : "primary"}
                onClick={() => openReschedule(appt)}
              >
                Reporter
              </Button>
            ) : (
              <div className="rounded-lg bg-surface p-m">
                <p className="text-bodyLarge text-textPrimary">
                  Choisissez un nouveau créneau
                </p>
                <TextField
                  className="mt-s"
                  label="Nouvelle date"
                  hideLabel
                  type="date"
                  min={salonToday(new Date(), tz)}
                  max={lastBookableDay(
                    appt.providerBookingHorizonDays ?? DEFAULT_HORIZON_DAYS,
                    tz,
                  )}
                  value={reschedDate}
                  onChange={(e) => {
                    setReschedDate(e.target.value);
                    if (e.target.value) loadSlots(appt, e.target.value);
                  }}
                />
                {slotsLoading ? (
                  <Loading label="Chargement des créneaux…" className="mt-s" />
                ) : slotsFailed ? (
                  <div className="mt-s" role="alert">
                    <p className="text-bodyMedium text-error">
                      Impossible de charger les créneaux. Vérifiez votre
                      connexion.
                    </p>
                    <button
                      type="button"
                      onClick={() => void loadSlots(appt, reschedDate)}
                      className={chipLinkClasses(false) + " mt-s"}
                    >
                      Réessayer
                    </button>
                  </div>
                ) : slots.length === 0 ? (
                  <SlotsEmpty
                    date={reschedDate}
                    tz={tz}
                    horizonDays={
                      appt.providerBookingHorizonDays ?? DEFAULT_HORIZON_DAYS
                    }
                    noticeMinutes={
                      appt.providerMinimumNoticeMinutes ??
                      DEFAULT_NOTICE_MINUTES
                    }
                    onGoToDay={(d) => {
                      setReschedDate(d);
                      loadSlots(appt, d);
                    }}
                  />
                ) : (
                  <div className="mt-s flex flex-wrap gap-s">
                    {slots.map((iso) => (
                      <button
                        key={iso}
                        type="button"
                        onClick={() => setPickedSlot(iso)}
                        className={chipLinkClasses(pickedSlot === iso)}
                      >
                        {salonFormatter(
                          { hour: "2-digit", minute: "2-digit" },
                          tz,
                        ).format(new Date(iso))}
                      </button>
                    ))}
                  </div>
                )}
                {reschedError ? (
                  <p role="alert" className="mt-s text-bodyMedium text-error">
                    {reschedError}
                  </p>
                ) : null}
                <div className="mt-m flex gap-s">
                  <Button
                    variant="secondary"
                    onClick={() => setRescheduling(false)}
                  >
                    Retour
                  </Button>
                  <Button
                    disabled={busy || !pickedSlot}
                    onClick={confirmReschedule}
                  >
                    Confirmer le report
                  </Button>
                </div>
              </div>
            )}
          </div>
        ) : null}

        {canCancel(appt) ? (
          <div className="mt-l">
            {!confirming ? (
              <Button variant="secondary" onClick={() => setConfirming(true)}>
                Annuler le rendez-vous
              </Button>
            ) : (
              <div className="rounded-lg bg-surface p-m">
                <p className="text-bodyLarge text-textSecondary">
                  Confirmer l’annulation&nbsp;?{" "}
                  {cancellationNotice(appt, now, currency)}
                </p>
                <div className="mt-s flex gap-s">
                  <Button
                    variant="secondary"
                    onClick={() => setConfirming(false)}
                  >
                    Retour
                  </Button>
                  <Button disabled={busy} onClick={cancel}>
                    Confirmer l’annulation
                  </Button>
                </div>
              </div>
            )}
          </div>
        ) : null}

        {/* Decision 183: any booking that is not upcoming, at a salon still
            open — the same question the « Passés » list asks. A ButtonLink,
            so it reaches 48 px (it was a 36 px hand-rolled link). */}
        {canRebook(appt, now) ? (
          <div className="mt-l">
            <ButtonLink href={rebookHref(appt)!}>Réserver à nouveau</ButtonLink>
          </div>
        ) : null}

        {canReview(appt.status) ? (
          <div className="mt-l border-t border-divider pt-l">
            <ReviewForm appointmentId={appt.id} />
          </div>
        ) : null}
      </div>
    </div>
  );
}

/// What counts as a salon's photo here, as on the card (`ProviderCard`'s
/// `photoOf`): `https://` only.
const httpsOrNull = (url: string | null | undefined): string | null =>
  url && url.startsWith("https://") ? url : null;

/// A titled card of the detail: an h2 under the salon's h1 (WEB-SYSTEM §4).
function DetailSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <Card as="section" className="mt-m">
      <h2 className="text-titleMedium font-semibold text-textPrimary">{title}</h2>
      <div className="mt-s">{children}</div>
    </Card>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    // `flex-wrap` (A2 §2.2): a value that no longer fits beside its label
    // drops under it, as the app's `LabelValueRow`; before, a long value
    // wrapped inside its own narrow box.
    <div className="flex flex-wrap justify-between gap-x-m">
      <dt className="text-textTertiary">{label}</dt>
      <dd className="text-right text-textPrimary">{value}</dd>
    </div>
  );
}
