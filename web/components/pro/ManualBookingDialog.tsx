"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { loadFailure, loadFailureMessage, type LoadFailure } from "../../lib/api/load-failure";
import { SubmissionKey } from "../../lib/api/network";
import {
  type ProProfile,
  createManualBooking,
  listClients,
} from "../../lib/api/pro";
import {
  formatDateTimeFr,
  formatDuration,
  formatFcfa,
  priceRange,
} from "../../lib/format";
import type { SalonClientListItem } from "../../lib/pro/clients";
import {
  canSubmitManualBooking,
  newClientNeedsPhone,
  combineDateTime,
  isFutureIso,
  manualBookingTotal,
} from "../../lib/pro/manual-booking";
import { salonToday } from "../../lib/time";
import { useFieldErrors } from "../../lib/forms/useFieldErrors";
import { normalizePhone, phoneFieldError } from "../../lib/phone";
import { Button } from "../Button";
import { Modal } from "../Modal";
import { PhoneField } from "../PhoneField";
import { conflictMessage } from "../../lib/booking/window";

const todayYmd = (tz?: string) => salonToday(new Date(), tz);

/// An existing salon client — from the search, or handed in by its card.
/// `linked`: the card is linked to a MyWeli account, whose number it carries
/// read-only (docs/design/phone-leftovers.md §8) — only the client can
/// correct it.
type PickedClient = { id: string; name: string; phone?: string; linked?: boolean };

