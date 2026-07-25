# web-b8-reading-text — the reading-text resize: bodyLarge where you read, 16px where you type, 14 where you scan (B8)

**Status:** Shipped (2026-07-23) — see « As built ». **Surface:** `web/` — every
`text-bodyMedium` call site, classified. **Design system:**
[WEB-SYSTEM.md §3](WEB-SYSTEM.md#3-type-on-the-web) ·
[SYSTEM.md §4](SYSTEM.md#4-type). **Roadmap:** design-system programme,
slice B8 (register row 17).

## Goal & the debt — the row that was wrong three ways

Row 17's claim: "356 × `text-bodyMedium`; `bodyLarge` used once; the web
reads one step smaller than the app." The census measured all three parts
wrong:

1. **308 sites, not 356** (pro 191 · account 50 · booking 18 · provider 17 ·
   shared root 11 · auth 5 · discovery 5 · landing 2 · app/ 9 — 69 files).
2. **`text-bodyLarge` had ZERO usages, not "once".** The design system's own
   "default reading text" role (tokens.ts:152 — 16px/24lh/0.5 tracking,
   defined since B2b) was entirely unused; the B7 emitted-CSS snapshot
   contains no `.text-bodyLarge` selector. No token work is needed — B8 is a
   usage migration.
3. **"The app reads at 16px" is only PARTLY true.** Measured on the Flutter
   app: the salon description (`provider_detail_screen.dart`) and the
   empty-state body (`empty_state.dart`) are `bodyMedium` (14) — mobile's own
   paragraphs read one step below §4's "bodyLarge = Default reading text"
   doctrine. Mobile's REAL 16px sites: the settings/account ListTile rows
   (`profile_screen.dart` bodyLarge, `pro_profile_screen.dart` ×6), auth
   prompt copy, and **typed input text** (M3's default —
   `app_text_field.dart` sets no style; hint = bodyMedium, label =
   labelMedium). Mobile role counts: bodySmall 227 · bodyMedium 159 ·
   titleMedium 86 · bodyLarge 31. A blind 308→16 sweep would have made the
   web read BIGGER than the app almost everywhere.

**And one accident found on the way:** the phone widget already types at
16px — `.myweli-phone .PhoneInputInput` (globals.css) sets no font-size and
inherits the browser default — while every `<TextField>` next to it types at
14. Right by luck; B8 makes it right by declaration.

## Owner decisions

1. **HYBRID — readers 16, pro density 14.** Genuine reading copy →
   `text-bodyLarge`; dense operator surfaces stay `text-bodyMedium` **by
   doctrine, not debt** (§9's density mandate — B7 just built the dense
   dashboard). Mobile's own 14px reading paragraphs become a NEW mobile-side
   register row (SYSTEM.md §21 — found from the OUTSIDE by this census;
   A-series candidate).
2. **ALL inputs type at 16.** M3 parity (mobile's typed text is 16 by
   default) — and 16px is the threshold below which iOS Safari auto-zooms
   every focused field, so the whole product stops zooming. Labels, hints
   and errors keep their smaller roles (M3 itself renders them small under a
   16px value: hint 14, label 12).

## The classification rule (first match wins)

1. className on `input`/`select`/`textarea` → **bodyLarge** (the typed value
   only).
2. Wears `truncate`/`line-clamp`, or is a DataTable cell / `<dl>` / table
   text → **stays 14**. Text permitted to clip is text you SCAN — this rule
   structurally removes the ProSidebar `w-60` and AvisClient `w-8`/`w-6`
   width risks (they were never reading text).
3. A control's own text (tab, menu item, chip, nav link, banner, Toast,
   Loading, sidebar row, calendar cell) → **stays 14**.
4. A meta/secondary line (date, price, duration, count, caption) →
   **stays 14**.
5. A French sentence standing as content — description, FAQ answer,
   marketing copy, empty/error body, dialog explanation, onboarding subline,
   auth prompt, a confirmation occupying the content area → **bodyLarge**.
6. Row PRIMARY text — **split**: account/settings *navigation* rows → 16
   (mobile's ListTile-bodyLarge twins); *operator-list* rows → 14 (scanning
   surfaces; mobile renders them as title roles, not body reading).
7. `role="status"` confirmations — **split by occupancy**: replaces a form /
   stands as body copy → 16; a terse inline « Enregistré. » tick → 14
   (Toast-at-14 is the precedent — an inline tick is a toast that didn't
   float). ⚠️ Review attention: the owner phrase "confirmation copy" must
   not be read as blanket-16.
8. `role="alert"` field/form errors (37) → **stay** at their current roles.
   `ErrorState`'s alert is exempt — it is a page body (rule 5).

Tie-break: would mobile render this as a §4 paragraph or as a ListTile
subtitle? Subtitle → 14.

**Predicted split: ~130 flip · ~178 stay** — the exact reconciliation lands
in « As built » (a count is a hypothesis; the burn-down is the measurement).

## The sweep, commit by commit

| Commit | Contents |
|---|---|
| ① B8a — inputs | `TextField` `field` const (input + textarea) · the 6 other consts (`inputCls` in Catalogue, Disponibilités, DayHoursEditor; `input` in Acompte, Profil, LocalityPicker) · ~20 inline input/select/textarea sites (ManualBookingDialog ×5, ProAppointmentDetail ×2, JournalPanel ×2, InviteMember ×3, ChangeRole ×2, ProRegister, AddSalon, RendezVous, Recherche, ReviewList textarea, Médias ×2) · globals.css phone input made explicit via `theme('fontSize.bodyLarge[0]')`. **Audit:** `grep -rn "text-bodyMedium" web/app web/components \| grep -E "input\|select\|textarea"` → empty. Tests in-commit (below). |
| ② B8b — shared bodies | `EmptyState` description + `ErrorState` message → bodyLarge (~30 surfaces at once). Pins in b6-states.test.tsx. |
| ③ B8c — consumer sweep | app/ marketing ×5 · Faq answers + salon description · booking confirmation copy · account status/reschedule copy + the settings row links (ListTile parity) · auth prompts · discovery/landing reading copy. |
| ④ B8d — pro reading copy ONLY | Dialog body copy (~6) · sentence confirmations (rule 7's 16 side) · Abonnement onboarding sublines. Everything density-classed stays. |
| ⑤ | Docs · register · review · PR. |

## What stays 14 — doctrine, not debt (the exclusion list is part of the row)

DataTable cells (the B7 density work; the admin twin's cells are 14 on
mobile) · meta/secondary lines (~55) · controls (~58: tabs ×13, menus,
links-as-controls, ProSidebar, Chip) · Toast, Loading, AppInstallBanner,
banners, `<dl>` fact-lists · field labels/hints (~22) + `role="alert"`
errors (37) + inline « Enregistré. » ticks (rule 7's 14 side) ·
operator-row primary text · MonthCalendar cells · AvisClient's fixed count
columns · Abonnement's line-through anchor price.

## Tests

- **`textfield.test.tsx` — "the typed text is 16 — the row-17 pin"**: the
  input and the multiline textarea carry `text-bodyLarge`, never
  `text-bodyMedium`. Proof-red at base (red today by construction).
- **`b6-states.test.tsx`** — EmptyState description + ErrorState body carry
  `text-bodyLarge` (extends the existing anatomy tests).
- **`type-overflow.spec.ts` extensions**: `/connexion` joins the public
  matrix (auth copy at 16 + a 16px TextField @375); a NEW pro test logs in
  (in-file helper shared with the journal test) and runs the
  no-horizontal-scroll + overflow checks on `/pro/disponibilites` @375 —
  DayHoursEditor is the tightest input geometry in the product. Honest note:
  the per-element check skips inputs (they clip their own text by design) —
  the page-level `scrollWidth` assertion is the real net there.
- **Untouched pins, verified**: the 13.75px journal pin is `labelSmall` +
  `leading-tight` (outside B8's set); no unit test asserts a bodyMedium
  className on any touched component; the token gates don't pin call-site
  role choices; tap-targets asserts only ≥48 (growth-safe); positional
  clicks are element-relative; axe is size-blind; Lighthouse perf is
  warn-only (a11y/SEO can only improve).

## Verification

Per commit: lint · typecheck · vitest · targeted e2e. Before PR: the full
battery + Lighthouse + all token gates, then:

- **Emitted-CSS diff vs the B7 snapshot — prediction: +1 selector, −0.**
  The one addition is `.text-bodyLarge` (its first emission ever);
  `text-bodyMedium` survives on ~178 sites. A SECOND new selector means the
  sweep leaked. The phone-input change edits declarations inside an existing
  selector — named here so the byte-diff reader expects it.
- **Browser visual pass @375/768/1280** (type-overflow can't see reflow —
  this is the honest complement): `/` · `/salon/salon-excellence`
  (description + FAQ, especially the 768–1024 band where B7's
  `max-w-content` cap stacks with the taller 24px lines) · `/recherche`
  empty state · `/connexion` · a booking step · `/mon-compte` + an
  appointment detail · `/pro/connexion` · `/pro/disponibilites` @375 ·
  `/pro/catalogue` with an editor open · ManualBookingDialog @375 AND @1280
  (it carries ① inputs and ④ copy — check after both) · `/pro/abonnement`
  (the one card where 16-next-to-14 is visible in one frame) · an Équipe
  dialog · Médias.
- **Post-sweep asserts**: the input residual grep → empty;
  `grep "text-bodyLarge" web/ -r | grep "leading-"` → zero (only 2
  `leading-*` overrides exist product-wide, both outside B8's set).

## Risks, recorded

- **Line-height 20→24** is THE visual change of ①: a `p-m` field's
  content-box grows 52→56px (min-h-12 no longer governs). Icon-beside-text
  flex rows shift ~2px — eyeballed in the visual pass.
- **+~15% width on long French strings** — wrap absorbs it; rule 2 is the
  structural guard (a `truncate` site was never reading text).
- **A partial input sweep re-summons iOS zoom** — the residual grep and the
  TextField pin are the only nets; a future input added at `text-bodyMedium`
  regresses silently (a lint rule is out of scope, recorded).

## As built — the deltas and the finds

- **The reconciliation is exact: 308 = 67 flipped + 241 stay**, plus **4
  token-less reading paragraphs declared** `text-bodyLarge` (zero-pixel: they
  rendered 16 only via the browser default — the phone-input accident in
  prose form): the salon page's intro (the most-read sentence on the most
  important public page), the marketing hero subline, the taxonomy landing
  intro, the 404 body. A tail of token-less `font-medium` TITLE-ish
  paragraphs remains (card titles missing title tokens) — a different,
  smaller debt, recorded here, not silently absorbed.
- **The tag scan beat the census twice**: it caught DepositProof's file-name
  input (missed), and un-binned the two Médias file-pick LABELS (control
  text, rule 3 — they stay 14; iOS zoom doesn't apply to file inputs).
- **The census's "~6 dialog body copy" dissolved to ONE** under the
  heuristic: ManualBookingDialog's guidance sentence. The email line is
  meta, the alert stays, the picked-client and Total rows are fact rows.
- **Judgment calls made (review targets)**: the invitation decision sentence
  (« X vous invite comme Y ») flipped on both surfaces — rule 5 over rule 6
  (read once to accept/decline, not scanned); the notification PREFS row
  titles flipped (SwitchListTile parity) while the notification FEED rows
  stay (a scanning list); the pro reviews page's review TEXT flipped (a
  review is read — the consumer twin flipped the same day).
- **Found in passing, fixed here**: type-overflow's salon route had been
  VACUOUS since the slug scheme changed — `/salon/salon-excellence` scanned
  the 404 page (which also doesn't overflow). Repointed at `/beaute-divine`,
  the real salon page, which now also carries B8's intro + FAQ growths.
- **Emitted-CSS diff, measured**: B8's own contribution is exactly the
  predicted **+1 / −0** — `.text-bodyLarge{font-size:16px;line-height:24px;
  letter-spacing:.5px}`, its first emission ever. (The raw diff vs the b7
  snapshot shows one more addition, `focus-within:bg-surfaceVariant` — that
  is B7's REVIEW fix, landed after the snapshot was taken; attributed, not
  B8's.) The phone-input change lives inside an existing selector.
- **Verified in the browser** @375: the salon page (intro 16/24 · FAQ 16 ·
  meta 14 · no h-scroll), /connexion (field 16/24 · prompt 16),
  /pro/disponibilites (3 fields at 16, no h-scroll), /pro/abonnement (the
  hybrid in one frame: the banner subtitle at 16 beside the 14px
  line-through anchor price).

## The adversarial review's corrections

The review (Fable-limit truncated — 7 of 29 agents finished, the rest
hand-verified: an unverified finding is not a rejected one) surfaced 12
mis-classifications, ALL real, in three classes:

- **Pro reading-copy twins the consumer sweep flipped but their pro sides
  didn't** (8 sites → bodyLarge): ProLoginOptions' two auth prompts (twins
  of LoginOptions), CompteDangerSection's data-export sentence + the
  **delete-account warning** (the highest-stakes sentence on the pro side —
  its consumer twin read 16, it read 14), VerificationClient's banner
  subtitle (incl. the `rejectionReason` — reading copy the pro must act on;
  the Abonnement banner twin had flipped), EquipeClient's offer-gating
  sentence + invite-card explanation (twins of Acompte/GoLive), and
  AppointmentDetail's not-found page BODY (a `role=alert` that IS the page,
  like ErrorState — rule 8's exemption applies).
- **Token-less reading paragraphs still reading 16 by accident** (3 →
  declared bodyLarge, zero-pixel): BookingFlow's booking-success body (the
  single most-read confirmation of the consumer flow), ClientsClient's
  onboarding empty body, ClientCard's not-found body. What remains
  token-less is now only the `font-medium` TITLE-ish tail (row/card names) —
  the as-built line above is accurate as written.
- **Over-flips corrected** (3 → reverted to bodyMedium): the reserver page's
  `catégorie · commune` caption (a meta caption, rule 4 — and its salon-page
  Hero twin is 14), « Rendez-vous reporté ✓ » (a terse tick, rule 7's 14
  side), and the reschedule slot-empty placeholder « Aucun créneau
  disponible ce jour. » — reverted so that ALL in-picker "nothing here"
  placeholders read 14 (glanced, not read; BookingFlow's own two stayed 14,
  and its token-less third was declared 14 to match). The shared EmptyState
  component stays 16; ad-hoc picker placeholders are 14 — the clean line.

And two more, off the classification axis:

- **A field the sweep missed** — `HomeSearch`'s two search inputs used a
  token-less `field` const, so they typed 16 only by the browser default:
  invisible to the grep audit (which hunted `text-bodyMedium`, and this had
  no class). Declared `text-bodyLarge` — the same iOS-zoom hole as the phone
  widget. The completeness claim is now true only WITH this fix; the audit
  grep is widened accordingly.
- **The phone COUNTRY SELECT** declared too — iOS zooms on focusing a
  `<select>` under 16px, so half-declaring the widget (input only) left the
  hole open.
- **The vacuous-route gate hardened**: the type-overflow public routes now
  assert a page-specific heading renders BEFORE measuring overflow — a route
  scanning the wrong DOM (the bug B8 found) is now a loud failure, not a
  silent green.

**Final reconciliation (exact): 308 = 72 net-flipped + 236 stayed**
(the three over-flips reverted in review count as stayed), **plus 8
token-less reading paragraphs declared `bodyLarge`, 1 placeholder + 2
phone-widget declarations in CSS** → working tree **80 `text-bodyLarge` /
237 `text-bodyMedium`**. Emitted CSS: **+1 selector** (`.text-bodyLarge`),
−0.

## Not in scope

Mobile's own 14px reading paragraphs (the new SYSTEM §21 row — an A-series
decision) · a lint rule enforcing 16px inputs · any token change
(`bodyLarge` exists; the scale is mirror-gated) · title/label/small roles.

## Definition of done

Row 17 → 0 with the three-way correction recorded · every flipped site
passes the heuristic · the +1/−0 CSS diff holds · full battery green ·
adversarial review passed · WEB-SYSTEM §3/§15 + SYSTEM §21 + ROADMAP
refreshed in the same PR.
