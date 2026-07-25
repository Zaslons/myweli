# mobile-a6-feedback — one `AppSnackBar`, one `ConfirmDialog`, and the confirm ladder (A6)

**Status:** In progress (2026-07-25). **Surface:** `mobile/` — every snackbar
call site and every `AlertDialog`, across consumer · pro · admin. **Design
system:** [SYSTEM.md §15](SYSTEM.md#15-feedback--destructive-actions) ·
[§11.3](SYSTEM.md#11-components) · [§13.4/§13.6](SYSTEM.md#13-accessibility) ·
[§21](SYSTEM.md#21-the-known-violations-register) rows 17 & 18. **Twin:**
[web-b5-feedback.md](web-b5-feedback.md) (the web did this in B5 — Toast +
Modal). **Roadmap:** design-system programme, mobile A-series slice A6.

## Goal & the debt

§15 opens on the honest state: *"That is the whole feedback layer of the app,
unmanaged."*

- **Row 17** — 118 `showSnackBar` tokens (117 real calls): **73 raw inline**, 38
  through a captured `messenger`, **6** through `Helpers.showSnackBar`, and
  exactly **one** with an action.
- **Row 18** — **11** copy-pasted `showDialog<bool>` confirmations.

**Both counts are exactly right** — the first register rows a census has not
disproven. What the counts hide is the slice:

1. **Every duration violates §15.** Measured: `2s` ×15, `1s` ×4, and Material's
   `4s` default ×99. §15 specifies **3s / 3s / 6s / 10s** — *no site anywhere
   uses any of them*, including the single action-bearing snackbar (§15 wants
   10 s; it runs at the 4 s default).
2. **Tone is arbitrary.** Only **7 of 31** successes carry `success`; **30 of
   61** errors are not `error`. « Rendez-vous annulé » is green;
   « Rendez-vous accepté » is ink. Same product, same verb class.
3. **Dialogs were never touched by the a11y tranche** (A4b/A4c): zero
   `Semantics`, zero `barrierLabel`, zero focus restoration, and
   **cancel-gets-focus 0 of 11** — mandated by §15 *and* §13.5. The a11y suite
   never opens a dialog.
4. **§15's ladder is unimplemented at both ends.** ZERO undo affordances exist
   (the one `SnackBarAction` is a *navigation* link). `pro_photos_screen` is the
   archetype: confirm a photo delete and it vanishes **silently** — no snackbar,
   no undo, nothing to announce.

## ⚠️ The census's headline was WRONG — and the correction improves the outcome

I reported "~107 snackbars are silent to screen readers, because only 6 of 117
calls reach the announcing helper." **That is false.** Verified in the SDK:

- `packages/flutter/lib/src/material/snack_bar.dart:831-833` wraps **every**
  `SnackBar` in `Semantics(container: true, liveRegion: true, …)`. A live region
  announces automatically on both platforms.
- `sky_engine/lib/ui/window.dart:986` — `supportsAnnounce` is a real feature
  flag, **false on Android**, where the platform discourages direct
  announcements in favour of `liveRegion`.
- `semantics_service.dart:51-56` — `SemanticsService.announce` is
  `@Deprecated` after v3.35 (the app already migrated to `sendAnnouncement`).

So the **6 sites that add an announcement are the anomaly**, not the 111 that
don't: on Android a direct announcement clears TalkBack's speech queue; on iOS
it double-speaks text the live region already carries.

**A6 therefore does the opposite of what the census implied**: `AppSnackBar`
adds **no** `SemanticsService`, the a11y gate *proves the live region* instead,
and the redundant announcements beside snackbars are **deleted**.
`Helpers.announce` survives for genuinely off-focus non-snackbar events (the map
sheet's favourite, pull-to-refresh) — that is A4c's territory, untouched. The
reversal is recorded in §21 row 14's note.

## Two §15 amendments this slice lands

Doctrine changes, written into SYSTEM.md — not silent exceptions:

1. **The kind needs a second cue (§13.6).** `AppColors.success` (#2D5016,
   relative luminance **0.072**) and `AppColors.error` (#8B0000, **0.062**) are
   *indistinguishable in greyscale* — §13.6's own test ("screenshot it in
   greyscale; if you lose information, it's a bug"), and the same failure A4b
   fixed on the story ring. `AppSnackBar` renders a **leading kind icon**
   (`check_circle_outline` / `info_outline` / `error_outline`,
   `excludeFromSemantics` — the text carries the meaning). Colour + glyph = two
   cues.
2. **The 10 s rule is over-broad** (owner decision). §15 says "with action →
   10 s". But a favourite toggle fires on a tap users make constantly, and **the
   heart icon is already a one-tap undo** — a 10-second bar would occlude the
   screen on every tap. Amended: **10 s when the snackbar is the ONLY route
   back** (a deleted photo); the kind's own duration when the UI itself is the
   undo.

## The third finding: a snackbar under a sheet is invisible AND unreachable

The web's B5 review found `aria-modal` pruning toasts from the a11y tree. The
mobile analogue is real and worse: `modal_barrier.dart:264` returns
`BlockSemantics(child: ExcludeSemantics(…))`, so a snackbar fired while a
`showModalBottomSheet` / `showDialog` is open is **pruned from the semantics
tree** *and* **painted under the scrim** — the latter also violating §10
("nothing may be painted above a dialog except feedback").

Measured sites: `deposit_payment_sheet:180,188` · `submit_review_sheet:74` ·
`commune_picker_sheet:108` (×4 callers) · `salon_picker_sheet:188` ·
`invite_member_sheet`. **These become inline in-sheet errors**, mirroring what
B5 did when `ManualBookingDialog`'s `onToast` died.
(`submit_review_sheet:131`'s success fires *after* `Navigator.pop` — correct as
a snackbar, untouched.)

## The components

### `AppSnackBar` — `mobile/lib/widgets/common/app_snack_bar.dart`

An `abstract final class` (the SDK's own idiom for `SemanticsService`), so the
pin has one grep-able name. **Durations live on the enum**, mirroring web B5
where the hook — not the token file — owns them: §15's 3/6/10 s are *dismiss
timeouts*, not §9 motion curves, so A6 has **no ordering dependency on A9**.

- `enum SnackKind { success, info, error }` carrying `(color, icon, duration)`.
- `show(context, message, {kind, action})` — the ergonomic form.
- **`showOn(messenger, message, {kind, action})`** — the primitive. The 38 sites
  that capture `ScaffoldMessengerState` *before* an await are doing it right; a
  `BuildContext`-only API would regress them.
- **`outcome/outcomeOn({required ok, required success, required error})`** — the
  18 dual-outcome sites (`ok ? successMsg : errorMsg`), so the tone can no
  longer be got wrong.
- `removeCurrentSnackBar` before each show: the newest message wins instead of
  queueing behind a 6 s error (web B5's "re-show resets the timer").
- Chrome comes from `snackBarTheme` (A3). The component adds only what a
  `ThemeData` cannot express: the per-kind **colour** and **duration**.
- The stray `margin` inside `Helpers.showSnackBar` is **dropped**, not promoted:
  the other 111 sites already render M3's default inset.
- `AppColors.info` stays deliberately unused — §15 says info = `textPrimary`,
  which is also the theme background, so the 70 colourless sites render
  byte-identically after the sweep.

### `ConfirmDialog` — `mobile/lib/widgets/common/confirm_dialog.dart`

One `StatefulWidget`, **two** show functions so a caption prompt doesn't
announce itself as a destructive confirm:
`showConfirmDialog(…) → bool` and `showInputDialog(…, field) → String?`.

Params: `title` · `message` **XOR** `content` (the rich deposit-forfeit callout
in `appointment_detail_screen`) · `icon` (icon-in-title) · `confirmLabel` (a
**verb**) · `cancelLabel` · `isDestructive` · `field`
(hint/required/maxLength — autofocused) · `confirmWord` (type-to-confirm).

**Cancel gets focus** via `autofocus: true` on the cancel `TextButton` —
correct because `ButtonStyleButton` exposes `autofocus` and the `DialogRoute`'s
own `FocusScope` resolves it on the first frame. *Not* a `requestFocus` in
`initState`, which races the scope attachment and lands intermittently. Touch
users see no ring (`FocusManager.highlightStrategy` is `automatic`); keyboard,
switch-access and external-keyboard users land on « Annuler ». A dialog **with a
field** gives focus to the field instead — you cannot proceed without typing,
which is the same doctrine expressed by the friction itself.

The dialog **owns its controller** ⇒ the 3 leaks die. Cancel-first order stays
(11/11 today; §15's "never place the destructive action where OK usually sits"
is satisfied by label + colour, and reordering would break 5 tests' tap targets
for no doctrinal gain).

**`showReasonDialog` re-bases onto it** as a ~6-line delegation — same name,
same params, same `Future<String?>`, so the 9 admin call sites don't change —
plus one optional `isDestructive` so « Bannir » / « Suspendre » / « Rejeter »
get their `error` confirm and row 18 closes without an asterisk.

## The ladder, applied (all 13 `AlertDialog` sites)

`AlertDialog(` appears **exactly 13×**: the 11 counted confirms + the admin's
`showReasonDialog` + the before/after caption prompt. Every other `showDialog`
is `<void>` (6 lightboxes) or the admin `<int>` month picker — out of scope.

| Rung | Sites | Treatment |
|---|---|---|
| Reversible | favourites (3), mark-all-read | **No dialog.** Act + Undo in the snackbar (§15). |
| Hard to undo | booking cancel · revoke access · delete photo / pair / service / employee · no-show · report review · logout · caption | `ConfirmDialog`: name the thing, **state the consequence**, verb button. |
| Irreversible + high-value | consumer account delete · **pro salon delete** | `ConfirmDialog` + **type-to-confirm**. |

**Destructive vs not — classified explicitly** (the "exclusion list is part of
the row" pattern): destructive ⇒ `error` confirm (the deletes, revoke, cancel,
and the ~6 admin ban/suspend/reject/hide actions). **Deliberately NOT
destructive, recorded**: logout (reversible — log back in), report-a-review
(nothing of the user's is destroyed), no-show (a state change), the caption
prompt. Forcing those red would dilute the signal.

**Verb labels + consequence sentences**: today 4/11 have verb labels and 2
dialogs are title-only with no consequence (`pro_photos`, `pro_before_after`).
Both gain a sentence; « Supprimer » becomes « Supprimer la photo », « Oui,
annuler » becomes « Annuler le rendez-vous ».

**Type-to-confirm asymmetry closed**: the consumer account delete guards with
« SUPPRIMER »; the **pro salon delete does not**, despite the identical damage
class. It gains one.

## Fixed as a by-product (not follow-up rows)

- **4 dialogs skip `mounted`** between the dialog and the mutation
  (`appointment_detail:192`, `pro_before_after:114`, `pro_photos:76`,
  `team_screen:458`) — each conversion also adopts the captured-messenger idiom.
- **3 `TextEditingController`s never disposed** — the dialog owns them now.

## Tests & gates

- **`app_snack_bar_test`** — kind → colour/duration/icon; a **behavioural**
  duration assertion (alive at 5.9 s, gone at 6.1 s — a field assertion alone
  can be overridden by the messenger); action ⇒ 10 s and tapping it closes the
  bar; **replace-not-queue**.
- **`a11y/feedback_test`** — `containsSemantics(isLiveRegion: true, label: …)`
  on the real SnackBar (the mechanism proof that replaces the announce myth) ·
  `androidTapTargetGuideline` with an action present (the ≥48 `SnackBarAction`)
  · **the modal-blocked assertion**: a snackbar under an open sheet is absent
  from the semantics tree — the finding, gated so it can't silently return.
- **`confirm_dialog_test`** — cancel holds primary focus (and the field wins
  when present) · type-to-confirm gating incl. lowercase · required-input
  gating · returns on confirm / cancel / **barrier-dismiss** · destructive
  `foregroundColor` resolves to `error` only when destructive · the controller
  disposes.
- **The pin** (`design_system_pin_test`, + an `allow` param on `offenders`) —
  **proven red at base (`b4d3dbe`)**: `\.showSnackBar\(` **116** ·
  `SnackBar\(` **111** · `AlertDialog\(` **13** ·
  `showDialog<(?:bool|String)>` **13**. Each → 0 outside its component. Zero
  `// ds-ignore` expected.
- **Goldens**: `components_dialog` is re-baselined against the **real**
  component (today it pictures a hand-built fixture whose cancel label
  « Retour » and `ElevatedButton` confirm exist nowhere in the product);
  `components_dialog_confirm` (type-to-confirm + the *disabled* confirm — a
  state nobody has looked at) and **`components_snackbar`** (the product's
  first) are new. The snackbar golden is deterministic without `pumpAndSettle`:
  four sibling `ScaffoldMessenger`s driven through the real API, shot at 400 ms
  — after the 250 ms entrance, inside a 2.6 s window before the earliest
  dismissal.

## Not in scope (recorded)

- **Server-side undo** (un-cancel a booking) — needs new service methods → new
  §21 row.
- **No `flutter_localizations` anywhere** — zero `localizationsDelegates` /
  `supportedLocales`, so every Material default string (the modal barrier's
  semantics label, « Dismiss », dialog route names) renders in **English** under
  a §17 that says French everywhere. Verified while building the dialog → new
  §21 row, its own slice.
- The 6 `showDialog<void>` lightboxes and the admin `<int>` month picker (not
  confirms) · A9's motion tokens · row 26 (segmented borders) · row 28
  (gold-as-text).

## Definition of done

Rows 17 & 18 → **0** with the pin green and its red recorded · every snackbar on
one entry point with §15's durations and two-cue kinds · every `AlertDialog`
through `ConfirmDialog` with the ladder applied and the destructive/neutral
classification recorded · the modal-blocked sites converted and gated · undo
shipped where the snackbar is the way back · the §15 amendments written into
SYSTEM.md · goldens regenerated on Linux and eye-reviewed · full battery green ·
adversarial review passed · §21 + ROADMAP refreshed in the same PR.
