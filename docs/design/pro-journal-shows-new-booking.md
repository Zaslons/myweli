# « Ma journée » shows the booking the salon just created

| | |
|---|---|
| **Status** | **Approved** (owner, 2026-10-13 — decision 2 of `pro-app-preview.md` §9: « fix it, build once more, and film that build ») — **being built** on `fix/journal-shows-new-booking`. Not merged, not in a build, not seen on a device. |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-13 |
| **PRD ref / phase** | Pro app — module `journal` (J1b) + manual booking · V1 · store submission |
| **ROADMAP entry** | [2026-10-13-pro-journal-shows-new-booking](../roadmap/entries/2026-10-13-pro-journal-shows-new-booking.md) |
| **Related** | [journal-j1b-app.md](journal-j1b-app.md) (« Ma journée ») · [pro-manual-booking.md](pro-manual-booking.md) (the form) · [clients-c1.md](clients-c1.md) (the client card) · `pro-app-preview.md` §4, §9 (the film that is shot on this build — on `docs/build-579-listing-filled`, not on `main` yet) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Governs** | `mobile/lib/core/access/pro_salon_scope.dart` · `providers/pro_appointment_provider.dart` · `providers/pro_journal_provider.dart` · `providers/pro_dashboard_provider.dart` · `providers/pro_clients_provider.dart` · `screens/provider/appointments/pro_manual_booking_screen.dart` · `services/mock/mock_pro_service.dart` (`createManualBooking`) |

## 1. Goal & scope

**Goal.** A salon that adds a booking from « Ma journée » is back on « Ma
journée » with that booking in it — at once, with no gesture. Today it is not
there until the list is pulled down. The build that goes to App Review carries
the fix, and the App Preview film is shot on it: a free slot becomes a booking,
in one take, with no pull-to-refresh.

**In scope**: the Pro app (`mobile/`, entry `lib/main_pro.dart`) — every screen
that shows the salon's bookings and is still mounted, or still cached, when a
booking is created.

**Out of scope**: the backend (no route, no DTO changes); the consumer app; any
new visual; the web (§1.3 — its day view already reloads).

### 1.1 The defect, as verified

Read in the code at `3d88d0e1`, **then observed** in a widget test that drives
the real screens (§8.1 — seven of its cases red before the fix):

| What | Where |
|---|---|
| « Nouveau », « + Nouvelle réservation » (empty day) and every « Libre — HH:MM » row `context.push('/pro/appointment/new', …)` and do not wait for it | `pro_journal_screen.dart:109`, `:175`, `:223` |
| The day is loaded in `initState`, on « Réessayer » and on pull-to-refresh — nowhere else | `pro_journal_screen.dart:49`, `:156`, `:164` |
| The form, on success: snackbar « Rendez-vous créé », then `Navigator.pop(context)` with no result | `pro_manual_booking_screen.dart:241–242` |
| `createManualBooking` appends the created booking to **`ProAppointmentProvider._appointments`** — and tells nobody | `pro_appointment_provider.dart:248` |
| « Ma journée » renders **`ProJournalProvider._day`** — a different store | `pro_journal_provider.dart:85` |

Two stores, one write. The booking exists on the server and in the agenda's
store; the day view never hears of it.

### 1.2 Every entry point, and every surface that goes stale

`/pro/appointment/new` (`pro_router.dart:116`) is opened from five places
(`grep -rn "appointment/new" mobile/lib`):

| # | Opened by | Returns to | Does that screen show bookings that are now stale? | This slice |
|---|---|---|---|---|
| 1 | « Nouveau » — `pro_journal_screen.dart:109` | « Ma journée » | **Yes**: the day list, the « Libre » rows, the week strip's dots | **Fixed** |
| 2 | « + Nouvelle réservation » on an empty day — `:175` | « Ma journée » | **Yes**: it still says « Aucun rendez-vous ce jour » | **Fixed** |
| 3 | A « Libre — HH:MM » row — `:223` | « Ma journée » | **Yes** | **Fixed** |
| 4 | « Ajouter » on « Rendez-vous » — `appointment_list_screen.dart:146` | « Rendez-vous » (calendar / list) | **Not stale** — it reads the store the form writes. **But wrong under a filter**: the append ignores what the list was loaded with, so a « Confirmé » booking appears under « En attente », and one for next week under « Aujourd'hui » | **Fixed** (the append respects the loaded filter — §2.6) |
| 5 | « Nouvelle réservation » on the client card — `client_detail_screen.dart:102` | « Fiche client » | **Yes**: the « Prochain rendez-vous » card and the visit history (`ProClientsProvider`, loaded once in `initState`, `:47`) | **Fixed** |

