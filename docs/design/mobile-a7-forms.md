# mobile-a7-forms — an error belongs to its field, not to a toast (A7)

**Status:** In progress (2026-07-26). **Surface:** `mobile/` — every screen and
sheet that collects input and can reject it, across consumer · pro · admin.
**Design system:** [SYSTEM.md §14](SYSTEM.md#14-forms--validation) ·
[§11.1](SYSTEM.md#11-components) · [§13.1/§13.3/§13.5](SYSTEM.md#13-accessibility) ·
[§20](SYSTEM.md#20-enforcement) · [§21](SYSTEM.md#21-the-known-violations-register)
row 19. **Twin:** [web-b4-controls.md](web-b4-controls.md) (the web settled this
design in B4 — `useFieldErrors` + `TextField`). **Roadmap:** design-system
programme, mobile A-series slice A7.

## Goal & the debt

§14 opens with the rule and then admits the product ignores it: *"`AppTextField`
exposes `errorText` and exactly **one caller in the entire codebase** passes
it — so the de-facto validation pattern is 'throw a red snackbar.'"* It names
the cost precisely: the message disappears on a timer, it never says *which*
field is wrong, and a screen reader never associates it with the input.

A6 is what makes this affordable. Before it, validation feedback was scattered
across 117 hand-rolled snackbar calls; now every one routes through a single
`AppSnackBar`, so the census is a grep rather than an archaeology dig.

## ⚠️ The census disproved the register row — in the direction that matters

Row 19 reads: *"**1** caller passes `errorText` | validation = 'throw a red
toast'"*. Measured at base (`49d406a`), **both halves are wrong**.

**"1 caller" is numerically right and practically zero.** The single `errorText`
site is `invite_member_sheet.dart:191`. `_emailError` is assigned only inside
`_continueFromEmail()` (`:73–75`) — and that method can only run when
`_emailValid` is already true, because the button that calls it is gated
`onPressed: _emailValid ? _continueFromEmail : null` (`:198`). The assignment is
unreachable. **The product has zero working field-anchored errors, not one.**

**"validation = throw a red toast" is materially false.** Only **4**
client-side validation snackbars fire on a live screen:

| # | Site | Copy |
|---|---|---|
| 1 | `pro_manual_booking_screen.dart:119` | « Choisissez une date et une heure à venir » |
| 2 | `pro_register_screen.dart:80` | « Le numéro de téléphone du salon est requis » |
| 3 | `pro_salon_profile_screen.dart:157` | « Le nom est requis » |
| 4 | `availability_screen.dart:628` | « L'heure de fin doit être après l'heure de début » |

Four more (`booking_hub:348/353`, `service_selection:67`, `date_time:149`) are
**dead code** — the same condition already disables the button. The dominant
pattern is not the toast at all:

| Surface | Count |
|---|---|
| **Silent disabled button** | **22** |
| Hand-rolled red `Text` block | 10 |
| `InlineFeedback` (A6, correct) | 4 |
| Validation snackbar, live | 4 |
| Validation snackbar, dead | 4 |
| `errorText` | 1 (dead) |
| Dialog | 0 |

**A slice built on the register's framing would have hunted toasts that mostly
aren't there and missed all 22 rule-5 violations.** The register is corrected in
the same PR.

**And it is not greenfield.** 5 live screens already run Flutter's
`Form`/`validator` with **13** validators — so mobile ships two competing
mechanisms, and §14 names only one of them.

## The correctness bugs under the presentation debt

The census found that "where the error renders" was hiding "whether the rule is
even right". Owner decision: fix these here.

| Bug | Evidence |
|---|---|
| **5 independent e-mail regexes** | `Validators.email` (strict) + the same loose `^[^@\s]+@[^@\s]+\.[^@\s]+$` copy-pasted at `login_screen:42`, `pro_register:47`, `pro_login:60`, `invite_member_sheet:51`. Two definitions of "valid e-mail" ship in one app |
| **The OTP gate accepts 4 digits** | `login_screen:282`, `pro_login:352`, `pro_register:354` gate on `length < 4` — on a field labelled « Code à 6 chiffres » with `maxLength: 6`. `Validators.otp` says 6 and has no callers |
| **The Mobile Money number is unvalidated** | `deposit_settings_screen.dart:321` — the field that decides where deposits land |
| **Two `PhoneNumberField`s can never validate** | `login_screen:331`, `client_list_screen:373` sit outside any `Form`, so the package's own validator never runs |
| **`Validators.phoneNumber` / `.otp` / `.required`** | zero callers; 7 inline `required` duplicates instead |
| **`errorMaxLines` defaults to 1** | `inputDecorationTheme` defines the error *borders* but never bounded the error TEXT, so every §17-compliant French sentence is amputated mid-instruction — a §13.3 failure at 200 % |

## Why not the SDK

`AutovalidateMode.onUserInteraction` is **not** §14 rule 2. It validates on every
change once the field is touched — it yells « email invalide » at `s@`, the
exact behaviour rule 2 forbids. `AutovalidateMode.onUnfocus` is blur-based, also
not rule 2. `FormState.validate()` returns a bare `bool`: no per-field map, no
subset scoping, and **no way to attach a server fault to a field**, so « Code
incorrect » has no route under the code field.

The two mechanisms also collide silently. In `TextFormField`, a `validator`
result **overwrites** `decoration.errorText`
(`text_form_field.dart:218-221`) — so a server error pinned to a field is erased
the moment the form re-validates. Keeping both is not a compromise, it is a bug.

## The components

### `FieldErrors` — `mobile/lib/core/forms/field_errors.dart`

A port of web's `useFieldErrors`, and **deliberately not a `ChangeNotifier`**:
form-error state is ephemeral and screen-local, a notifier buys nothing, and it
would add ~30 `dispose()` obligations to a codebase where A6 found 3 leaked
controllers. Callers mutate inside `setState` — the idiom `otp_verify_screen`
already uses. The payoff is that the semantics are pure, so they get the real
unit test the web version never had.

```dart
typedef FieldValidator = String? Function(String value);

class FieldErrors {
  FieldErrors(this._validators);
  String? operator [](String key);
  bool get isEmpty;
  String? get firstErroredKey;          // the focus move, below

  bool validate(Map<String, String> values);  // submit: subset-scoped, MERGES
  void revalidate(String key, String value);  // rule 2: only if already errored
  void set(String key, String? message);      // a server fault → its field
  void clear();
}
```

**Merge, not replace, is the load-bearing detail.** Web shipped replace first;
its adversarial review proved a step-2 submit wiped a still-unfixed step-1 error
**and then submitted the empty value**. Subset scoping is the other half: a
multi-step form must not fail fields the user has never seen.

### `Validators` — `mobile/lib/core/utils/validators.dart`, made canonical

5 statics, 2 callers today. It absorbs the duplicates and becomes the only
definition of each concept: one e-mail rule, `otp` = 6 digits everywhere, a real
phone format for the four unvalidated fields, `required` replacing its 7 inline
copies. Every inline regex dies with it.

### `AppTextField` — `mobile/lib/widgets/common/app_text_field.dart`

- **gains** `focusNode` — it has none today, and the focus move needs one.
- **loses** `validator` — the forcing function that migrates the 5 `Form`
  screens, kills the override footgun, and makes the pin a one-liner.
- `errorText` is unchanged; §11.1 already calls it *"the contract for
  validation"*.

### `inputDecorationTheme` — `mobile/lib/core/theme/app_theme.dart`

Gains **`errorMaxLines: 3`**, and nothing else.

**A correction to this spec's own first draft.** It claimed the error text was
"the one style in this theme with no token behind it" and added an `errorStyle`
to fix that. Then the gate written to hold the change stayed green when the
change was removed — theatre — so the style was measured directly: **byte for
byte identical** with and without (`Roboto/12.0/#8B0000/1.333/0.4/w400`). A3's
full `ColorScheme.error` and `textTheme.bodySmall` already resolve to exactly
it. The `errorStyle` was deleted; dead configuration that agrees with its own
default is a comment pretending to be a decision. Only `errorMaxLines` was ever
real, and its gate goes red when it is removed.

## The three amendments §14 gains

1. **The rule-5 exception.** A6's `ConfirmDialog` disables its confirm until the
   reason is typed or the confirm word matches. That is §15's destructive
   ladder — deliberate friction — not form validation. §14 says so explicitly,
   so the two sections stop contradicting each other on paper.
2. **Focus follows the first error.** §13.5 covers focus on open and return on
   close, and is silent on submit. Under strict rule 5 an always-tappable button
   can produce an error the user never sees, so a failed submit scrolls the
   first errored field into view and focuses it.
3. **The three-slot boundary**, because `invite_member_sheet` is currently the
   only file that uses two of them:

| Slot | Widget | Owns |
|---|---|---|
| field fault | `AppTextField.errorText` | "this input is wrong" — persists until fixed |
| form / in-modal outcome | `InlineFeedback` (A6) | « Connexion impossible » · anything inside a sheet, where §15 proved a snackbar is pruned by `ModalBarrier` |
| screen outcome | `AppSnackBar` | §14 rule 3 — the outcome, never a field fault |

## Server errors that belong to a field

Ten sites raise a server message as a bar when it names one field. The sharpest:
`client_list_screen.dart:86` shows « Ce numéro existe déjà. » **on the list
screen, after the sheet has already popped** — the field it describes is gone.

## Errors that genuinely cannot be field-anchored (recorded, staying non-field)

Plan/entitlement failures (`reseau_required`, `salon_limit`, `offer_required`) ·
session-level notices (the revoked-access banner) · asset-upload failures (the
owner is a file picker) · post-dismissal outcomes (all 10 admin
`showReasonDialog` sites answer after the dialog is closed) · whole-record
writes with no single owning field (availability, notification preferences) ·
device/OS failures (geolocation, "no navigation app") · optimistic actions with
undo, which are §15's snackbar by design.

## Tests & gates

§20's rule→gate table has **no row for §14** — forms are the one section of the
design system with zero enforcement, which is why row 19 never moved. A7 gives
it its first.

A grep-pin cannot see "this snackbar carries a field fault", because §14 rule 3
*permits* outcome bars. So the enforcement is shaped differently from A6's usage
pins:

- **Pins, red measured at base (`49d406a`):** `validator:` **13** → 0 outside
  `AppTextField` · inline e-mail regex **5** → 0.
- **Unit:** `FieldErrors` merge / subset / `set()` / silent-until-errored — the
  merge case is a direct port of the bug web shipped. `Validators` gets its
  first coverage.
- **Behavioural, per funnel:** submit invalid → the message renders **under the
  field** *and* **no `SnackBar` exists in the tree**. This is the rule 3 gate no
  regex can express.
- **Rule 5:** submit is enabled on an empty form, and pressing it produces a
  field error rather than nothing.
- **a11y:** the errored field survives `TextScaler.linear(2.0)` without overflow
  (what `errorMaxLines` fixes — nothing in `test/a11y/` currently pumps an
  *input*), and the message is reachable in the field's semantics via
  `containsSemantics`, mirroring `feedback_test.dart`'s live-region proof.
  **Not** `SemanticsService`: A6 proved `supportsAnnounce` is false on Android.
- **Golden:** `components_inputs` already photographs an error row and its own
  doc comment calls it the spec image for this register row; it gains
  errored+focused and a two-line message.

Known casualty, moving in lockstep: `invite_member_sheet_test.dart:150-164`
asserts the disabled button — the exact anti-pattern rule 5 forbids.

## Not in scope (recorded)

- **Server-side validation** — the client never becomes the authority; every
  rule here is a courtesy that the API re-checks.
- **Row 29 (no `flutter_localizations`)** — `TextFormField`'s `maxLength`
  counter and every Material default still render in English. Its own slice.
- **Rows 8/20 (motion)** — renumbered to A8 by this PR, not built by it.

## Definition of done

Row 19 → **0** with both pins green and their red recorded · every field fault
under its field, persisting until fixed · rule 2 honoured (silent until submit,
live once errored) · all 22 rule-5 gates tappable and answering · focus follows
the first error · one `Validators` with one rule per concept · the §14
amendments written into SYSTEM.md · §20 gains its first §14 row · §11.1
un-staled · goldens regenerated on Linux and eye-reviewed · full battery green ·
adversarial review passed · §21 + ROADMAP refreshed in the same PR.
