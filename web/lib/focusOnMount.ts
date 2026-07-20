/// §7's replaced-form pattern: when a submit unmounts the whole form — and the
/// focused submit button with it — a success message mounted in its place is
/// silent (a live region must pre-exist its text) and focus drops to <body>.
/// Moving focus TO the confirmation fixes both: a newly focused element is
/// announced by AT, and the keyboard user is standing on the outcome, not
/// nowhere. Use as a callback ref on the confirmation (with tabIndex={-1}).
export function focusOnMount(el: HTMLElement | null) {
  el?.focus();
}