Screens that open nothing but sit **under** one of the five, still mounted:

| Screen | Why it is stale | This slice |
|---|---|---|
| « Accueil » (`dashboard_screen.dart`) — « Aujourd'hui · N · Rendez-vous », « Aujourd'hui · Revenus », « Ce mois » | It is the root of the stack, loaded once (`:67`), and `ProDashboardProvider.loadDashboardStats` returns early when it already holds figures for the salon (`pro_dashboard_provider.dart:20–22`) | **Fixed** (quiet refetch) |
| « Ma journée », when the booking was created from « Rendez-vous » opened over it (the calendar icon, `pro_journal_screen.dart:91`) | same two stores | **Fixed** (same signal) |
| « Clients » list, under a client card | **Not stale**: a row shows completed visits and the last visit, and a new booking changes neither (`clients_service.dart:533–560`). A booking typed with a **new** number creates a client the list under the card does not have until it is reopened | **Left** — not this defect; the list reloads on every visit |

**Left, and why** (each is a different defect, found while reading; none is
needed for the film):

- **A status changed on the detail screen is not shown by « Ma journée ».**
  « Accepter », « Rejeter », « Marquer comme terminé », « Marquer comme
  absent » (`pro_appointment_detail_screen.dart:271`, `:288`, `:338`, `:370`)
  write `ProAppointmentProvider` only, then pop. Same two stores, another
  trigger. **Read, not observed.** It needs its own decision (what a card
  shows while the server confirms) and its own tests.
- **Pull-to-refresh on « Accueil » does not refetch** once figures are loaded:
  it calls the same `loadDashboardStats`, which returns early. Observed in
  `pro_dashboard_booking_created_test.dart` (the cache case). Not fixed here,
  because the loud path it would take ends, on failure, on a text with no way
  out (`dashboard_screen.dart:180–189`) — a stale number is better than a dead
  end, and the right fix is that screen's error state.
- **The web's « Calendrier » and « Liste » views** after a booking created from
  the day grid — §1.3.

### 1.3 Web parity — checked, nothing to fix for the day view

The web day view (« Journée », `web/components/pro/RendezVousClient.tsx`)
**already reloads** after a creation. **Read, not run** (no browser, no
Playwright on this Mac):

- « + Nouveau rendez-vous »: `onCreated` calls `loadJournal()` and lists the
  appointments again (`RendezVousClient.tsx:344–350`);
- a click in an empty cell of the grid: `onCreated` → `onChanged()`
  (`JournalGrid.tsx:212–215`), which is `loadJournal` (`RendezVousClient.tsx:272`);
- the client card: `onCreated` → `load()` (`ClientCardClient.tsx:446–450`).

The existing e2e tests stop at « the dialog closed » / « Rendez-vous créé »
(`web/tests/e2e/pro.spec.ts:409–444`, `:533–549`); none asserts the new block.

**One thing is stale on the web, and it is not the day view**: a booking
created from a grid cell (or a block dragged, or accepted in the panel)
reloads the day only — `items`, which feeds « Calendrier » and « Liste », is
filled at mount and by « + Nouveau rendez-vous » alone. Switching view shows
the old list until the page is reloaded. **Read, not observed; left** — it is
the web's version of the status defect above, and this branch does not touch
`web/`.

## 2. UX & flows

Nothing visual is new: no component, no colour, no motion, no announcement.
The booking's card is the day's own card; the confirmation is the snackbar the
form already raises.

### 2.1 Happy path

1. « Ma journée » → a tap on « Libre — 10:45 » (or « Nouveau »).
2. « Réservation » opens, date and hour already set from the row.
3. Services, client, « Créer le rendez-vous ». The button shows the app's
   loader while the server answers.