/// The web salon-entered booking (docs/design/web-manual-booking.md) — the
/// app's `ProManualBookingScreen`, web-adapted, with the J1 §3.4 C1 client
/// search-or-create kept. Three entry points: a journal grid cell (fixed
/// `dateTimeIso` + `artistId`), the rendez-vous header (standalone date/time
/// inputs) and the client card (`initialClient` pre-picked).
export function ManualBookingDialog({
  providerId,
  profile,
  artistId,
  dateTimeIso,
  initialDate,
  initialClient,
  onClose,
  onCreated,
}: {
  providerId: string;
  profile: ProProfile;
  artistId?: string;
  dateTimeIso?: string;
  initialDate?: string;
  /** The client card's own client — its id names the card a refusal of its
   *  stored number points to. */
  initialClient?: PickedClient;
  onClose: () => void;
  onCreated: () => void;
}) {
  const services = (profile.provider.services ?? []).filter(
    (s) => s.active !== false,
  );
  // The ACTIVE salon's market (multi-pays MP3): picked wall-clocks are the
  // SALON's; prices carry its currency.
  const tz = profile.provider.timezone ?? undefined;
  const currency = profile.provider.currency ?? undefined;
  const [selected, setSelected] = useState<string[]>([]);
  const [date, setDate] = useState(initialDate ?? todayYmd(tz));
  const [time, setTime] = useState("");
  const [query, setQuery] = useState("");
  const [matches, setMatches] = useState<SalonClientListItem[]>([]);
  // The search failed: it says so — not the same fact as « no such client »
  // (docs/design/web-pro-truthful-failure.md §2.1, owner Q3). The name can
  // still be typed and the client created.
  const [searchFailed, setSearchFailed] = useState<LoadFailure | false>(false);
  const [searchKey, setSearchKey] = useState(0);
  const [picked, setPicked] = useState<PickedClient | null>(
    initialClient ?? null,
  );
  const [newPhone, setNewPhone] = useState("");
  // « Client sans numéro » — the app's box: the walk-in nobody knows.
  const [withoutNumber, setWithoutNumber] = useState(false);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  // One Idempotency-Key per submission (docs/design/write-idempotency.md §4).
  const submission = useRef(new SubmissionKey());

  // Grid-cell entry: the tapped cell IS the date/time choice.
  const fixed = Boolean(dateTimeIso);
  const dt = fixed
    ? dateTimeIso!
    : time
      ? combineDateTime(date, time, tz)
      : null;
  const phone = picked
    ? picked.phone
    : withoutNumber
      ? undefined
      : normalizePhone(newPhone) || undefined;
  const total = manualBookingTotal(services, selected);

  // Debounced client search (C1 endpoint).
  useEffect(() => {
    if (picked || query.trim().length < 2) {
      setMatches([]);
      setSearchFailed(false);
      return;
    }
    let active = true;
    const t = setTimeout(async () => {
      const r = await listClients(providerId, { query });
      if (!active) return;
      setMatches(r.list?.items.slice(0, 5) ?? []);
      setSearchFailed(r.status === 200 && r.list ? false : loadFailure(r.status));
    }, 250);
    return () => {
      active = false;
      clearTimeout(t);
    };
  }, [providerId, query, picked, searchKey]);

  function toggle(id: string) {
    setSelected((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id],
    );
  }

  // `cardId`: the client card a refusal points to (§7 below) — the way out
  // rides with its sentence, so neither can outlive the other. `aboutPicked`:
  // the sentence is about the picked client, and goes with them (« Changer »).
  const [error, setError] = useState<{
    text: string;
    cardId?: string;
    aboutPicked?: boolean;
  } | null>(null);
  // The phone-field fault sits UNDER the field (§14) — the E.164 lesson: the
  // backend refuses non-E.164 with `invalid_phone`, and this dialog used to
  // send raw text and label the refusal « Création impossible. Réessayez. ».
  // PhoneField emits E.164 (or ''), so a passing number here IS sendable —
  // the shared rule (docs/design/phone-national-length.md) also holds a
  // market's number to its national length.
  // Required for a NEW client unless « Client sans numéro » (the app's rule,
  // docs/design/web-manual-booking-walk-in.md).
  const needsPhone = newClientNeedsPhone({ picked: Boolean(picked), withoutNumber });
  const fields = useFieldErrors({
    phone: (v: string) => phoneFieldError(v, { required: needsPhone }),
  });

  const canSubmit = canSubmitManualBooking({
    serviceIds: selected,
    dateTimeIso: dt,
  });

  async function create() {
    if (!canSubmit || !dt) return;
    // Only the NEW-client phone has a field to gate. A picked client's stored
    // phone is shown, not editable here, and crosses as stored — the server
    // judges it (a number stored before the national-length rule is refused:
    // see the `invalid_phone` arm below).
    if (!picked && !withoutNumber && !fields.validate({ phone: newPhone })) return;
    // The app's future-only guard — on the standalone path (a grid cell is
    // the salon's own calendar choice).
    if (!fixed && !isFutureIso(dt)) {
      setError({ text: "Choisissez une date et une heure à venir" });
      return;
    }
    setError(null);
    setBusy(true);
    const name = picked?.name ?? query.trim();
    const booking = {
      serviceIds: selected,
      appointmentDateTime: dt,
      artistId: artistId || undefined,
      clientName: name || undefined,
      clientPhone: phone,
      notes: note.trim() || undefined,
      // Always `false`, and sent rather than omitted — the same payload as the
      // app (`FeatureFlags.smsInvite` is off there). No SMS is sent by
      // anything today, so the dialog offers no control for one
      // (docs/design/web-manual-booking.md §2).
      sendSmsInvite: false,
    };
    const r = await createManualBooking(
      providerId,
      booking,
      submission.current.for(booking),
    );
    setBusy(false);
    if (r.ok) {
      submission.current.settle();
      onCreated();
    }
    else if (r.error === "invalid_phone" && picked?.phone)
      // docs/design/phone-leftovers.md §7: the refused number is the one on
      // the client's card, and this dialog has no field for it — the generic
      // « format international » sentence sent the salon looking for one.
      // Say where the fault is, and lead there — unless the card is LINKED:
      // its number is the client's MyWeli account's, read-only on the card
      // (§8), so the way to it would lead nowhere; the client corrects it.
      setError(
        picked.linked
          ? {
              text: "Le numéro de ce client est celui de son compte MyWeli : il doit le corriger dans son application.",
              aboutPicked: true,
            }
          : {
              text: "Le numéro enregistré sur la fiche de ce client est invalide.",
              cardId: picked.id,
              aboutPicked: true,
            },
      );
    else
      setError({
        text: conflictMessage(r.error, {
          audience: "salon",
          taken: "Ce créneau est déjà pris.",
          fallback: "Création impossible. Réessayez.",
        }),
      });
  }

  // ds-ignore: viewport-relative dialog scroll box.
  // eslint-disable-next-line tailwindcss/no-arbitrary-value
  const panelCls =
    "max-h-[90vh] w-full max-w-sm overflow-y-auto rounded-xl border border-border bg-secondary p-l";

  return (
    <Modal
      title="Nouveau rendez-vous"
      onClose={onClose}
      panelClassName={panelCls}
    >
      {fixed ? (
        <p className="mt-xs text-bodyMedium text-textSecondary">
          {formatDateTimeFr(dateTimeIso!, tz)}
        </p>
      ) : null}

      {/* Prestations (multi-select, the app's checkbox list) */}
      <p className="mt-m text-labelMedium font-medium uppercase text-textTertiary">
        Prestations
      </p>
      {services.length === 0 ? (
        <p className="mt-xs text-bodyLarge text-textTertiary">
          Ajoutez des services à votre profil pour pouvoir créer un rendez-vous.
        </p>
      ) : (
        <ul className="mt-xs divide-y divide-divider">
          {services.map((s) => (
            <li key={s.id}>
              <label className="flex min-h-12 cursor-pointer items-center gap-s text-bodyMedium">
                <input
                  type="checkbox"
                  className="h-5 w-5 shrink-0 accent-primary"
                  checked={selected.includes(s.id)}
                  onChange={() => toggle(s.id)}
                />
                <span className="flex-1 text-textPrimary">{s.name}</span>
                <span className="text-textTertiary">
                  {priceRange(s.price ?? 0, s.priceMax, currency)} ·{" "}
                  {formatDuration(s.durationMinutes ?? 0)}
                </span>
              </label>
            </li>
          ))}
        </ul>
      )}

      {/* Date & heure (standalone entry points only) */}
      {!fixed ? (
        <div className="mt-m">
          <p className="text-labelMedium font-medium uppercase text-textTertiary">
            Date &amp; heure
          </p>
          <div className="mt-xs flex gap-s">
            <input
              type="date"
              aria-label="Date du rendez-vous"
              min={todayYmd(tz)}
              value={date}
              onChange={(e) => setDate(e.target.value)}
              className="flex-1 min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
            />
            <input
              type="time"
              aria-label="Heure du rendez-vous"
              step={900}
              value={time}
              onChange={(e) => setTime(e.target.value)}
              className="flex-1 min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
            />
          </div>
        </div>
      ) : null}

      {/* Client search-or-create (J1 §3.4 — kept) */}
      <p className="mt-m text-labelMedium font-medium uppercase text-textTertiary">
        Client
      </p>
      {picked ? (
        <div className="mt-xs flex items-center justify-between rounded-lg bg-surface p-s text-bodyMedium">
          <span className="text-textPrimary">
            {picked.name}
            {picked.phone ? ` · ${picked.phone}` : ""}
          </span>
          <button
            type="button"
            className="-my-sm inline-flex min-h-12 items-center text-textTertiary underline"
            onClick={() => {
              setPicked(null);
              // A refusal about THIS client's number goes with them.
              setError((e) => (e?.aboutPicked ? null : e));
            }}
          >
            Changer
          </button>
        </div>
      ) : (
        <div className="mt-xs">
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Client (nom ou téléphone)…"
            aria-label="Rechercher ou nommer le client"
            aria-describedby={searchFailed ? "client-search-failed" : undefined}
            className="w-full min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
          />
          {searchFailed ? (
            <div className="mt-xs flex flex-wrap items-center gap-s">
              <p id="client-search-failed" role="alert" className="text-bodyMedium text-error">
                {loadFailureMessage(searchFailed, "Recherche indisponible.")}
              </p>
              <Button variant="secondary" onClick={() => setSearchKey((k) => k + 1)}>
                Réessayer
              </Button>
            </div>
          ) : null}
          {matches.length > 0 ? (
            <ul className="mt-xs divide-y divide-border rounded-lg border border-border">
              {matches.map((c) => (
                <li key={c.id}>
                  <button
                    type="button"
                    className="flex min-h-12 w-full items-center justify-between px-s text-left text-bodyMedium hover:bg-surface"
                    onClick={() =>
                      setPicked({
                        id: c.id,
                        name: c.displayName,
                        phone: c.phone ?? undefined,
                        linked: c.linked,
                      })
                    }
                  >
                    <span className="text-textPrimary">{c.displayName}</span>
                    <span className="text-textTertiary">{c.phone ?? ""}</span>
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
          {/* The number is always asked for a new client, and « Client sans
              numéro » turns it off — the app's form (it used to appear only
              once a name was typed, and was optional). */}
          <div className="mt-xs">
            <PhoneField
              label="Téléphone (pour retrouver ce client)"
              disabled={withoutNumber}
              onChange={(v) => {
                setNewPhone(v);
                fields.revalidate("phone", v);
              }}
              error={withoutNumber ? null : fields.errors.phone}
            />
          </div>
          <label className="flex min-h-12 cursor-pointer items-center gap-s text-bodyMedium">
            <input
              type="checkbox"
              className="h-5 w-5 shrink-0 accent-primary"
              checked={withoutNumber}
              onChange={(e) => {
                setWithoutNumber(e.target.checked);
                // Its fault goes with the field it was about.
                if (e.target.checked) fields.set("phone", null);
              }}
            />
            <span className="text-textPrimary">Client sans numéro</span>
          </label>
        </div>
      )}

      {/* Note */}
      <textarea
        value={note}
        onChange={(e) => setNote(e.target.value)}
        rows={2}
        maxLength={500}
        placeholder="Note (optionnel)"
        aria-label="Note"
        className="mt-m w-full min-h-12 rounded-lg border border-borderStrong bg-surface p-m text-bodyLarge text-textPrimary focus:border-borderFocus focus:ring-1 focus:ring-borderFocus"
      />

      {/* Total (the app's running sum; server re-prices) */}
      <div className="mt-m flex items-center justify-between text-bodyMedium">
        <span className="text-textSecondary">Total</span>
        <span className="font-semibold text-primary">
          {formatFcfa(total, currency)}
        </span>
      </div>

      {error ? (
        <p role="alert" className="mt-s text-bodyMedium text-error">
          {error.text}
        </p>
      ) : null}
      {/* The way out (§12) for a refused stored number: the card, where the
          number lives. Closing first — from the card itself the link is the
          page under this dialog. */}
      {error?.cardId ? (
        <Link
          href={`/pro/clients/${error.cardId}`}
          onClick={onClose}
          className="mt-xs inline-flex min-h-12 items-center text-bodyMedium text-textPrimary underline"
        >
          Ouvrir la fiche
        </Link>
      ) : null}
      <div className="mt-l flex justify-end gap-s">
        <Button variant="secondary" onClick={onClose} disabled={busy}>
          Annuler
        </Button>
        <Button onClick={create} disabled={busy || !canSubmit}>
          Créer
        </Button>
      </div>
    </Modal>
  );
}
