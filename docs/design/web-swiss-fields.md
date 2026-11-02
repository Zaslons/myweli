# Web — square fields and buttons, and the search as one bar (B11.6) — design spec

| | |
|---|---|
| **Status** | **Approved 2026-11-02** (decision 70): the owner chose option D, on the whole site, from pictures on the real pages. Merged in #728, on the owner's word |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-02 |
| **PRD ref / phase** | Presentation only · V1 |
| **Module** | Web, all surfaces: `styles/tokens.ts`, `styles/globals.css`, `Button`, `TextField`, `HomeSearch`, and every hand-written field and button in `app/` and `components/` |
| **Origin** | The owner, once the home page was live: « make the typing forms Swiss style ». Reverses [web-swiss-direction.md](web-swiss-direction.md) §3's « Rounded controls » |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-verification-guardrails ✓ · no backend, contract or data change |

---

## 1. Goal & scope

**Goal.** With square rules everywhere, rounded inputs had become the one thing on the page that didn't belong. What you type in or press now follows the same line.

**The rule, in one sentence: anything you type in or press is square, with a thin black line. Anything that only holds content is unchanged.**

**In scope**

| What | Change |
|---|---|
| Every field: text, e-mail, number, date, time, textarea, select, the phone field and its country box | Square, 1px black line |
| Every button and button-like link, filled or outlined, including icon buttons and calendar days | Square. An outline becomes the 1px black line |
| The search on `/` and `/recherche` | One ruled bar with no gaps (§3) |
| The focus ring | Square, like what it surrounds |

**Stays as it is, and why**

