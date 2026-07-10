'use client';

import { useEffect, useState } from 'react';
import {
  type ProProfile,
  createManualBooking,
  listClients,
} from '../../lib/api/pro';
import { formatDateTimeFr, formatDuration, formatFcfa, priceRange } from '../../lib/format';
import type { SalonClientListItem } from '../../lib/pro/clients';
import {
  canSubmitManualBooking,
  combineDateTime,
  isFutureIso,
  manualBookingTotal,
} from '../../lib/pro/manual-booking';
import { Button } from '../Button';

const todayYmd = () => new Date().toISOString().slice(0, 10);

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
  onToast,
}: {
  providerId: string;
  profile: ProProfile;
  artistId?: string;
  dateTimeIso?: string;
  initialDate?: string;
  initialClient?: { name: string; phone?: string };
  onClose: () => void;
  onCreated: () => void;
  onToast: (msg: string) => void;
}) {
  const services = (profile.provider.services ?? []).filter(
    (s) => s.active !== false,
  );
  const [selected, setSelected] = useState<string[]>([]);
  const [date, setDate] = useState(initialDate ?? todayYmd());
  const [time, setTime] = useState('');
  const [query, setQuery] = useState('');
  const [matches, setMatches] = useState<SalonClientListItem[]>([]);
  const [picked, setPicked] = useState<{ name: string; phone?: string } | null>(
    initialClient ?? null,
  );
  const [newPhone, setNewPhone] = useState('');
  const [note, setNote] = useState('');
  const [sendSms, setSendSms] = useState(true);
  const [busy, setBusy] = useState(false);

  // Grid-cell entry: the tapped cell IS the date/time choice.
  const fixed = Boolean(dateTimeIso);
  const dt = fixed ? dateTimeIso! : time ? combineDateTime(date, time) : null;
  const phone = picked?.phone ?? (newPhone.trim() || undefined);
  const total = manualBookingTotal(services, selected);

  // Debounced client search (C1 endpoint).
  useEffect(() => {
    if (picked || query.trim().length < 2) {
      setMatches([]);
      return;
    }
    const t = setTimeout(async () => {
      const r = await listClients(providerId, { query });
      setMatches(r.list?.items.slice(0, 5) ?? []);
    }, 250);
    return () => clearTimeout(t);
  }, [providerId, query, picked]);

  function toggle(id: string) {
    setSelected((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id],
    );
  }

  const canSubmit = canSubmitManualBooking({
    serviceIds: selected,
    dateTimeIso: dt,
    clientNamed: Boolean(picked) || query.trim().length >= 1,
  });

  async function create() {
    if (!canSubmit || !dt) return;
    // The app's future-only guard — on the standalone path (a grid cell is
    // the salon's own calendar choice).
    if (!fixed && !isFutureIso(dt)) {
      onToast('Choisissez une date et une heure à venir');
      return;
    }
    setBusy(true);
    const name = picked?.name ?? query.trim();
    const r = await createManualBooking(providerId, {
      serviceIds: selected,
      appointmentDateTime: dt,
      artistId: artistId || undefined,
      clientName: name || undefined,
      clientPhone: phone,
      notes: note.trim() || undefined,
      sendSmsInvite: sendSms && Boolean(phone),
    });
    setBusy(false);
    if (r.ok) onCreated();
    else
      onToast(
        r.status === 409
          ? 'Ce créneau est déjà pris.'
          : 'Création impossible. Réessayez.',
      );
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Nouveau rendez-vous"
      className="fixed inset-0 z-50 flex items-center justify-center bg-primary/40 p-m"
      onClick={onClose}
    >
      <div
        className="max-h-[90vh] w-full max-w-sm overflow-y-auto rounded-xl border border-border bg-secondary p-l"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="text-lg font-semibold text-textPrimary">
          Nouveau rendez-vous
        </h2>
        {fixed ? (
          <p className="mt-xs text-sm text-textSecondary">
            {formatDateTimeFr(dateTimeIso!)}
          </p>
        ) : null}

        {/* Prestations (multi-select, the app's checkbox list) */}
        <p className="mt-m text-xs font-medium uppercase tracking-wide text-textTertiary">
          Prestations
        </p>
        {services.length === 0 ? (
          <p className="mt-xs text-sm text-textTertiary">
            Ajoutez des services à votre profil pour pouvoir créer un
            rendez-vous.
          </p>
        ) : (
          <ul className="mt-xs divide-y divide-divider">
            {services.map((s) => (
              <li key={s.id}>
                <label className="flex cursor-pointer items-center gap-s py-xs text-sm">
                  <input
                    type="checkbox"
                    checked={selected.includes(s.id)}
                    onChange={() => toggle(s.id)}
                  />
                  <span className="flex-1 text-textPrimary">{s.name}</span>
                  <span className="text-textTertiary">
                    {priceRange(s.price ?? 0, s.priceMax)} ·{' '}
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
            <p className="text-xs font-medium uppercase tracking-wide text-textTertiary">
              Date &amp; heure
            </p>
            <div className="mt-xs flex gap-s">
              <input
                type="date"
                aria-label="Date du rendez-vous"
                min={todayYmd()}
                value={date}
                onChange={(e) => setDate(e.target.value)}
                className="flex-1 rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
              />
              <input
                type="time"
                aria-label="Heure du rendez-vous"
                step={900}
                value={time}
                onChange={(e) => setTime(e.target.value)}
                className="flex-1 rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
              />
            </div>
          </div>
        ) : null}

        {/* Client search-or-create (J1 §3.4 — kept) */}
        <p className="mt-m text-xs font-medium uppercase tracking-wide text-textTertiary">
          Client
        </p>
        {picked ? (
          <div className="mt-xs flex items-center justify-between rounded-lg bg-surface p-s text-sm">
            <span className="text-textPrimary">
              {picked.name}
              {picked.phone ? ` · ${picked.phone}` : ''}
            </span>
            <button
              type="button"
              className="text-textTertiary underline"
              onClick={() => setPicked(null)}
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
              className="w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
            />
            {matches.length > 0 ? (
              <ul className="mt-xs divide-y divide-border rounded-lg border border-border">
                {matches.map((c) => (
                  <li key={c.id}>
                    <button
                      type="button"
                      className="flex w-full justify-between px-s py-xs text-left text-sm hover:bg-surface"
                      onClick={() =>
                        setPicked({
                          name: c.displayName,
                          phone: c.phone ?? undefined,
                        })
                      }
                    >
                      <span className="text-textPrimary">{c.displayName}</span>
                      <span className="text-textTertiary">{c.phone ?? ''}</span>
                    </button>
                  </li>
                ))}
              </ul>
            ) : query.trim().length >= 1 ? (
              <input
                type="tel"
                value={newPhone}
                onChange={(e) => setNewPhone(e.target.value)}
                placeholder="Téléphone (pour retrouver ce client)"
                aria-label="Téléphone du nouveau client"
                className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
              />
            ) : null}
          </div>
        )}

        {/* SMS switch (backend no-op until the notifications slice) */}
        <label
          className={`mt-m flex items-start gap-s text-sm ${
            phone ? '' : 'opacity-45'
          }`}
        >
          <input
            type="checkbox"
            disabled={!phone}
            checked={sendSms && Boolean(phone)}
            onChange={(e) => setSendSms(e.target.checked)}
          />
          <span>
            <span className="text-textPrimary">
              Envoyer la confirmation par SMS
            </span>
            <span className="block text-xs text-textTertiary">
              Le client reçoit un lien vers l’app (bientôt disponible)
            </span>
          </span>
        </label>

        {/* Note */}
        <textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          rows={2}
          maxLength={500}
          placeholder="Note (optionnel)"
          aria-label="Note"
          className="mt-m w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
        />

        {/* Total (the app's running sum; server re-prices) */}
        <div className="mt-m flex items-center justify-between text-sm">
          <span className="text-textSecondary">Total</span>
          <span className="font-semibold text-primary">{formatFcfa(total)}</span>
        </div>

        <div className="mt-l flex justify-end gap-s">
          <Button variant="secondary" onClick={onClose} disabled={busy}>
            Annuler
          </Button>
          <Button onClick={create} disabled={busy || !canSubmit}>
            Créer
          </Button>
        </div>
      </div>
    </div>
  );
}