4. The server answers `201`. **Before the form starts to leave**, the day has
   the booking: at its hour, in time order, « Confirmé », its end computed from
   the services' duration. The « Libre » row it took is gone; if time is left
   before the next booking, a « Libre » row starts at the new booking's end.
5. The form slides away over a day that is already right. « Rendez-vous créé »
   (success snackbar, a live region — SYSTEM.md §15; nothing is announced
   beside it).
6. Behind it, the day is asked for again, **quietly**: no loader, no blank
   list, the scroll position is kept, the rows stay on screen. When the answer
   lands it **replaces** what is shown — the server's own name for the client,
   its no-show badge, its order, anything another device changed meanwhile —
   and the week strip's dots are counted again.

### 2.2 The booking is for another day

The date was changed in the form. « Ma journée » **stays on the day it was
showing**; the booking is not added to that day; the snackbar still says
« Rendez-vous créé »; **the other day's dot appears** in the week strip at
once (when that day is in the displayed week) and is then confirmed by the
reload.

### 2.3 Filters

« Ma journée » filters in memory (`visibleAppointments`): the artist chip and
« Voir les annulés ». The new booking goes through the same filter — it is
added to the day, not to the list.

- Created from a « Libre » row under « Awa »: the row carries the artist
  (J1b §4.2), so the booking is Awa's and **is shown**.
- Created from « Nouveau » under « Awa »: it has no artist, so it is **not
  shown** — the filter says « Awa ». It is not lost: the « Sans artiste » chip
  appears, and « Tous » shows it.
- « Voir les annulés » is not reset; cancelled rows stay hidden or shown as
  they were.

### 2.4 States and edge cases

| Situation | What is on screen |
|---|---|
| **Slow network, during the creation** | The form, its button in the loading state (unchanged). Nothing changes under it. |
| **Slow network, after the creation** | « Ma journée » with the new booking, exactly as in §2.1 step 4. No indicator: the booking shown is the server's own `201` body, not a guess. |
| **The quiet reload fails** (offline, 5xx, a thrown error) | Nothing changes and nothing is said: the booking stays, no error state, no snackbar, no loader. The next pull-to-refresh or visit reconciles. A `forbidden` / `not_a_member` code is still reported to `ProAccessGuard` — a revoked member is signed out as everywhere else. |
| **The quiet reload returns a list without the booking** | The server wins: the booking leaves the list. This request was sent **after** the `201`, so its answer cannot predate the booking — the only way it is missing is that it was cancelled or moved meanwhile. |
| **An older request answers late** (a pull-to-refresh or a day change sent before the `201`) | Ignored. Every day request carries a sequence number and only the newest is applied — otherwise an answer computed before the booking existed would erase it. This also closes a race that was already there: two quick day changes, the slower answer winning. |
| **The day was still loading, or had failed, when the booking was created** (« Nouveau » is reachable in both states) | There is no settled day to add a row to. The day is loaded again, the ordinary way: loader, then the day — or its error state with « Réessayer », where the booking cannot be shown because no day is. |
| **Double submit** | The button is disabled from the first frame after the tap (unchanged). Two taps inside one frame — reproduced only by a test — used to send two requests and pop twice; `_submit` now returns when a creation is already in flight. |
| **The same booking announced twice** | Added once (matched by id). |
| **Empty day** (entry 2) | « Aucun rendez-vous ce jour » is replaced by the booking's card. |
| **The salon is switched** while a quiet reload is in flight | Its answer is dropped (the switch bumps the same sequence number). |
| **A failed creation** | Unchanged: the form stays, the refusal sits under it (`InlineFeedback`), no snackbar, nothing is announced to any store, nothing is reloaded. |
| **Collaborateur, own mode** | Unchanged: no « Nouveau », « Libre » rows are not tappable, no empty-state action (`pro_journal_screen.dart:106–107`, `:221–222`, `:172–175`); the server refuses anyway (`Cap.journalManageAll`). |

### 2.5 The other surfaces

