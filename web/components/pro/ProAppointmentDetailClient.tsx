"use client";

import Link from "next/link";
import { Card } from "../Card";
import { ErrorState } from "../ErrorState";
import { Chip } from "../Chip";
import { StatusChip } from "../StatusChip";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { statusLabelFr } from "../../lib/account/appointments";
import { noShowBadge, noShowLabel } from "../../lib/pro/clients";
import {
  type ProProfile,
  getMyProvider,
  arriveAppointment,
  getProAppointment,
  proAction,
} from "../../lib/api/pro";
import { formatDateTimeFr, formatFcfa } from "../../lib/format";
import {
  type LifecycleAction,
  actionsForMembership,
  hasStarted,
} from "../../lib/pro/lifecycle";
import { hasCap } from "../../lib/pro/team";
import {
  loadFailure,
  loadFailureMessage,
  type LoadFailure,
} from "../../lib/pro/load-failure";
import { rescheduleAppointment } from "../../lib/api/pro";
import { hhmm, minutesOfDay } from "../../lib/pro/journal";
import { combineDateTime } from "../../lib/pro/manual-booking";
import type { ProAppointment } from "../../lib/pro/today";
import {
  isSameSalonDay,
  salonDayKey,
  salonFormatter,
  salonToday,
} from "../../lib/time";
import { Button } from "../Button";
import { Loading } from "../Loading";
import { conflictMessage } from "../../lib/booking/window";
import { useOptionalProMembership } from "./ProMembershipContext";
import { agendaParams } from "../../lib/pro/agenda-url";
import { NoShowAction } from "./NoShowAction";
import { ProDepositProof } from "./ProDepositProof";

/// The switches this page already made, by `id:salon` — so a server that does
/// not take one cannot send the page round in circles (each switch remounts
/// it). Cleared once the page loads under that salon.
const switchedFor = new Set<string>();

/// The sentence « Mes salons » says when a switch is refused.
const SWITCH_REFUSED =
  "Changement impossible — votre accès à ce salon a peut-être été retiré.";

