'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import {
  type Appointment,
  canReschedule,
  statusLabelFr,
} from '../../lib/account/appointments';
import { canReview } from '../../lib/account/extras';
import { listAppointments } from '../../lib/api/account';
import { formatDateTimeFr } from '../../lib/format';

/// « Vos rendez-vous ici » (parity 2.7) + the review invite (2.8): the
/// signed-in client's bookings AT THIS salon, on the public salon page.
/// One session probe on mount — anonymous 401 renders nothing (the
/// HeaderBell pattern).
export function SalonVisitsCard({ providerId }: { providerId: string }) {
  const [items, setItems] = useState<Appointment[] | null>(null);

  useEffect(() => {
    let active = true;
    listAppointments().then((r) => {
      if (!active || r.status !== 200) return;
      setItems(r.items.filter((a) => a.providerId === providerId));
    });
    return () => {
      active = false;
    };
  }, [providerId]);

  if (!items || items.length === 0) return null;

  const upcoming = items
    .filter(canReschedule)
    .sort((a, b) => a.appointmentDate.localeCompare(b.appointmentDate));
  // The latest reviewable completed visit → its detail hosts the ReviewForm.
  const reviewable = items
    .filter((a) => canReview(a.status))
    .sort((a, b) => b.appointmentDate.localeCompare(a.appointmentDate))[0];

  if (upcoming.length === 0 && !reviewable) return null;

  return (
    <section className="px-m py-l">
      <div className="rounded-xl border border-border bg-secondary p-m">
        <div className="flex items-center justify-between gap-m">
          <h2 className="text-lg font-semibold text-textPrimary">
            Vos rendez-vous ici
          </h2>
          <Link href="/mon-compte" className="text-sm text-textPrimary underline">
            Voir tout
          </Link>
        </div>
        {upcoming.length > 0 ? (
          <ul className="mt-s space-y-xs">
            {upcoming.slice(0, 3).map((a) => (
              <li key={a.id}>
                <Link
                  href={`/mon-compte/${a.id}`}
                  className="flex items-center justify-between gap-m rounded-lg bg-surface px-m py-s text-sm hover:bg-surfaceVariant"
                >
                  <span className="text-textPrimary">
                    {formatDateTimeFr(a.appointmentDate)}
                  </span>
                  <span className="text-textTertiary">
                    {statusLabelFr(a.status)}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        ) : null}
        {reviewable ? (
          <div className="mt-s">
            <Link
              href={`/mon-compte/${reviewable.id}`}
              className="inline-flex items-center justify-center rounded-lg bg-primary px-l py-s text-sm font-medium text-secondary hover:bg-primaryLight"
            >
              Donner votre avis
            </Link>
          </div>
        ) : null}
      </div>
    </section>
  );
}
