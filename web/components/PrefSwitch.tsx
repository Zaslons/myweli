'use client';

/// A preference's on/off switch — the consumer « Préférences » rows and the
/// salon's « Alertes par e-mail » (docs/design/salon-email-alerts.md §4).
/// Moved here from `account/NotificationsClient.tsx`, not copied: one switch,
/// one set of fixes (B4's target and label, B11's knob travel).
export function PrefSwitch({
  checked,
  labelledBy,
  onToggle,
}: {
  checked: boolean;
  /// The id of the row's title — a real element, not a duplicated string.
  labelledBy: string;
  onToggle: () => void;
}) {
  return (
    // §13.2: the BUTTON is the ≥48px target; the 44×24 track is the visible
    // inner span, unmoved.
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-labelledby={labelledBy}
      onClick={onToggle}
      className="flex min-h-12 min-w-12 shrink-0 items-center justify-center"
    >
      <span
        className={`relative block h-6 w-11 rounded-pill transition-colors ${
          checked ? 'bg-primary' : 'bg-border'
        }`}
      >
        <span
          // ds-ignore: the knob's travel is exact geometry, not spacing — and B11 had to
          // fix the ARITHMETIC, not just the unit. It read "track w-11 (44) − knob w-5 (20)
          // − left-0.5 (2) = 22" and wrote `left-[22px]`, but all three of those operands
          // are REM (`tailwind.config.ts` sources the sizing keys from Tailwind's default
          // scale). The sum is only 22px at a 16px root; at Chrome's "Very large" (24px)
          // the correct travel is 33 and the knob stopped a third of the way across a
          // track that had grown around it. In rem the identity holds at every root:
          // 2.75 − 1.25 − 0.125 = 1.375rem. (The switch stays hand-rolled — §10 specs no
          // Switch primitive; B4 fixed its target + label in place.)
          // eslint-disable-next-line tailwindcss/no-arbitrary-value
          className={`absolute top-0.5 h-5 w-5 rounded-pill bg-secondary shadow transition-all ${
            checked ? 'left-[1.375rem]' : 'left-0.5'
          }`}
        />
      </span>
    </button>
  );
}