- **« Accueil »**: its figures are asked for again, quietly — the cards keep
  their numbers until the new ones land; a failure changes nothing and says
  nothing. It is two screens away when this happens, so there is nothing to
  see. After a failed quiet reload the figures are remembered as stale, and
  the next pull-to-refresh asks again, still quietly.
- **« Fiche client »**: when the booking's phone number is the card's client's
  — the rule the server itself links a salon-entered booking by
  (`clients_service.dart:516–531`) — the card and its visits are asked for
  again, quietly: no loader, the card stays on screen, « Prochain rendez-vous »
  and the history update. A failure changes nothing. A booking for someone
  else leaves the card alone.

### 2.6 « Rendez-vous » (the agenda)

The store keeps what it was last loaded with (status, from, to). A created
booking joins the list only when it matches: a « Confirmé » booking does not
appear under « En attente », a booking for next week does not appear under
« Aujourd'hui ». « Calendrier », « À venir » and « Tous » show it as before.

### 2.7 Copy

No new string. « Rendez-vous créé » (existing).

## 3. API & contract

None. `POST /providers/{id}/appointments` already answers `201` with the
created booking — `id`, `artistId`, `appointmentDate`, `durationMinutes`,
`status: confirmed`, `clientName`, `clientPhone` (`BookingService.bookManual`,
`booking_service.dart:339–361`) — which is everything the day's card needs.
`GET /providers/{id}/journal` then supplies the enriched fields
(`clientDisplayName`, `clientNoShowCount`).

**Mock fidelity**: `MockProService.createManualBooking` did not return
`durationMinutes`; the server does. It now sums the services' durations (30
when none), like `bookManual`.

## 4. Data model

None.

## 5. Architecture & patterns

**One owner of « a booking was created ».** The only code that creates one is
`ProAppointmentProvider.createManualBooking`. On success it announces it,
once, to the fleet of per-salon stores:

```dart
ProSalonScope.bookingCreated(created);
```

`ProSalonScope` (`core/access/pro_salon_scope.dart`) already is that fleet: it
holds every per-salon `ChangeNotifier` (`main_pro.dart` registers each with
`ProSalonScope.track`) and already sweeps them on a salon switch
(`resetAll`). A store that shows bookings implements a second contract:

```dart
abstract class ShowsSalonBookings implements SalonScoped {
  void bookingCreated(Appointment booking);
}
```

| Store | On `bookingCreated` |
|---|---|
| `ProJournalProvider` | adds the booking to the displayed day when it is that day's; bumps that day's dot; reloads the day quietly |
| `ProDashboardProvider` | marks its figures stale; refetches them quietly |
| `ProClientsProvider` | reloads the open card quietly when the booking is that client's |

**Why this and not the alternatives.**

- *Each opener awaits `context.push` and refreshes its own provider.* Five call
  sites that each have to remember, and the two surfaces that open nothing —
  « Accueil », and a « Ma journée » left under « Rendez-vous » — are never
  told. It is also later: the result of a `push` arrives when the form has
  begun to leave, so the day would change mid-transition.
- *The form calls each provider after success* (the shape of
  `pro_appointment_detail_screen.dart:316–330`). A screen orchestrating three
  stores it does not own; the next store that shows bookings is forgotten the
  same way this one was.
- *`ChangeNotifierProxyProvider`.* New wiring in `main_pro.dart` that every
  test harness must reproduce to mean anything; the existing registry needs
  none.

No screen changes: « Ma journée », « Accueil », « Fiche client » already watch
their providers. A screen never reaches around its provider.

**A listener cannot break a creation.** `ProSalonScope.bookingCreated` calls
each store inside its own `try`: a store that throws is logged and skipped, the
others are still told, and `createManualBooking` still returns `true` — a
booking that exists must never be reported as failed (the salon would create
it twice).

**The wiring is the app's own.** The widget test registers its providers with
`ProSalonScope.track`, as `main_pro.dart` does, and a source pin holds the
three `track(…)` lines in `main_pro.dart`.

## 6. Security & authz

No new surface, no new data, nothing stored or logged. The booking shown
before the reload is the server's own response, never a client-side guess of a
price, an id or a status. Manual booking stays `Cap.journalManageAll`
server-side; the Collaborateur's own mode is untouched. Threat model: no
delta.

