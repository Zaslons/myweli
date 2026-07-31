'use client';

import { formatDateFr } from '../../lib/format';
import {
  emptyReason,
  firstBookableDay,
  formatNotice,
  lastBookableDay,
} from '../../lib/booking/window';
import { chipLinkClasses } from '../Chip';

/// Why a day offered nothing — said out loud, with a way out (A14d).
///
/// §12 requires an empty state to say WHY, and to offer the action that fixes
/// it wherever one exists. « Aucun créneau disponible » did neither: it says
/// nothing, and it implies the salon is full, which is false when the truth is
/// that the date sits outside the window the salon accepts.
///
/// **None of these offers a retry.** The request succeeded; re-asking the same
/// day can only return the same nothing. Retry belongs to the failure state,
/// which is a sibling of this one, not a variant of it.
///
/// Shared by the booking funnel and account reschedule so the same salon
/// explains itself the same way on both, and so it matches mobile's
/// `SlotPicker` word for word.
export function SlotsEmpty({
  date,
  tz,
  horizonDays,
  noticeMinutes,
  onGoToDay,
}: {
  date: string;
  tz?: string;
  horizonDays: number;
  noticeMinutes: number;
  /// Hands the host a new salon day (`YYYY-MM-DD`); the host owns the date.
  onGoToDay: (day: string) => void;
}) {
  const reason = emptyReason({ date, horizonDays, noticeMinutes, tz });

  const { title, body, action } = (() => {
    switch (reason) {
      case 'beyondHorizon': {
        const last = lastBookableDay(horizonDays, tz);
        return {
          title: 'Trop loin dans le temps',
          body: `Ce salon accepte les réservations jusqu’au ${formatDateFr(last, tz)}.`,
          action: {
            label: 'Aller au dernier jour disponible',
            day: last,
          },
        };
      }
      case 'tooSoon': {
        const first = firstBookableDay(noticeMinutes, tz);
        return {
          title: 'Réservation trop proche',
          body: `Ce salon demande un délai de ${formatNotice(noticeMinutes)} avant chaque rendez-vous.`,
          action: {
            label: 'Aller au premier jour disponible',
            day: first,
          },
        };
      }
      case 'past':
        return {
          title: 'Cette date est passée',
          body: 'Choisissez une date à venir pour voir les créneaux disponibles.',
          action: null,
        };
      case 'full':
        return {
          title: 'Aucun créneau ce jour-là',
          body: 'Ce salon n’a plus de disponibilité à cette date.',
          action: null,
        };
    }
  })();

  return (
    <div className="mt-m">
      <p className="text-bodyLarge text-textPrimary">{title}</p>
      <p className="mt-xs text-bodyMedium text-textSecondary">{body}</p>
      {action ? (
        <button
          type="button"
          onClick={() => onGoToDay(action.day)}
          className={chipLinkClasses(false) + ' mt-s'}
        >
          {action.label}
        </button>
      ) : null}
    </div>
  );
}
