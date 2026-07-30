/// The shared tab strip (B9) — WEB-SYSTEM §10.
///
/// ## Why this exists
///
/// There were **five byte-identical copies** of
/// `flex gap-s border-b border-divider` with `px-m py-s text-bodyMedium`
/// buttons — the agenda's view switcher and its status tabs, the catalogue, the
/// media library, and the account's bookings. Not five variations on a theme:
/// `grep -rn "flex gap-s border-b border-divider" web/components` returned all
/// five in one line.
///
/// **The cause is a doc gap, not carelessness.** WEB-SYSTEM §10's inventory has
/// no `Tabs` and no `SegmentedControl`, and neither was in its "to build"
/// table — the web design system said nothing whatsoever about tab controls.
/// Patching the five in place would have left that, and invited a sixth.
///
/// ## It wraps; it does not scroll
///
/// Mobile answered the same question with `isScrollable: true` (A11 C4, all
/// three bars). Web wraps, deliberately:
///
/// - a horizontal scroller has no swipe affordance with a mouse — an off-screen
///   tab is discoverable on a phone and invisible on a desktop;
/// - A11 C4 recorded that its scrollable strip put « Tous » fully off-screen at
///   200%, so every `tester.tap` needed an `ensureVisible` first. The web twin
///   of that is every Playwright `.click()` needing a scroll.
///
/// ## Not ARIA tabs, and that is a choice
///
/// Plain `<button>`s inside a `role="group"`. Real `role="tablist"` obliges APG
/// arrow-key navigation and a roving tab stop (WEB-SYSTEM row 21's radio-group
/// conversion is the precedent for what that costs) — a keyboard contract worth
/// writing deliberately, not as a side effect of an overflow fix. The `group`
/// with an `aria-label` is honest about what this is: a set of related
/// controls, named.
///
/// ## `min-h-12` is load-bearing, and the reason is a trap
///
/// All five strips were **38px** tall (`py-s` on a 20px line, plus the active
/// tab's 2px border) — 10 under §13.2's floor, while WEB-SYSTEM row 7h claimed
/// "0 remaining".
///
/// But the widest strip measured **56px** and passed a tap-target check, and it
/// passed *because it was broken*: the row needed 340px of 327, so flexbox
/// shrank the items, `min-width: auto` stopped « En attente » at its longest
/// word, the label wrapped to two lines, and `align-items: stretch` made all
/// four buttons that tall. **Fixing the overflow alone would have turned that
/// green subject red.** The floor and the wrap belong in the same change.
'use client';

export function Tabs<T extends string>({
  label,
  items,
  value,
  onChange,
  className = '',
}: {
  /// Names the group for a screen reader — « Vue de l'agenda », not "Tabs".
  label: string;
  items: readonly { key: T; label: string }[];
  value: T;
  onChange: (key: T) => void;
  /// Layout only (the caller's own top margin). Never styling.
  className?: string;
}) {
  return (
    <div
      role="group"
      aria-label={label}
      className={`flex flex-wrap gap-s border-b border-divider ${className}`}
    >
      {items.map((t) => (
        <button
          key={t.key}
          type="button"
          aria-pressed={value === t.key}
          onClick={() => onChange(t.key)}
          className={`min-h-12 px-m py-s text-bodyMedium ${
            value === t.key
              ? 'border-b-2 border-primary text-textPrimary'
              : 'text-textTertiary'
          }`}
        >
          {t.label}
        </button>
      ))}
    </div>
  );
}