## 7. Performance

One creation costs what one « pull-to-refresh » costs — the day, then the
existing week prefetch (six light requests, `journal.md` §8.2) — plus one
dashboard request, plus two for an open client card. No frame is spent
waiting: the row is added synchronously, the rest is off-screen work. The week
prefetch stops as soon as a newer request starts, so two loops never write the
same dots.

## 8. Testing plan

### 8.1 Widget — the real flow (`test/widget/pro_journal_shows_new_booking_test.dart`)

The journal screen, the form, `ProRouter`'s own two `GoRoute`s (so the « Libre »
prefill travels through the real `extra`), the real providers registered with
`ProSalonScope.track`; one fake salon whose journal and whose `POST` answer
from the same list. No test drags the journal, calls `refresh()`, or starts
with the booking already in the stub; every assertion about the day is scoped
to the card keyed by the booking's id — the client's name is also in the form's
text field while the form slides away.

| Case | What it holds |
|---|---|
| A « Libre » row → form → create | one frame after the answer, **form still on screen**, reload **held**: the card exists, at 12:00–12:30, « Confirmé », between its neighbours; « Libre — 12:00 » gone, « Libre — 12:30 » there; the old rows still there; no loader; the day was asked for exactly once more. Then the server answers and wins (its name, another device's booking). |
| « Nouveau » → pick a date and an hour → create | the card is first in the day |
| The date is changed in the form | still « Aujourd'hui », no card, « Libre — 12:00 » still there, the 13th gets its dot while the reload is held |
| Filter « Awa » + « Nouveau » | no card under « Awa »; « Sans artiste » appears and shows it; a cancelled row stays hidden |
| Filter « Awa » + a « Libre » row | the card is shown (the artist travelled) |
| The reload fails — refusal, then thrown | the card stays, the old rows stay, no error state, no « Réessayer », no error text, no loader |
| **Control**: the creation is refused | the form keeps the refusal, no snackbar, the day is not asked for again, nothing changed after going back |
| The scroll position | a scrolled day keeps its offset through the whole flow |
| Two taps in one frame | one request, one booking, one pop |

### 8.2 Unit

- `pro_salon_scope_booking_created_test.dart` — only `ShowsSalonBookings`
  stores are told; a throwing store does not stop the others;
  `createManualBooking` announces on success, exactly once, and never on a
  refusal or a thrown error; a throwing store does not turn a success into a
  failure; `main_pro.dart` tracks the three stores.
- `pro_journal_test.dart` — same day / other day / before the first load /
  another salon / while a load is in flight / in the error state / twice; the
  reload replaces the day, removes a booking the server no longer has, keeps
  the day on a refusal and on a throw, never raises `isLoading`; a late older
  answer is dropped (both orders); a salon switch drops an answer in flight.
- `pro_dashboard_booking_created_test.dart`, `pro_clients_test.dart`,
  `manual_booking_test.dart`, `mock_pro_service_test.dart` — the three other
  stores and the mock.

### 8.3 Mutations

On committed code, each with an exact-anchor assert, the targeted test watched
red, then `git checkout --`. The list and the result of each are in the commit
message and in §8.4.

### 8.4 What was run, and what was not

Filled in at the end of the build — see the bottom of this file.

## 9. Rollout & scope discipline

No flag: it is a correction. V1 only. It ships in the next Pro build — the one
submitted to App Review and filmed. No backend deploy, no migration.

## 10. Definition of done

- [ ] `flutter analyze` 0 · `dart format` clean on the touched files · the
      targeted tests green.
- [ ] Every new guard watched red.
- [ ] Spec indexed and cross-linked from the code; roadmap entry written.
- [ ] Branch pushed; no PR, no merge, no build from this session.
- [ ] **Seen on a device** — a free slot becoming a booking, on the build that
      is filmed. Not done here.

## 11. Open questions

1. The detail screen's status changes (§1.2) — the same signal could carry
   them; it wants a decision on what the card shows meanwhile.
2. « Accueil »'s pull-to-refresh and its error state with no way out (§1.2).
3. The web's « Calendrier » / « Liste » after a creation from the grid (§1.3).
