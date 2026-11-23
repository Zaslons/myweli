# MyWeli (client) — what the app says is true (A1) — design spec

| | |
|---|---|
| **Status** | **Approved by the owner on 2026-11-23** (« Approve as recommended »: §11's five recommendations, BACKLOG decisions 165–169). **Amended the same day by decision 170:** the home stories are hidden behind a flag, not removed (§2.1). **Built 2026-11-23** on `feat/consumer-app-truth` (A1); A1w, the web half of §2.7, is next. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-23 |
| **PRD ref / phase** | FR-DISC-001, FR-APPT-001, FR-APPT-003/005, FR-APPT-009, FR-PAY-005 · V1 · BACKLOG B0.10 (decision 160), B12.6, B12.10 (part), B12.11 |
| **Module** | `online-booking` (MODULES §2), with `payments` and `trust` |
| **ROADMAP entry** | [2026-11-23-consumer-app-truth-spec.md](../roadmap/entries/2026-11-23-consumer-app-truth-spec.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails · myweli-web-guardrails (for §9's web PR, when it is built) |
| **Read at** | `main` `d0a31d63`. Every « today » below was read in the code on 2026-11-23, with its file and line. |
| **Related** | [consumer-app-release-audit.md](consumer-app-release-audit.md) §6 gaps 2, 3, 6, 9 (part), 12, 15, 16 and §7 row A1 · [web-true-sentences.md](web-true-sentences.md) §3 · [web-flow-audit-2026-11.md](web-flow-audit-2026-11.md) C4 · [SYSTEM.md](SYSTEM.md) §12, §13, §15, §17 · [salon-cover-photo.md](salon-cover-photo.md) §11 · [app-store-forms.md](app-store-forms.md) §1 item 3 |

---

## 1. Goal & scope

**Goal:** every sentence, label and picture the client app shows is true before
either store sees it. Three of these are App Review rejections on their own: a
false offer (2.3.1), placeholder content (2.1), and a purpose string that does
not describe the use (5.1.1(ii)).

**In scope.** Seven changes in one app PR (A1), plus one web PR (A1w) for the
rule the two surfaces share (§2.7, §9):

| # | Change | Audit gap |
|---|---|---|
| 2.1 | The home stories are hidden behind a flag, kept for real ones (decision 170) | 2 |
| 2.2 | The cancel confirmation states the salon's rule, word for word as the web | 3 |
| 2.3 | « Langue » goes from the profile | 12 |
| 2.4 | The iOS permission texts describe what this app does | 6 |
| 2.5 | A salon card with no photo draws a local placeholder | 16 |
| 2.6 | Booking cards and home tiles read the booking's own salon name and services | 9 (part) |
| 2.7 | « Passés » tells the truth: no invented « Terminé », a tab for no-shows, no « Annuler » on a closed booking | 15 |

**Out of scope, and where each goes:**
- the appointment detail's status, salon, services and directions: A2;
- a sign-in screen you can leave, and push you can turn on later: A3;
- search and the Ivorian categories: A4;
- the privacy policy: B2. The store texts: B3, which must not mention stories or promotions;
- **MyWeli Pro: nothing changes.** Its booking lists use their own private `_AppointmentCard`s (`appointment_list_screen.dart:297`, `appointment_calendar_view.dart:221`, `booking_journal_screen.dart:185`), and its purpose strings stay as they are;
- **the backend: nothing changes** (§3).

---

## 2. Each change: today, after, every state, the French words

### 2.1 The home stories: hidden behind a flag, kept for real ones

*Amended 2026-11-23 by decision 170.* The spec first removed the stories. The
owner chose instead: **« don't remove stories, put it under a flag, or make it
that someone manage them »**. The flag is needed either way: until someone
manages real stories, the three in the tree are demo content and must not
reach a client.

**Today.**
- `AnnouncementStories` sits on every home (`screens/home/home_screen.dart:173`).
- Its three stories are hard-coded (`widgets/home/announcement_stories.dart:48-71`). Their texts are drawn inside the pictures (`assets/images/stories/*.svg`):
  - « -15% sur une sélection de salons », « Offre limitée », « Jusqu'à dimanche »: an offer nobody makes;
  - « Nouveau salon », « Beauté Divine », « Marcory · Zone 4 »: a salon that does not exist.
- A tap opens `StoryViewer` (`screens/stories/story_viewer.dart`). Seen stories are kept in `shared_preferences` under `myweli_seen_story_ids_v1` (`services/story_seen_service.dart:4`).

**Why the row cannot show as it is.** Any hard-coded promotion is an offer
nobody makes: App Store 2.3.1, Play's deceptive-behaviour policy, consumer law.

**After.**
- **`FeatureFlags.homeStories`, off.** While it is off, the home reads: the commune pill, a `spacingM` gap, then the category chips.
- **Everything stays in the tree:** the widget, the viewer, the seen-service, the three pictures and their `pubspec.yaml` line, and their tests.
- **Three guards:**
  - `test/unit/feature_flags_test.dart` fails when the flag is on while the demo ids (`promo_weekend`, `new_salon`, `last_minute`) or their pictures are in the tree. It is red on the defect and green on the repair: once real stories replace the demo, the flag may flip. Its blind spot is written in it: demo content under new ids passes;
  - the home's layout test checks that the row follows the flag, whichever way the flag is set;
  - the stories' 200 % text gate (§21 row 62) moves from the home pump to the widget pumped alone, so it does not go quiet while the row is hidden.
- **Turning it on** is a later change. It replaces the hard-coded list with a managed source, then flips the flag. **Who manages them is its own spec:**
  - MyWeli, from the admin console;
  - or the salons, which is V2 (PRD §7.2, « Pro: provider-posted stories »).
- **Goldens re-made:** `consumer_home.png` and `consumer_home_w360_x2.png`, now without the row.
### 2.2 The cancel confirmation states the salon's rule

**Today** (`screens/appointments/appointment_detail_screen.dart:98-172`). When the
booking has a deposit, the dialog adds one of two sentences:
- late: « Annulation à moins de 24 h : votre acompte de 5 000 FCFA ne sera pas remboursé. »
- otherwise: « Votre acompte de 5 000 FCFA sera remboursé. »

Both are said even when no proof was sent. The second promises what nobody does:
- the server records the cancellation and has no refund logic (`backend/lib/src/appointments/appointment_lifecycle_service.dart:24-30`);
- the CGU say MyWeli « ne rembourse aucun fonds » (§4);
- the web already says the salon's rule instead (B12.2, merged 2026-11-02 in #723).

**After: the web's rule, word for word** (`cancellationNotice`,
`web/lib/account/appointments.ts:169-192`; [web-true-sentences.md](web-true-sentences.md) §3).
The words were approved by the owner on 2026-11-02 for the web.

| Case | The box under « Êtes-vous sûr de vouloir annuler ce rendez-vous ? » | Tone |
|---|---|---|
| No deposit (`depositAmount` ≤ 0) | none | — |
| Booked by the salon (`clientName != null`, the app's form of the web's `salonEntered`; see `web/lib/bff.ts:144-151`) | none | — |
| Deposit asked, **no proof sent** (`depositScreenshotUrl` null) | **Vous n’avez envoyé aucun justificatif d’acompte pour ce rendez-vous.** | neutral |
| Proof sent, **the appointment's time has passed** | **D’après la règle du salon, votre acompte de 5 000 FCFA ne sera pas remboursé, car l’heure du rendez-vous est passée.** | error |
| Proof sent, **N h or less before** | **D’après la règle du salon, votre acompte de 5 000 FCFA ne sera pas remboursé, car vous annulez moins de 24 h avant.** | error |
| Proof sent, **more than N h before** | **D’après la règle du salon, votre acompte de 5 000 FCFA vous revient, car vous annulez plus de 24 h avant. Voyez avec le salon pour le récupérer : MyWeli ne détient aucun acompte.** | success |
| Proof sent, a salon whose delay is **0 h**, before the time | The sentence above, ending **…car vous annulez avant l’heure du rendez-vous. Voyez avec le salon pour le récupérer : MyWeli ne détient aucun acompte.** Never « plus de 0 h ». | success |

**Details.**
- **The web's seventh row is not needed in the app.** That row covers a missing delay. `cancellation_window_hours` is `NOT NULL DEFAULT 24` (`backend/lib/src/db/migrations.dart:80`), so the server always sends it. The web keeps the row as a defence.
- **The characters are the web's**, including the no-break spaces in « 24 h » and before « : ». One sentence shared by two surfaces should be byte-identical. SYSTEM §17.1's note on no-break spaces is about app-wide conventions, and this adds none.
- **Tones:**
  - error is today's late box: `error` border, warning icon, `error` text;
  - success is today's on-time box: `success` border, info icon;
  - neutral is new: `border` colour, info icon in `textSecondary`, `textPrimary` text;
  - all three keep the `surfaceVariant` fill required by §13.1.
- **The exact cut-off counts as late**, as in `cancellation_policy.dart` and the web.
- **The clock:** the sentence is computed when the dialog opens, from `AppClock`. A wrong phone clock can pick the wrong row; the sentence is advice, and nothing is enforced (the web's note).
- **The amount:** `Formatters.formatCurrency(depositAmount, currency: a.currency ?? a.providerCurrency ?? 'XOF')`, as today.
- **The button labels stay** « Annuler le rendez-vous » and « Garder » (§15).
- **Code:** a pure `cancellationNotice(Appointment a, DateTime now)` in `core/utils/cancellation_policy.dart` returns the text and its tone, or null. It replaces `cancellationOutcome`, whose only caller is this dialog (`appointment_detail_screen.dart:100`). `test/unit/cancellation_policy_test.dart` is rewritten around the table above.

### 2.3 « Langue » goes

**Today:** `screens/profile/profile_screen.dart:101-107` shows a « Langue » tile,
trailing « Français ». Tapping it shows « Fonctionnalité à venir », which is
placeholder content (App Review 2.1).

**After:** the tile is removed and nothing replaces it. The app is French only
(`CFBundleLocalizations = [fr]`), so there is nothing to choose. « Fonctionnalité
à venir » then appears nowhere under `lib/`. The one other use is a component
golden's demo of a snackbar (`test/golden/components_feedback_a6_golden_test.dart:128`),
which no user sees, so it stays.

### 2.4 The iOS permission texts describe this app

**What the app really does, read in code:**
- **Camera and photos** go through one picker sheet. It offers both sources every time (`widgets/provider/image_picker_sheet.dart:28-80`) and is used for:
  - review photos (`widgets/review/submit_review_sheet.dart:79`);
  - the profile photo (`screens/profile/edit_profile_screen.dart:91`);
  - the deposit proof (`widgets/booking/deposit_payment_sheet.dart:201`).
- **Location** is used by:
  - the map (`screens/map/map_screen.dart`);
  - « Près de moi » in the commune picker, which finds the nearest commune (`widgets/common/commune_picker_sheet.dart:83-97`).
- **There is no salon gallery** in this app.

The strings live in `ios/tool/setup_flavours.rb:75-78`. The script writes them into `project.pbxproj` (`CAMERA_USAGE_DESCRIPTION` and its siblings).

| Key | Today | After |
|---|---|---|
| Camera | MyWeli utilise l’appareil photo pour vos photos d’avis, votre photo de profil et, côté salon, la galerie de votre établissement. | **MyWeli utilise l’appareil photo pour vos photos d’avis, votre photo de profil et la photo de votre justificatif d’acompte.** |
| Photos | MyWeli accède à vos photos pour vos photos d’avis, votre photo de profil, votre justificatif d’acompte et, côté salon, la galerie de votre établissement. | **MyWeli accède à vos photos pour vos photos d’avis, votre photo de profil et votre justificatif d’acompte.** |
| Location (when in use) | Nous utilisons votre position pour afficher les salons autour de vous sur la carte. | **MyWeli utilise votre position pour afficher les salons autour de vous sur la carte et trouver votre commune.** |
| Location (always, required by the plugin; never asked) | MyWeli n’utilise votre position que pendant que vous utilisez l’app, pour afficher les salons autour de vous sur la carte. | **MyWeli n’utilise votre position que pendant que vous utilisez l’app, pour afficher les salons autour de vous sur la carte et trouver votre commune.** |

- **The camera text was missing the deposit proof**, although the deposit sheet offers the camera. **The location text was missing the commune**: the same gap Pro's text was fixed for (app-store-forms §1 item 3).
- **The PR runs `ruby ios/tool/setup_flavours.rb` and commits the regenerated `project.pbxproj`.** `test/infra/setup_flavours_test.dart` (« on the committed project, a run changes nothing ») fails if the two disagree.
- The comment above `FLAVOURS` (« The consumer strings are unchanged, verbatim ») is reworded.
- **Pro's four strings do not change.**

### 2.5 A salon with no photo: a local placeholder

**Today:**
- `widgets/provider/provider_card.dart:195` and `:380` load `https://via.placeholder.com/400x300` for a salon with no photo. That is a request to a third party, and the privacy label does not declare it.
- Whether that host still serves is UNVERIFIED. If it does not, `TimedCachedImage` shows its error box.
- `AppConstants.placeholderProviderImage` and `placeholderAvatar` (`core/constants/app_constants.dart:45-48`) point at the same host and are used nowhere.

**After:**
- **One local widget, `SalonPhotoPlaceholder(width, height)`:** a `surface` fill with the `Icons.store` glyph at `iconL` in `textTertiary`.
- **It is the look the booking card already draws by hand** for a salon with no photo (`appointment_card.dart:75-84`), which then uses the widget too.
- It is decorative and excluded from semantics: the card's name carries the meaning.
- No network request. The two constants are deleted.

### 2.6 Cards and home tiles: the booking's own salon

**Today:**
- The booking card (`widgets/booking/appointment_card.dart:39-48`) and the home's « Derniers rendez-vous » tiles (`home_screen.dart:321-338`) look the salon up in `ProviderProvider.providers`. That list is the discovery page that happens to be loaded: 20 salons, in the chosen commune.
- **A booking at any other salon reads « Salon », and the card's services line is empty.** That covers another commune, page two, or a salon that left the listing.
- Yet the booking carries `providerName` and `serviceNames` from the server (`withProviderFacts`, `backend/lib/src/appointments/appointment_enrichment.dart:68, 92`).

**After:**
- **Name:** `salonNameOr(appointment.providerName ?? provider?.name, kUnnamedSalon)`. The booking comes first, the discovery list second, « Salon » last (§17.2).
- **Services (the card):** `appointment.serviceNames` when it is not empty; otherwise the discovery lookup, as today.
- **Unchanged:** the photo and the place row (« Voir sur la carte », « Itinéraire »). The booking carries no photo and no coordinates. A2 brings the salon's facts to the detail.

### 2.7 « Passés » tells the truth

**Today:**
- **« À venir »** is every booking after now that is not cancelled (`providers/appointment_provider.dart:80-89`).
- **« Passés »** is `visitHistory`:
  - `effectiveAppointmentStatus` makes every past booking that is not cancelled or a no-show `completed` (`core/utils/visit_history.dart:9-19`);
  - the list then forces the chip to `completed` (`my_bookings_screen.dart:227-229`);
  - so **a booking the salon never confirmed reads « Terminé »**, and `VisitSummary` counts it as a visit and adds its price to « dépensés ».
- **A no-show is in no tab.**
- **The detail offers « Annuler le rendez-vous » on a no-show** (`appointment_detail_screen.dart:542-571`: only `cancelled` and `completed` hide it). The server refuses it: a closed booking is `invalid_state` (`appointment_lifecycle_service.dart:51, 223-224`).
- **The web differed until A1w** (2026-11-23, [web-account-bookings-truth.md](web-account-bookings-truth.md)), when it took the same table (`categorize(status)`, `web/lib/account/appointments.ts:120-127`, as read at `d0a31d63`):
  - a past pending or confirmed booking stays in « À venir » (C4, B12.6);
  - a no-show goes to « Annulés ».
- **Nothing on the server closes a booking by itself.** No cron job completes or expires one (`backend/routes/internal/cron/`, read 2026-11-23); only the salon does, with « Terminé » or « Non présenté » in Pro.
- `visit_history.dart`'s own comment calls the rule « a placeholder until the backend sends real completion / no-show events ». It does now.

**The rule: one table, the same on both surfaces.**

| Booking | Tab | Chip | Chip tone |
|---|---|---|---|
| `pending`, time after now | À venir | En attente | warning (as today) |
| `confirmed`, time after now | À venir | Confirmé | success (as today) |
| `pending`, time now or past | **Passés** | **Non confirmé** (new) | **neutral** |
| `confirmed`, time now or past | **Passés** | Confirmé | success |
| `completed`, any time | Passés | Terminé | neutral (as today) |
| `noShow`, any time | **Passés** | Absent | error (as today) |
| `cancelled` | Annulés | Annulé | error (as today) |

- **A no-show goes in « Passés », not « Annulés ».** Nobody called it off: the time passed and the salon marked the client absent. « Annulés » holds what the client or the salon called off (§11 Q1).
- **« Non confirmé »:** the salon never answered, and MyWeli does not know whether the visit happened.
  - « En attente » is untrue once the time has passed: nothing is awaited anymore. That is also why its tone moves from warning to neutral.
  - « Terminé » would invent an outcome.
  - A past « Confirmé » stays: it is true, and the visit probably happened (§11 Q2).
- **The boundary:** a booking whose time is exactly now is past, as on the web (`isUpcoming`: `> Date.now()`).

**« Passés »:**
- **Order:** newest first, grouped by month, as today.
- **The summary (`VisitSummary`):**
  - it counts only `completed` bookings: « N visite(s) » and « X FCFA dépensés »;
  - **it is hidden when there are none.** A « 0 visite » block above a list of past bookings would read as a fault (§11 Q3).
- **« Réserver à nouveau »:** under every past booking whose salon is live, whatever its chip, as today. A stopped salon shows the same `InlineFeedback` as today.
- **Empty state:** title **« Aucun rendez-vous passé »**, text **« Vos rendez-vous passés apparaîtront ici. »** The title was « Aucune visite », and the tab now holds absences too.
- **Loading, error, retry and pull-to-refresh:** unchanged (`AppAsyncView`; the three tabs read one list and fail together).
- **At 200 % text:** « Non confirmé » is the longest chip. The card's `Wrap` already lets a chip drop to its own line (`appointment_card.dart:90-128`), and the 2× golden checks it.

**Elsewhere:**
- **« À venir »:** `pending` and `confirmed` after now, soonest first.
- **« Annulés »:** `cancelled` only.
- **The home's « Derniers rendez-vous »:** the same three newest bookings that are not cancelled; their chips follow the table. A past pending booking reads « Non confirmé ».
- **The salon page's tiles** (`provider_detail_screen.dart:583`): chips follow the table.
- **The detail:**
  - « Annuler le rendez-vous » shows only for `pending` and `confirmed`; a no-show is closed, like `cancelled` and `completed`;
  - « Reporter » and « Ajouter au calendrier » are unchanged (future bookings only).
- **The review offer is unchanged.** It reads the real `completed` status (`appointment_provider.dart:118-130`).

**Code:**
- **A pure `core/utils/client_booking_rule.dart`** holds `clientTab(a, now)`, `clientStatusLabel(a, now)` and `clientStatusTone(a, now)`. `AppointmentProvider`'s three lists, the card, the tile and the detail read it.
- **« Non confirmé » lives in that file, not in `StatusLabels`.** It is a fact about the client's display, not a status, and Pro must never show it.
- **In `visit_history.dart`:**
  - `effectiveAppointmentStatus` and `visitHistory` are deleted;
  - `groupVisitsByMonth` and `totalSpent` stay;
  - the unused `pastAppointments` getter goes; it also listed past cancelled bookings.

**The web half (PR A1w; closes B12.6 and C4):** its own spec, [web-account-bookings-truth.md](web-account-bookings-truth.md), written 2026-11-23 after A1 merged (#834). It names the function `clientTab(a, now)`, as in the app, and adds the order of each tab, C7's history, an empty state per tab and a heading, each asked in its §11.
- `clientTab(a, now)` replaces `categorize(status)`, with the same table (built in A1w, 2026-11-23).
- `clientStatusLabel(a, now)` gives « Non confirmé » for a past pending booking.
- « Passés » gains no-shows and past pending and confirmed bookings, and « Annulés » loses no-shows.
- Unit tests go in `web/tests`.
- The web guardrails skill is run when it is built.
- **Merging it is a production web deploy, on the owner's word.**

---

## 3. API & contract

**None.** The server already sends every field used:
- `providerName` and `serviceNames`;
- `status`;
- `depositAmount`, `depositScreenshotUrl` and `cancellationWindowHours`;
- `clientName`, `currency` and `providerCurrency`. **Corrected 2026-11-23:** `currency` is declared but never stored (the Postgres insert has no column for it), so the app reads `providerCurrency`. Found while writing [web-account-bookings-truth.md](web-account-bookings-truth.md) §1; a backend task of its own.

`docs/api/openapi.yaml` does not change.

## 4. Data model

**None.** The app's `Appointment` model does not change. Nothing is stored on
the phone, and the stories key is left as described in §2.1.

## 5. Architecture & patterns

- **Two pure functions in `core/utils/`**, each unit-tested, which the widgets read. No new service, provider or route.
- **One shared widget**, `widgets/common/salon_photo_placeholder.dart`, used at three sites: the two in `provider_card.dart` and the booking card.
- **One new flag**, `FeatureFlags.homeStories`, beside the others in `core/config/feature_flags.dart`.
- **One booking widget**, `widgets/booking/cancellation_notice_box.dart`: the dialog's deposit box in its three tones, so one golden can show all three.

## 6. Security & privacy

- **One third-party request is gone** (`via.placeholder.com`), so the privacy label (B3) has nothing to declare for it.
- **The four purpose strings name every use and no other** (5.1.1(ii)).
- **No new data is collected, sent or stored.**

## 7. Performance

- **The home skips a row of three SVG decodes** and the `shared_preferences` read that coloured their rings, while the flag is off.
- **The APK keeps the three SVG assets** (decision 170).
- **No request is added.** One is removed: the placeholder.

---

## 8. Testing plan

**Each new guard is watched red once, and the commit message lists every
mutation run.**

| Test | What it pins | The mutation that must turn it red |
|---|---|---|
| `test/unit/cancellation_policy_test.dart` (rewritten) | The seven rows of §2.2; the exact cut-off is late; 0 h; a passed time; no proof; a salon booking; no deposit | `!now.isBefore(cutoff)` → `now.isAfter(cutoff)` |
| `test/unit/cancellation_notice_parity_test.dart` (new) | Each fixed fragment of the app's sentences appears verbatim in `web/lib/account/appointments.ts`, with comments stripped | One word changed in the app; then one in the web |
| `test/unit/client_booking_rule_test.dart` (new) | The seven rows of §2.7; a time exactly now is past | A no-show sent to « Annulés »; `isAfter` → `!isBefore` at the boundary |
| `test/widget/my_bookings_screen_test.dart` (new) | A past pending booking is in « Passés » as « Non confirmé », and « Terminé » is absent; a no-show is listed; the summary is hidden with no `completed` booking and counts only `completed` ones | Restore `copyWith(status: completed)` |
| `test/widget/appointment_detail_states_test.dart` | A no-show has no « Annuler le rendez-vous »; each tone of §2.2 renders its sentence | Drop `noShow` from the closed set |
| `test/widget/appointment_card_test.dart` | A booking whose salon is not in the discovery list shows its own `providerName` and `serviceNames` | Read `provider?.name` first |
| `test/unit/feature_flags_test.dart` | The home stories stay off while the demo ids or pictures are in the tree (§2.1) | `homeStories = true` |
| `test/a11y/layout_test.dart` | The home row follows the flag; the stories' 200 % gate, pumped alone | Show the row whatever the flag says |
| `test/unit/truth_pins_test.dart` (new) | No file under `lib/` contains `via.placeholder.com` or « Fonctionnalité à venir », comments stripped | Put either string back in a widget |
| `test/infra/setup_flavours_test.dart` | The consumer camera and photos strings contain neither « côté salon » nor « galerie »; the location strings name « commune »; the committed `pbxproj` matches the script | Restore today's camera string in the script only |
| Goldens | Re-made where the Linux run moved them (`consumer_home.png`, `consumer_home_w360_x2.png`, and any other it shows). New, in `consumer_truth_golden_test.dart`: `consumer_cancel_notice_tones` (1×), `consumer_cancel_notice_tones_w360_x2`, `consumer_past_chips_w360_x2` | Made by the goldens workflow (Linux); every changed PNG opened before commit; the before and after go in the PR |

**Also:**
- `flutter analyze` at 0;
- the full mobile suite, run locally before the push;
- the tap-target, 200 % text and semantics checks of SYSTEM §13 on the changed screens;
- the design-system counts of §20 not grown.

---

## 9. Rollout & scope discipline

**PR A1 (app):**
- **Touches** `mobile/`, SYSTEM.md, BACKLOG, the audit's §6 marks and one roadmap entry.
- **Merging deploys nothing.** The change reaches clients with the next consumer build (Track C, each step on the owner's yes).
- **The next Pro build carries the code but shows none of it:** these screens are the client app's, and Pro's purpose strings do not change.

**PR A1w (web):**
- Opened right after A1 (§11 Q4).
- **Its merge is a production web deploy, on the owner's word.**

**What closes, and what is left:**
- **With A1:**
  - BACKLOG B12.11;
  - B12.10's no-shows and `via.placeholder.com`;
  - audit gaps 2 (hidden; real stories are their own spec), 3, 6, 12, 15 (app side) and 16, and the name half of 9.
- **With A1w:** B12.6 and the web half of gap 15.
- **Left:** the rest of gap 9 is A2's.

---

## 10. Definition of done

- [ ] Every sentence in §2 shipped exactly as written, or as the owner changed it in §11.
- [ ] Analyze at 0; the full suite green; the goldens made on Linux and looked at.
- [ ] Every guard in §8 watched red, listed in the commit message.
- [ ] Four states on the changed screens: « Passés » has its new empty text; loading, error and success are unchanged.
- [ ] SYSTEM §13: chips and the dialog survive 200 % text; tap targets of at least 48 px; the placeholder excluded from semantics.
- [ ] Tokens only, no new literal. SYSTEM.md's story mentions updated (§2.1).
- [ ] V1 only; nothing in Pro changes.
- [ ] The roadmap entry, BACKLOG, and the audit's §6 updated in the same PR.

---

## 11. Open questions (each with a recommendation)

1. **No-shows:** in « Passés » with « Absent », or in « Annulés », as the web shows them today? *Recommended: « Passés »*: nobody cancelled them (§2.7).
2. **A past booking the salon never confirmed:** « Non confirmé », or another word? *Recommended: « Non confirmé »*: it says what MyWeli knows and nothing more.
3. **The summary on « Passés »:** count only bookings the salon marked « Terminé » and hide it when there are none, or remove it? *Recommended: count only « Terminé », hidden when there are none.*
4. **The web half:** its own PR right after the app's, merged and deployed on your word, or in the same PR? *Recommended: its own PR*, so the app PR's merge touches no production.
5. **The words:** approve the French sentences of §2 as written? They are: the cancel sentences (the web's, approved on 2026-11-02), the four purpose strings, « Non confirmé » and the empty state.

**Answers (2026-11-23): « Approve as recommended »**, all five (BACKLOG decisions 165–169): no-shows in « Passés »; « Non confirmé »; the summary counts only « Terminé » and hides at zero; the web half in its own PR; the sentences as written.
