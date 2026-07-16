# web-b4-controls — the focus ring, `<TextField>`, and the 48px floor (B4)

**Status:** Built (2026-07-17). **Surface:** `web/` · every form + control.
**Design system:** [WEB-SYSTEM.md §5–§6, §10](WEB-SYSTEM.md#5-focus--keyboard) ·
[SYSTEM.md §13.2, §14](SYSTEM.md#14-forms--validation). **Roadmap:** design-system
programme, slice B4 (register rows 3 · 8 · 9 · 10 · 11 · 7h).

## Goal & the debt

Every measured number is zero or failing: `focus-visible:` = **0** across 180
buttons + ~105 real controls (93 literal + the ~12 rendered inside the 6 phone
widgets); `htmlFor`/`id`-on-controls/`aria-invalid`/`aria-describedby` = **0** —
no error in the app is programmatically tied to its field; every text input wears
the decorative `border-border` (1.44:1) instead of §3.3's mandatory `borderStrong`;
and **not one control reaches §13.2's 48px** (`Button` — every button — is 36px;
the glyph floor is 16px). The register's own root cause: seven-plus ad-hoc input
copies and zero shared primitives. B4 ships the primitive, the ring, and the floor,
and migrates everything.

One token blocks it all: **`borderFocus` does not exist on web** (the sixth mirror
drift — mobile has it at `colors.dart:68`; WEB-SYSTEM §1 promises it; §5's own CSS
snippet consumes it and would fail the build). It lands first.

## UX & the states

**The focus ring (§5, one base rule):** `:focus-visible` → 2px solid `borderFocus`,
offset 2px, radius `md`. Keyboard-only by trigger; a clicked *button* shows nothing
(browsers legitimately show it on clicked *text fields* — recorded, not fought).
A "Aller au contenu" skip link is the first focusable element (in `app/layout.tsx`,
`sr-only focus:not-sr-only`, jumping to the layout's `#contenu` wrapper — `<main>`
lives per-page in 14 files, so the layout wrapper is the one-edit target and covers
the pro shell too).

**`<TextField>` anatomy (§6) — the mobile `InputDecorationTheme`, ported:**

| State | Border | Extra |
|---|---|---|
| enabled | `borderStrong` 1px | |
| focused | `borderFocus` 1px + `ring-1` `borderFocus` | the ring fakes mobile's 2nd px outside the border-box — zero layout shift |
| error | `error` 1px | `<p role="alert">` in `bodySmall`/`error` under the field, persists until fixed |
| focused+error | `error` 1px + `ring-1` `error` | |
| disabled | soft `border`, `textDisabled` | recedes below enabled — §3.3 |

Radius `lg` (12). Padding `p-m` (mobile's symmetric `spacingM` — fields grow
~38→~54px; that *is* the parity fix). `min-h-12` floor. Label above in
`labelMedium`/`textSecondary` (`hideLabel` renders it `sr-only` for the hero search
and date/time cells where the design has no visible label — the accessible name
stays). Hint in `bodyMedium`/`textTertiary`. `aria-describedby` = error id then
hint id. `useId` fallback. `multiline` renders a textarea. No `forwardRef` (zero
callers ref a text input today; adding it later is compatible).

**Copy rules (§14):** French, actionable ("Saisissez une adresse e-mail valide.",
"Le numéro doit comporter 10 chiffres"); optional fields suffix the label
`(optionnel/le)` — 10 mobile precedents; required is unmarked. A placeholder is
never the label: it survives only as a *format example* ("07 00 00 00 00") or an
"Ex : …" hint; "Votre e-mail" dies, "Code à 6 chiffres" becomes the label.

**Validation flow (§14 rules 1–6):** validate on submit; re-validate on change once
a field has errored (`lib/forms/useFieldErrors.ts`, ~20 lines, adopted in the
funnels as the reference implementation). Submit is disabled only while submitting —
the funnels' current `disabled={busy || !emailValid}` is a rule-5 violation this
slice fixes. Field faults render under the field; outcome messages ("Connexion
impossible — réessayez") stay form-level (their announcements are B5's).

**`Button`:** `min-h-12` (mobile A3's `Size(0, 48)` — a height floor, width from
container); new `text` variant (`textPrimary` ink + `hover:bg-surfaceVariant` —
deliberately not mobile's `primary` foreground, per §1's ink/brand split); new
`isLoading` (disabled + `aria-busy`, children `text-transparent` — not `invisible`,
which strips the accessible name — with an absolute-centered `border-current`
spinner: constant size, no layout jump).

**Tap targets (§13.2, row 7h):** every control ≥48px. Bordered boxes and pills grow
visibly (Lightbox ✕ → 48 pill; MediasClient IconBtn → 48; chips 28→48 — A4a's own
pills→48 precedent; ReviewForm's stars 24→48 each, `gap-xs`→`gap-s` fixing their
4px adjacency violation). Tight-layout glyphs expand invisibly — padding +
negative margin, −(48−box)/2, all on the rhythm scale (ProSidebar/JournalPanel/
EquipeClient/AppInstallBanner ✕s, HeaderBell, hamburger, "Mon compte"). The
absolute photo-✕ badges get a 48px wrapper at a compensated offset (a visible 48px
box would cover the thumbnail). The switch keeps its 44×24 track as an inner
`<span>`; its `<button>` becomes the 48px transparent target, labelled by the row
title (`aria-labelledby`). MonthCalendar cells: `min-h-12` height floor; width
stays grid-bound (~43px at 375) — recorded in the register, not hidden. 20px
text-links become `<Button variant="text">`.

## Architecture & patterns

`web/components/TextField.tsx` (new) · `Button.tsx` (rebuild, API-compatible) ·
`PhoneField.tsx` (gains the same label/hint/error shell; react-phone-number-input
forwards rest props to its inner input, so `id`/`aria-*` pass through — measured;
the two raw `<PhoneInput>`s migrate to it). `.myweli-phone` CSS is keep-and-fix:
`borderStrong` border, `borderFocus` focus + 48px min-height — and the
country-select ring **must stay CSS** (the select is an opacity-0 overlay; the
global outline is invisible on it). Role-picker rows gain `aria-pressed`. Selects
get `min-h-12` + `borderStrong` + real label wiring (no Select primitive — §10
specs none). File inputs keep the hidden+label FilePick pattern.

## Testing plan

Unit (`tests/textfield.test.tsx`, `tests/button.test.tsx`): label association,
aria-invalid, describedby chaining + id resolution, useId fallback, multiline,
disabled; variants, isLoading semantics. E2e: `focus.spec.ts` (skip link + ring
computed styles + no-ring-on-clicked-button + funnel error association) and
`tap-targets.spec.ts` (the row-7h pin: `boundingBox()` ≥ 48 over the control
table + star adjacency ≥8px) — both proven red first. jsx-a11y strict lands with
the fixes: branch-base proof-red = **16 errors / 5 rules** (recorded); target =
0 errors, **0 disables** (`label-has-associated-control` configured `{depth: 25}`
— three of the 16 are its depth-2 false positives; three more are
`img-redundant-alt` catching French "Photo" alts). Test lockstep: placeholder
queries become `getByLabelText`; accessible names stay stable elsewhere.

## What the adversarial review corrected (recorded, per the register's own rule)

The sweep's first "row 7h → 0 remaining" claim was **false**. The review measured:
a **behavioural bug** — `useFieldErrors.validate()` replaced the whole error map,
so a step-2 submit wiped a still-unfixed step-1 error *and the submit fired with
the empty value* (now **merge** semantics; ProRegister validates each path's full
subset); **four adjacency violations the sweep itself created** with two-sided
negative margins (banner ✕/bell/hamburger abutting neighbours at 0–4px — now
one-sided); MediasClient's 3×48 IconBtn row (160px) **overflowing its 155px card**
at 375px (now 1-col base / `sm:2` / `lg:3` + a wrapping footer); and a long tail
of sub-48 controls the sweep never reached — the header logo and « MyWeli Pro »
wordmark links (28px), sidebar nav links (36px at a 4px stride), the salon
switcher, ManualBookingDialog's rows and « Changer », ClientCardClient's tag
pills/tel links/« Supprimer », DayHoursEditor's « Travaille » rows — all floored,
the new ones pinned in `tap-targets.spec.ts`. The spec's own EquipeClient ⋯ guard
was **vacuous** (the stub seeds no second member) and is replaced with hard
asserts on controls that exist. In passing: `OtpLoginForm` has zero callers
(register row 16); the hidden-file-input FilePick is keyboard-inaccessible
(register row 22, B5); `Button isLoading` documents its plain-children constraint
(`text-transparent` doesn't cascade past a child's own `text-*` class).

## Not in scope (B5's)

Toast/`aria-live` · Modal focus-trap · the `/recherche` heading fix · the
route-level axe run. The field-level `role="alert"` is B4's; page-level live
regions are B5's.

## Definition of done

Rows 3, 8, 9, 10, 11, 7h → 0 with measured counts · jsx-a11y strict green with
zero disables · every form still submits (full vitest + e2e green) · the four
states intact on touched forms · French copy · ROADMAP + WEB-SYSTEM refreshed in
the same PR · adversarial review passed.