/// [salon] — `?salon=` from a notification about ANOTHER of the account's
/// salons (R6): the page switches to it before loading, the app's flow
/// (`ProAppointmentDetailScreen(salonId:)`;
/// docs/design/web-pro-notifications.md §3.4).
export function ProAppointmentDetailClient({
  id,
  salon,
}: {
  id: string;
  salon?: string;
}) {
  const router = useRouter();
  const switchSalon = useOptionalProMembership()?.switchSalon;
  const [switchError, setSwitchError] = useState<LoadFailure | false>(false);
  const [profile, setProfile] = useState<ProProfile | null>(null);
  const [appt, setAppt] = useState<ProAppointment | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [loadError, setLoadError] = useState<LoadFailure | false>(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // « ← Rendez-vous » returns to the agenda the salon came from — its view
  // and day ride on this page's address (docs/design/web-pro-agenda-url.md
  // §2.2), validated, never copied. Read after mount: the server render has
  // no address, and a link that differed between the two would not hydrate.
  const [backQuery, setBackQuery] = useState("");
  useEffect(() => {
    setBackQuery(agendaParams(window.location.search));
  }, []);

  const load = useCallback(async () => {
    setLoadError(false);
    setSwitchError(false);
    setNotFound(false);
    setLoading(true);
    const me = await getMyProvider();
    if (me.status === 401) {
      router.replace("/pro/connexion");
      return;
    }
    // No salon, no page (docs/design/pro-appointment-detail-profile-gate.md):
    // every time here is the salon's clock, the role shape is its membership,
    // and « Reprogrammer » writes in its timezone — without /me the page fell
    // back to Abidjan and an owner's shape, and moved a UTC+1 salon's booking
    // an hour off. A 403 lands here too; the shell's probe owns the sign-out.
    if (me.status !== 200 || !me.profile) {
      setLoadError(loadFailure(me.status));
      setLoading(false);
      return;
    }
    // Another salon's booking: switch first. A successful switch re-keys the
    // dashboard, so this page remounts and loads again under that salon.
    if (salon && switchSalon) {
      const key = `${id}:${salon}`;
      if (me.profile.provider.id !== salon) {
        // Already switched once and still elsewhere: the server did not take
        // it — say so rather than switch again.
        let outcome: "switched" | LoadFailure = "failed";
        if (!switchedFor.has(key)) {
          switchedFor.add(key);
          outcome = await switchSalon(salon);
        }
        if (outcome !== "switched") {
          switchedFor.delete(key);
          setSwitchError(outcome);
          setLoading(false);
        }
        return;
      }
      switchedFor.delete(key);
    }
    setProfile(me.profile);
    const r = await getProAppointment(id);
    if (r.status === 401) {
      router.replace("/pro/connexion");
      return;
    }
    if (r.status !== 200 || !r.appt) {
      // The API wrapper DISTINGUISHES: 404 = a loaded list without this id
      // (terminal); anything else is a transient failure — the review proved
      // a stub restart told the pro their appointment "n'existe pas".
      if (r.status === 404) setNotFound(true);
      else setLoadError(loadFailure(r.status));
      setLoading(false);
      return;
    }
    setAppt(r.appt);
    setLoading(false);
  }, [id, router, salon, switchSalon]);

  useEffect(() => {
    load();
  }, [load]);

  // « Reprogrammer » (parity 1.9) — cross-day, the app's date+time flow;
  // the server re-validates (409 → créneau indisponible).
  const [reprog, setReprog] = useState(false);
  const [reprogDate, setReprogDate] = useState("");
  const [reprogTime, setReprogTime] = useState("");
  const [reprogError, setReprogError] = useState<string | null>(null);

  async function reschedule() {
    // Never without the salon: an UNLOADED salon is not one with no
    // timezone. A loaded one with a null timezone is the server's own
    // Abidjan default (salon_time.dart `locationOf`), so the seam agrees.
    if (!profile || !reprogDate || !reprogTime) return;
    setBusy(true);
    setReprogError(null);
    // The picked wall-clock IS salon time — offset-aware build through the
    // seam (multi-pays MP3).
    const r = await rescheduleAppointment(
      id,
      combineDateTime(
        reprogDate,
        reprogTime,
        profile.provider.timezone ?? undefined,
      ) ?? "",
    );
    setBusy(false);
    if (!r.ok) {
      // The salon is exempt from its own window, so these two codes should
      // never reach a pro path — reading the code anyway costs nothing and
      // means a future change cannot make this surface lie.
      setReprogError(
        conflictMessage(r.error, {
          audience: "salon",
          taken: "Créneau indisponible. Choisissez un autre horaire.",
          fallback: "Le report a échoué. Réessayez.",
        }),
      );
      return;
    }
    setReprog(false);
    await load();
  }

  async function run(action: LifecycleAction) {
    setBusy(true);
    setError(null);
    const r = await proAction(id, action);
    setBusy(false);
    if (!r.ok) {
      setError(
        r.status === 409
          ? "Action impossible — le statut a déjà changé."
          : "L’action a échoué. Réessayez.",
      );
      return;
    }
    await load();
  }

  if (loading) return <Loading className="mt-l" />;
  if (switchError) {
    return (
      <ErrorState
        title="Rendez-vous"
        message={loadFailureMessage(switchError, SWITCH_REFUSED)}
        onRetry={load}
      />
    );
  }
  if (loadError || !profile) {
    return (
      <ErrorState
        title="Rendez-vous"
        message={loadFailureMessage(loadError)}
        onRetry={load}
      />
    );
  }
  if (notFound || !appt) {
    return (
      <div>
        <h1 className="text-headlineSmall font-semibold text-textPrimary">
          Rendez-vous
        </h1>
        <p role="alert" className="mt-m text-bodyMedium text-error">
          Rendez-vous introuvable.
        </p>
        <p className="mt-m">
          <Link href={`/pro/rendez-vous${backQuery}`} className="text-bodyMedium underline">
            ← Rendez-vous
          </Link>
        </p>
      </div>
    );
  }

  // The ACTIVE salon's market (multi-pays MP3).
  const tz = profile.provider.timezone ?? undefined;
  const currency = profile.provider.currency ?? undefined;
  const serviceName = (sid: string) =>
    profile.provider.services?.find((s) => s.id === sid)?.name;
  const services =
    (appt.serviceIds ?? []).map(serviceName).filter(Boolean).join(", ") || "—";
  // Team access R5b: the role-shaped action set (staff = Terminé/Absent on
  // their own confirmed bookings; the server enforces T40 regardless).
  // « Absent » only once the start is past (web-pro-journal-panel-deposit.md
  // §2.2 — the app's rule; the server has none).
  const membership = profile.membership;
  const actions = actionsForMembership(appt.status, membership, {
    started: hasStarted(appt.appointmentDate),
  });
  const canManageAll = hasCap(membership, "journal.manage.all");
  const canViewClients = hasCap(membership, "clients.view");
  // The screenshot is signed for the whole-journal roles only
  // (deposit_service.dart) — a Collaborateur sees the amount alone.
  const canViewDeposit = hasCap(membership, "journal.view.all");

  return (
    <div>
      <Link
        href={`/pro/rendez-vous${backQuery}`}
        className="text-bodyMedium text-textTertiary"
      >
        ← Rendez-vous
      </Link>
      <h1 className="mt-m text-headlineSmall font-semibold text-textPrimary">
        Détails du rendez-vous
      </h1>

      <Card as="section" className="mt-m">
        {/* B11: the fifth and sixth copies of this shape, and the two that
            matter most — the heading here is a SALON NAME, unbounded user
            data, sitting beside a status chip with nothing allowed to
            wrap. The four fixed earlier all hold fixed page titles. The
            review caught these; the census had listed them under "button
            clusters" rather than title toolbars. */}
        <div className="flex flex-wrap items-center justify-between gap-m">
          <p className="flex items-center gap-s font-medium text-textPrimary">
            {appt.clientDisplayName ?? appt.clientName ?? "Client"}
            {noShowBadge(appt.clientNoShowCount) !== "none" ? (
              <Chip
                variant={
                  noShowBadge(appt.clientNoShowCount) === "red"
                    ? "tinted"
                    : "neutral"
                }
                tint="error"
              >
                {noShowLabel(appt.clientNoShowCount ?? 0)}
              </Chip>
            ) : null}
            {appt.salonClientId && canViewClients ? (
              <Link
                href={`/pro/clients/${appt.salonClientId}`}
                className="text-bodySmall font-normal text-textTertiary underline"
              >
                Voir la fiche
              </Link>
            ) : null}
          </p>
          <StatusChip status={appt.status} />
        </div>

        <dl className="mt-m space-y-xs text-bodyMedium">
          <Row
            label="Date"
            value={formatDateTimeFr(appt.appointmentDate, tz)}
          />
          {appt.clientPhone ? (
            <Row label="Téléphone" value={appt.clientPhone} />
          ) : null}
          <Row label="Prestations" value={services} />
          {typeof appt.totalPrice === "number" ? (
            <Row label="Total" value={formatFcfa(appt.totalPrice, currency)} />
          ) : null}
          {appt.depositAmount ? (
            <Row
              label="Acompte annoncé"
              value={formatFcfa(appt.depositAmount, currency)}
            />
          ) : null}
        </dl>

        {/* The panel's block (web-pro-journal-panel-deposit.md §2.3): it
            loads by itself and a failure says so. It used to wait behind
            « Voir le justificatif », and a failed load did nothing at all. */}
        {appt.depositAmount ? (
          <div className="mt-s">
            <ProDepositProof
              appointmentId={appt.id}
              hasProof={!!appt.depositScreenshotUrl}
              pending={appt.status === "pending"}
              canView={canViewDeposit}
            />
          </div>
        ) : null}

        {error ? (
          <p role="alert" className="mt-s text-bodyMedium text-error">
            {error}
          </p>
        ) : null}

        {actions.length > 0 ? (
          <div className="mt-l flex flex-wrap gap-s">
            {actions.map((a) =>
              a.confirm ? (
                <NoShowAction
                  key={a.action}
                  label={a.label}
                  depositAmount={appt.depositAmount}
                  busy={busy}
                  onConfirm={() => run(a.action)}
                />
              ) : (
                <Button
                  key={a.action}
                  variant={a.variant}
                  disabled={busy}
                  onClick={() => run(a.action)}
                >
                  {a.label}
                </Button>
              ),
            )}
          </div>
        ) : null}

        {/* Parity 1.10 (J1b §4.2 debt): arrival from the detail page too. */}
        {appt.arrivedAt ? (
          <p className="mt-m text-bodyMedium text-textSecondary">
            Arrivé à{" "}
            {salonFormatter({ hour: "2-digit", minute: "2-digit" }, tz).format(
              new Date(appt.arrivedAt),
            )}
          </p>
        ) : appt.status === "confirmed" &&
          canManageAll &&
          isSameSalonDay(new Date(appt.appointmentDate), new Date(), tz) ? (
          <div className="mt-m">
            <Button
              variant="secondary"
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                const r = await arriveAppointment(id);
                setBusy(false);
                if (!r.ok) {
                  setError("Impossible d’enregistrer l’arrivée.");
                  return;
                }
                await load();
              }}
            >
              Client arrivé
            </Button>
          </div>
        ) : null}

        {(appt.status === "pending" || appt.status === "confirmed") &&
        canManageAll ? (
          <div className="mt-m border-t border-divider pt-m">
            {!reprog ? (
              <Button
                variant="secondary"
                disabled={busy}
                onClick={() => {
                  setReprog(true);
                  setReprogError(null);
                  // Prefill with the SALON wall-clock (multi-pays MP3).
                  setReprogDate(
                    salonDayKey(new Date(appt.appointmentDate), tz),
                  );
                  setReprogTime(hhmm(minutesOfDay(appt.appointmentDate, tz)));
                }}
              >
                Reprogrammer
              </Button>
            ) : (
              <div className="rounded-lg bg-surface p-m">
                <p className="text-bodyMedium text-textPrimary">
                  Nouvelle date et heure
                </p>
                <div className="mt-s flex flex-wrap gap-s">
                  <input
                    type="date"
                    aria-label="Nouvelle date"
                    // A14d: a `min` this field never had. NO `max` — the salon is
                    // exempt from its own booking window (it owns its calendar), so
                    // only the past is out of bounds here.
                    min={salonToday(new Date(), tz)}
                    value={reprogDate}
                    onChange={(e) => setReprogDate(e.target.value)}
                    className="min-h-12 rounded-lg border border-borderStrong bg-secondary p-m text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
                  />
                  <input
                    type="time"
                    aria-label="Nouvelle heure"
                    step={900}
                    value={reprogTime}
                    onChange={(e) => setReprogTime(e.target.value)}
                    className="min-h-12 rounded-lg border border-borderStrong bg-secondary p-m text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
                  />
                </div>
                {reprogError ? (
                  <p role="alert" className="mt-s text-bodyMedium text-error">
                    {reprogError}
                  </p>
                ) : null}
                <div className="mt-m flex gap-s">
                  <Button variant="secondary" onClick={() => setReprog(false)}>
                    Annuler
                  </Button>
                  <Button
                    disabled={busy || !reprogDate || !reprogTime}
                    onClick={reschedule}
                  >
                    Confirmer
                  </Button>
                </div>
              </div>
            )}
          </div>
        ) : null}
      </Card>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-m">
      <dt className="text-textTertiary">{label}</dt>
      <dd className="text-right text-textPrimary">{value}</dd>
    </div>
  );
}