| What | Why |
|---|---|
| **Filter chips and pill choices** (`Chip`, the deposit's choices) | The owner's choice: a chip is a label you toggle, and the pill tells it apart from a button |
| **Google and Apple sign-in** (`rounded-sm`) | Each brand describes its own button, and they keep the shape they have |
| **Round icons over a photo** (the lightbox's close, the before/after handle and dots) | They sit on an image, away from any form |
| **The map's pins and controls** | They belong to the map, where a round pin is what a pin looks like |
| **A photo you press** (the gallery, its thumbnails) | It is a photo that happens to open. Photos lose their corners in the new look's own slices, S3 and S4 |
| **Agenda blocks** (`JournalGrid`, `WeekGrid`) | Appointments are content on a grid, and they are pressed as content |
| **Containers:** cards, notices, dropdown panels, photos, toasts, skeletons | Not controls. Public pages lose their boxes slice by slice in the new look's own plan; the Espace pro keeps `Card` (§8) |

**Out of scope:** any word, flow, route, API or JSON-LD. The apps stay rounded (§7).

---

## 2. The look

| State | Field | Button |
|---|---|---|
| Resting | 1px `border-primary`, no radius, background as today | Filled: black, no radius. Outlined: 1px `border-primary`, no radius |
| Hover | As today | As today |
| Focus by click | Border black, plus today's 1px ring, so two pixels with no layout shift | None, as today |
| Focus by keyboard | The same, plus the global 2px ring at a 2px offset, now square | The global ring, square |
| Error | 1px `border-error`, as today | n/a |
| Disabled | 1px `border-border`, grey text, as today | 50% opacity, as today |

**Contrast.** SYSTEM §3.3 asks an interactive boundary for at least 3:1. `borderStrong` gave 3.22:1 and black gives far more, so this only strengthens the boundary.

**The token.** `radius.control`, `0px`, declared web-only: `rounded-control` says what the thing is, the way `text-labelLarge` does. Changing it is one line, if the corners ever want 2px. `rounded-none` stays banned by the closed theme.

**It must be explicit, not left to a default.** Two reasons:
- iOS Safari can round an input the page has not squared. **Not checked on a device before the merge:** it gets looked at in the iOS simulator on the deployed site.
- The base `:focus-visible` rule gave every focused element an 8px radius, so a square field with no radius class would have rounded the moment you clicked it. That line goes (§6).

---

## 3. The search as one bar

`HomeSearch`, on `/` and `/recherche`.

| Width | Layout |
|---|---|
| Below `sm` | Service, commune and button stacked, sharing their lines, with no gaps. It saves 16px at the fold |
| From `sm` | One row: service takes what is left, commune `w-44` (`xl:w-56`), the button at the end |

**How it is drawn:** one 1px black box around the form, and `divide-*` for the lines between. The fields have no border of their own, so no negative margin is needed and no line is ever doubled.

**Focus.** The focused part rises above its neighbours (`relative`, `focus:z-dropdown`), or the black button would paint over the ring. The ring stays the global one, so `focus.spec.ts` keeps holding it.

**Other forms keep their gaps.** A sign-in form's fields have labels and error lines between them, so they cannot join.

---

## 4. States and edge cases

| Case | Behaviour |
|---|---|
| A long commune typed in the bar | Scrolls inside its field, as today |
| 320 wide | Stacked, full width. Covered by the reflow gate |
| A browser's autofill background | Fills the field's square, unchanged |
| The native `<select>` arrow | Stays the browser's. Only the box changes |
| Date and time inputs | Same box. The picker is the browser's |
| The phone field | Country box and number field stay two boxes with a gap, as a field and its label do |
| Forced-colours mode | Borders are the system's |

---

## 5. Tests

Each guard is watched red on committed work.

| Guard | Holds | Red when |
|---|---|---|
| **New: the rendered sweep** (`e2e/controls-shape.spec.ts`) | On public, booking, account and Pro pages at 375 and 1280: every visible field and button computes a 0 radius, naming the first that doesn't | `Button` goes back to `rounded-lg` |
| Same | Every visible typing field has a black line | A field keeps `border-borderStrong` |
| Same | A focused field stays square, the phone field too | A field loses `rounded-control`, so the base rule rounds it |
| Same | Chips stay pills | A chip goes square |
| Same | The bar: no gap between its parts at 375, 640 and 1280, on `/` and `/recherche` | A `gap` returns |
| Same | The focused part of the bar stacks above its neighbours | `focus:z-dropdown` goes |
| **New: the source walk** (`controls-shape.test.ts`) | Dialogs the sweep can't reach: no class string with `min-h-12` carries a rounded token, no filled button keeps one, and `border-borderStrong` lives only in `Chip` and the before/after viewer | One is put back in a dialog |
| `tokens.mirror` | `control` is declared web-only | Remove it from `WEB_ONLY` |
| `tap-targets`, `focus`, `axe`, `type-overflow` | Unchanged | Existing |

**What these cannot see:** whether it looks right, so each surface gets looked at, and iOS, which the simulator checks after the deploy. The source walk relies on `min-h-12` marking a control, which §13.2's floor makes nearly universal, and the rendered sweep backs it on every page it visits.

---

## 6. What else this changes

- **The base focus rule loses its radius** (`globals.css`). A focused link's ring goes from rounded to square, on every page. WEB-SYSTEM §5 records it.
- **WEB-SYSTEM §16** said « Rounded corners stay on controls ». Corrected, and so is web-swiss-direction §3, with the date.
- **SYSTEM §6** gets a line: on the web, controls are `control`.
- **Performance:** classes change and a few bytes go, so no budget is at risk. All three budgeted pages get measured anyway.

---

## 7. The trade-off

The site and the apps look less alike now: a booking starts on square fields on the web and rounded ones in the app. Web-swiss-direction §3 kept controls rounded for that reason, and the owner chose otherwise with both in front of them. The apps can follow later: `radiusLarge` in `AppTheme` is the seam. That is a separate decision and needs its own look at a phone screen.

---

## 8. Not decided here

**The cards around the controls.** The booking steps, the client's account and the Espace pro keep their rounded cards (`Card`, `rounded-xl`), now holding square buttons and fields. It follows the owner's scope, which was fields and buttons. Whether it reads as a mismatch is for the owner to judge from the [pictures](assets/web-swiss-fields.png). If so, it is one more token.

**The floating « Carte » button over the footer.** On a short results page on a phone, it sits over the large wordmark. It floats by design and goes when the page gets longer, so this is recorded rather than changed.

---

## 9. Rollout

One PR. Its merge is a production web deploy, with no backend deploy, so the Apple keys are untouched. `/support` and `/politique-confidentialite` stay listed with Apple: their words don't change, only the buttons and fields on them. Read back on `myweli.com` afterwards, and looked at in the iOS simulator.

---

## 10. What was seen

Chosen from [the four options on the real pages](assets/web-swiss-fields-options.png). The result: [public, booking, account and Espace pro](assets/web-swiss-fields.png).

- **Red on the old code:** 5 of the 6 source tests. Green with the fix: all 2,352 unit tests, types, lint. Full e2e: 353 passed, and the 2 failures call the stub's fixed port, which only CI's configuration uses.
- **Each rule broken on purpose, on the committed fix: 17 of 17 caught,** 8 at unit level and 9 in the browser (in three builds, each named test seen failing).
- **The sweep corrected this spec.** It reported the gallery's photos and the map's pins as round buttons, so both joined §1's exceptions, which is the right answer for each.
- **Speed, five runs each, on a local build:** `/` 2113 ms (2113 before), `/suppression-compte` 2109 ms (2109), `/connexion` 2754 ms (2713), with one run at 3327. Nothing here touches what that page loads, and it swings between runs (`main` measured 2712–2789), so this is read as noise, not proved to be. CLS 0, TBT 0.
- **Not seen before the merge:** iOS, where Safari can round a field by itself. `rounded-control` sets the radius explicitly, which should hold; the simulator on the deployed site is what will say.
