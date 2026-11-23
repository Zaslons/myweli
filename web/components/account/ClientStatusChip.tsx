import { Chip } from '../Chip';
import {
  type Appointment,
  clientStatusLabel,
  clientStatusTone,
} from '../../lib/account/appointments';

/// A client's own booking status, as the app draws it
/// (docs/design/web-account-bookings-truth.md §2.3).
///
/// **Not `StatusChip`, which the Espace pro keeps.** Two differences, both
/// client-only:
/// - the words follow the client rule: a past booking nobody confirmed reads
///   « Non confirmé », where the salon's own lists still say « En attente »;
/// - neutral is drawn `ink` (textSecondary at 10 %), the app's neutral chip
///   (`app_chip.dart`). `StatusChip`'s `neutral` is `bg-surface`, which has no
///   visible shape on the card's white (~1.04:1, `Chip.tsx`), so « Terminé »
///   and « Non confirmé » were words with no pill.
export function ClientStatusChip({
  appt,
  now,
}: {
  appt: Appointment;
  /// The page's one instant, so the tab, the chip and the summary agree.
  now: Date;
}) {
  const label = clientStatusLabel(appt, now);
  const tone = clientStatusTone(appt, now);
  return tone === 'neutral' ? (
    <Chip variant="ink">{label}</Chip>
  ) : (
    <Chip variant="tinted" tint={tone}>
      {label}
    </Chip>
  );
}
