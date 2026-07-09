'use client';

import { useEffect, useState } from 'react';
import {
  type ProProfile,
  createManualBooking,
  listClients,
} from '../../lib/api/pro';
import { formatDateTimeFr, formatFcfa } from '../../lib/format';
import type { SalonClientListItem } from '../../lib/pro/clients';
import { Button } from '../Button';

/// Quick-create from an empty grid cell (module journal J1 §3.4): C1 client
/// search-or-create → service → create. Time + artist come from the cell.
export function QuickCreatePopover({
  providerId,
  profile,
  artistId,
  dateTimeIso,
  onClose,
  onCreated,
  onToast,
}: {
  providerId: string;
  profile: ProProfile;
  artistId: string;
  dateTimeIso: string;
  onClose: () => void;
  onCreated: () => void;
  onToast: (msg: string) => void;
}) {
  const services = profile.provider.services ?? [];
  const [query, setQuery] = useState('');
  const [matches, setMatches] = useState<SalonClientListItem[]>([]);
  const [picked, setPicked] = useState<{ name: string; phone?: string } | null>(
    null,
  );
  const [newPhone, setNewPhone] = useState('');
  const [serviceId, setServiceId] = useState(services[0]?.id ?? '');
  const [busy, setBusy] = useState(false);

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

  async function create() {
    if (!serviceId) return;
    setBusy(true);
    const name = picked?.name ?? query.trim();
    const phone = picked?.phone ?? (newPhone.trim() || undefined);
    const r = await createManualBooking(providerId, {
      serviceIds: [serviceId],
      appointmentDateTime: dateTimeIso,
      artistId: artistId || undefined,
      clientName: name || undefined,
      clientPhone: phone,
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
        className="w-full max-w-sm rounded-xl border border-border bg-secondary p-l"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="text-lg font-semibold text-textPrimary">
          Nouveau rendez-vous
        </h2>
        <p className="mt-xs text-sm text-textSecondary">
          {formatDateTimeFr(dateTimeIso)}
        </p>

        {/* Client search-or-create */}
        {picked ? (
          <div className="mt-m flex items-center justify-between rounded-lg bg-surface p-s text-sm">
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
          <div className="mt-m">
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

        {/* Service */}
        <label className="mt-m block text-sm text-textSecondary">
          Prestation
          <select
            value={serviceId}
            onChange={(e) => setServiceId(e.target.value)}
            className="mt-xs w-full rounded-lg border border-border bg-surface px-m py-s text-sm text-textPrimary"
          >
            {services.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name} — {formatFcfa(s.price ?? 0)}
              </option>
            ))}
          </select>
        </label>

        <div className="mt-l flex justify-end gap-s">
          <Button variant="secondary" onClick={onClose} disabled={busy}>
            Annuler
          </Button>
          <Button
            onClick={create}
            disabled={busy || !serviceId || (!picked && query.trim().length < 1)}
          >
            Créer
          </Button>
        </div>
      </div>
    </div>
  );
}
