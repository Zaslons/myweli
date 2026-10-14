# « Ma journée » shows the booking the salon just created

| | |
|---|---|
| **Status** | **Approved** (owner, 2026-10-13 — decision 2 of `pro-app-preview.md` §9: « fix it, build once more, and film that build ») — **built 2026-10-13** on `fix/journal-shows-new-booking`, **reviewed the same day and corrected** (§8.5). **Not merged, not in a build, not seen on a device.** What was run and what was not: §8.4, §8.5. |
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
there until the list is pulled down. The build that goes to App Review is to
carry the fix, and the App Preview film is to be shot on it: a free slot
becomes a booking, in one take, with no pull-to-refresh. Neither is true yet —
see the Status row.

**In scope**: the Pro app (`mobile/`, entry `lib/main_pro.dart`) — every screen
that shows the salon's bookings and is still mounted, or still cached, when a
booking is created.

**Out of scope**: the backend (no route, no DTO changes); the consumer app; any
new visual; the web (§1.3 — its day view already reloads).

### 1.1 The defect, as verified

Read in the code at `3d88d0e1` — every line number in this file is that
commit's — **then observed** in a widget test that drives the real screens
(§8.1: nine of its ten cases red before the fix, the control green):

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
  it calls the same `loadDashboardStats`, which returns early. Observed at the
  provider (`pro_dashboard_booking_created_test.dart`, first case: a second
  load asks the service for nothing); not observed on the screen. Not fixed here,
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
| **An older request answers late** (a pull-to-refresh or a day change sent before the `201`) | Ignored — its answer, and its **failure** too (a request that errors out long after a newer one has answered). Every day request carries a sequence number and only the newest is applied — otherwise an answer computed before the booking existed would erase it, and a late failure would drop the day. This also closes a race that was already there: two quick day changes, the slower answer winning. |
| **A refresh of the displayed day was in flight when the booking was created** — a pull-to-refresh still unanswered, the refetch behind a swipe action, « Ma journée » reopened (its first load keeps the rows of the last visit). It takes a request slower than filling the form: a network that is already failing | Exactly §2.1 step 4: the rows on screen are that day's, so the booking joins them **at once**. The quiet reload outdates the refresh in flight — its late answer is ignored, and when both fail the day and the booking stay and nothing is said. The pull's own indicator, if it is still showing, stays until its request ends (read in `BrandRefresh`, not looked at). *Before the review this state took the loud path of the last row: the booking was withheld until the server answered, and a failure replaced the whole day with « Une erreur est survenue » (§8.5).* |
| **A day change was in flight when the booking was created** (the date was changed, « Nouveau » tapped before the new day landed) | The rows on screen are the **previous** date's: no row is added to them, also when the booking is for the date being loaded. That date is asked for again, the ordinary way; its dot is there at once. If that load fails it is the error state of a failed day change, with « Réessayer » — there is no day of that date to keep. |
| **The day's first load was still in flight, or had failed, when the booking was created** (« Nouveau » is reachable in both states) | There is no day to add a row to. It is loaded again, the ordinary way: the loader, then the day — or its error state with « Réessayer », where the booking cannot be shown because no day is. |
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
| `ProJournalProvider` | adds the booking to the displayed day when it is that day's; bumps that day's dot; reloads the day quietly. It keeps which salon day its rows were loaded for (`_dayKey`, written with `_day` — not read from the server's `JournalDay.date`): a refresh of that day in flight is treated like a settled day, and only a day *change* in flight, or no day at all, takes the ordinary loud load |
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
`ProSalonScope.track`, as `main_pro.dart` does, and a source pin (comments
stripped) holds that every provider naming `ShowsSalonBookings` is tracked in
`main_pro.dart`, and that the announcement has exactly one caller.

**What none of this can see.** A future store that shows bookings and does
*not* implement `ShowsSalonBookings` is not told — which is this defect again,
one store later — and no test can know that it should have been. The contract
makes the right thing one line; it does not make the wrong thing fail. The
pin is on text, too: nothing here pumps `MyweliProApp` itself.

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

**The journal store pays this also when « Ma journée » is not on the stack** —
a booking made from the client card, reached from « Accueil »: the day and the
six prefetch requests are sent for a screen that loads again, loudly, at its
next visit (`pro_journal_screen.dart:49`). About ten light requests after one
creation on that path. **Read, not measured; left on purpose**: the way to skip
them is to ask `hasListeners`, and a store whose behaviour depends on whether
someone listens turns every provider test that forgot a listener into a test of
another path.

## 8. Testing plan

### 8.1 Widget — the real flow (`test/widget/pro_journal_shows_new_booking_test.dart`)

The journal screen, the form, `ProRouter`'s own two `GoRoute`s (so the « Libre »
prefill travels through the real `extra`), the real providers registered with
`ProSalonScope.track`; one fake salon whose journal and whose `POST` answer
from the same list. No test calls `refresh()`, drags the journal once the form
is open, or starts with the booking already in the stub; every assertion about
the day is scoped to the card keyed by the booking's id — the client's name is
also in the form's text field while the form slides away. One case does drag:
a pull, *before* the form is opened and with every answer held. That pull is
the situation under test, and it ends in a failure — it cannot be what shows
the booking.

Twelve cases.

| Case | What it holds |
|---|---|
| A « Libre » row → form → create | one frame after the answer, **form still on screen**, reload **held**: the card exists, at 12:00–12:30, « Confirmé », between its neighbours; « Libre — 12:00 » gone, « Libre — 12:30 » there; the old rows still there — which is also « no loader », since the screen draws its loader *instead of* the list; the day was asked for exactly once more. Then the server answers and wins (its name, another device's booking). |
| « Nouveau » → pick a date and an hour → create | the card is first in the day |
| The date is changed in the form | still « Aujourd'hui », no card, « Libre — 12:00 » still there, the 13th gets its dot while the reload is held |
| Filter « Awa » + « Nouveau » | no card under « Awa »; « Sans artiste » appears and shows it; a cancelled row stays hidden |
| Filter « Awa » + a « Libre » row | the card is shown (the artist travelled) |
| The reload fails — refusal, then thrown | the card stays, the old rows stay, no error state, no « Réessayer », no error text |
| **A pull-to-refresh is still in flight** — refusal, then thrown (added after the review, §8.5) | the list is pulled down, its request held; then the form. One frame after the answer the card is there, « Libre — 12:00 » gone, the day asked for once more. Then both requests fail: the card and the old rows stay, no error state, no « Réessayer », nothing retried |
| **Control**: the creation is refused | the form keeps the refusal, no snackbar, the day is not asked for again, nothing changed after going back |
| The scroll position | a scrolled day keeps its offset through the whole flow |
| Two taps in one frame | one request, one booking, one pop |

### 8.2 Unit

| File | Cases | What it holds |
|---|---|---|
| `pro_salon_scope_booking_created_test.dart` | 14 | only tracked `ShowsSalonBookings` stores are told, once; a throwing store does not stop the others and nothing escapes; neither does a store that registers another store while being told; `createManualBooking` announces on success, once, **before it returns**, with the server's answer — also when the agenda's own list does not take the booking — and never on a refusal or a thrown error; a throwing store does not turn a success into a failure; every provider naming `ShowsSalonBookings` is `ProSalonScope.track`ed in `main_pro.dart`, and the announcement has one caller (comments stripped) |
| `pro_journal_booking_created_test.dart` | 29 | same day (at once, in order, no loader, one request) · the server wins, and its day reaches the listeners when it lands, not after the week prefetch · a reload without the booking removes it · refused / thrown reload keeps everything · `forbidden` still reaches `ProAccessGuard` · twice · empty day · both filters · another day and its dot · the salon timezone decides the day · a count asked before the booking cannot overwrite its dot · never opened / another salon / after a switch · the first load still in flight, a day change in flight, the error state (the retry counted, its own failure read) · a refresh of the displayed day in flight: the booking joins at once, the flag is lowered, both requests failing keeps the day, « Ma journée » reopened · a late older answer is dropped (three orders), and a late older **failure** too |
| `pro_dashboard_booking_created_test.dart` | 14 | refetched and replaced with no loader and never blank · refused / thrown keeps the figures and the next pull asks again, quietly, until confirmed · `forbidden` still reaches `ProAccessGuard` · the figures had failed to load: nothing is asked · another salon · never loaded · a load in flight is followed by one refetch — and when that load fails, the retry is one request · the older of two refetches cannot win · asked for another salon while a refetch is in flight · a salon switch, and `clearStats`. Its first case is a **known defect, recorded and not endorsed** (« Accueil »'s pull-to-refresh, §1.2): the repair turns it red |
| `pro_clients_booking_created_test.dart` | 9 | reloaded for the card's client, no loader, never blank, visits too · someone else, no number, another salon: untouched · no card open · refused / thrown keeps the card · `forbidden` still reaches `ProAccessGuard` · a salon switch drops the reload in flight · another card opened meanwhile, during the card request and during the visits request |
| `manual_booking_test.dart` (+8) | | the agenda's loaded filter: status, both date bounds, inclusive, each of the three forgotten on a salon switch |
| `mock_pro_service_test.dart` (+2) | | the mock answers with the booking's length |

The fakes answer like a server: **what they say is decided when the request
arrives** and may be delivered later — that is what makes « an answer computed
before the booking existed » a test and not a comment.

### 8.3 Mutations

*This section is the first round, on the code as it stood at `84c81a66`. The
review then ran its own, found lines these had missed, and one of the rows
below pinned a behaviour that has since been changed — §8.5.*

56, and one control, each on committed code, each with an exact-anchor assert
(a mutation that does not apply is no result), the targeted test files run,
then `git checkout --` and a clean-tree check.

| Area | What was broken on purpose | Result |
|---|---|---|
| The announcement and the wiring (7) | removed (the defect itself — 9 of the 10 flow cases red, the control green); made after the method returned; a throwing store not caught; only the first store told; the journal, then the home store, no longer tracked in `main_pro.dart`; not made when the agenda's list does not take the booking | 7 red |
| `ProJournalProvider` (20) | not added to the day; added whatever its day; no dot; no reload; the loud reload; a refused / thrown reload drops the day or raises the error; `forbidden` not reported; the answer merged instead of applied; the filter reset; « Voir les annulés » switched on; three sequence checks removed, one at a time — **the provider has four**, and the one in `load`'s `catch` was not among them (§8.5); the switch not outdating; whose booking not checked; added twice; the fallback ignoring a load in flight (*the behaviour this one held — a refresh in flight withholds the booking — is the one the review had changed*, §8.5); the fallback asking for nothing | 20 red |
| `ProDashboardProvider` (9) | nothing done; the loud reload; a refusal drops the figures; stale figures not asked for again; never un-staled; whose booking not checked; a load in flight not followed; an older refetch winning; the switch not outdating | 9 red |
| `ProClientsProvider` (9) | nothing done; the loud reload; any booking reloads the card; the salon not checked; a refusal drops the card; each of the two sequence checks removed; another card not outdating; the visits not replaced | 9 red |
| The agenda's filter (5) | each of the three tests removed; an exclusive bound; kept across a salon switch | 5 red |
| The form (1) | the in-flight guard removed | red |
| The mock (2) | no duration; no 30-minute floor | 2 red |
| The wiring pin itself (3 + a control) | the journal store un-tracked **with a comment quoting the line left behind**; a second caller of the announcement (the form announcing too); the announcer un-tracked. **Control**: the journal store's header rewritten `implements SalonScoped, ShowsSalonBookings` — the pin must still list it | 3 red; the control green, as it must be |

**Two of the first 53 survived their first run, and each named a real gap** —
closed by a test, then run again red:

- *not announced when the agenda's list does not take the booking*: nothing
  held that the announcement is independent of the tab the agenda was left on.
  Leave it on « En attente », create a « Confirmé » booking from « Ma journée »
  — the day would have missed it again.
- *the client card's first sequence check removed*: the outdated answer was
  still dropped by the second check, after one request too many.

### 8.4 What was run, and what was not

*The table is the first round, at `84c81a66`; the run on the corrected code is
in §8.5. The « not run » list under it still holds, word for word.*

**Run** (macOS, Flutter 3.44.9, targeted files only — the Mac is shared):

| Command | Result |
|---|---|
| `flutter test test/widget/pro_journal_shows_new_booking_test.dart` on the code before any fix (commit `e4278fc0`) | **+1 −9** — the control green, the nine others red |
| the same after the journal fix alone | +9 −1 (« two taps in one frame »: 2 requests for 1) |
| the same after the form's guard | **+10** |
| `flutter test test/unit/manual_booking_test.dart` before the agenda's filter | +6 −3 |
| 24 files, on the final code — the seven new or changed test files, every other test file that touches the changed providers and screens, and `test/a11y/layout_test.dart` (the width and text-scale gate, which covers the journal and the form: 115 of the cases) | **+407 ~14**, all passed (the 14 skipped are the Pro goldens, which only run on Linux) |
| `flutter analyze` (the package) | 0 issues |
| `dart format --set-exit-if-changed` on the touched files | clean |
| 56 mutations and one control | §8.3 |

**Looked at**: three pictures rendered from the flow test on this Mac (real
fonts, 390 × 844) — the day before; the form leaving, 120 ms into the
transition, with the reload held; the day after. The card « 12:00 – 12:30 ·
Yao K. · Confirmé » sits between its neighbours in the second one already,
« Libre — 12:30 » under it; in the third, « Rendez-vous créé » stands above
« Nouveau ». Throwaway files: not goldens, not committed.

**Not run, not seen — nothing below is claimed:**

- **No device, no simulator, no build.** That the booking is on screen
  « before the form starts to leave » is asserted in a widget test, one frame
  after the answer with the form still in the tree — not watched on a phone.
- **Not against the real API.** What the `201` carries is read in
  `booking_service.dart`; the fake salon is written from that reading.
- **The full suite** was not run (shared Mac); CI runs it on the pull request.
- **Goldens**: nothing visual changed and no golden test creates a booking, so
  none should move — **not verified**, they are skipped on macOS.
- **The web**: read only (§1.3).
- **A screen reader**: the snackbar is the announcement, as before; not
  listened to.

### 8.5 After the review

Two reviewers read the branch at `84c81a66` the same day, each with mutations
and throwaway probes of their own. Eleven distinct findings, none above
« minor ». Each was first reproduced or re-read here; what it came to:

| Finding | Real? | What was done |
|---|---|---|
| **A refresh of the day in flight when the booking is created**: the booking is withheld and the slot still offered as « Libre »; if that refresh fails, the whole day is replaced by « Une erreur est survenue » | **Yes — observed** at the provider before the change: at once `shown=[a1] isLoading=true`; after the failure `day=null error=Erreur réseau. Réessayez.` | **Fixed** (§2.4, §5): the loud path is kept for « no day » and « a day change in flight » only |
| The sequence check in `load`'s `catch` — the fourth of four — is held by no test | Yes | A case: an older request that throws after a newer answer is on screen. Red without the line |
| Nothing fails if the server's day reaches the listeners only after the week prefetch | Yes | A case that delivers the day's answer alone and counts the notification while the prefetch is held |
| « `forbidden` still reaches `ProAccessGuard` » is held for the journal only | Yes | One case for the home figures, one for the client card |
| Six more lines no test fails without (the registry's copy, the agenda's two dates on a switch, the card's switch, three in the home store) | Yes | Eight of the nine lines are now held by a case each. The ninth cannot be: `_stale = false` in `clearStats` — like its twin in `resetForSalonSwitch`, which the review did not name. Nothing can act on that flag before the next load, which after either reset is a loud one and lowers it itself. Both kept: a reset that leaves one field as it was would need a paragraph to justify, and these need none |
| « …and when that load fails too » cannot tell « tried and failed » from « never tried » | Yes | It counts the request, sees the loader, and reads the new failure's own sentence |
| The flow test's three « no loader » lines cannot be the line that fails | Yes — the screen draws its loader *instead of* the list | Removed; §8.1 says what holds the property |
| A dashboard case pins as expected what §1.2 lists as a defect | Yes | The case is named a known defect, recorded and not endorsed, and says which two assertions the repair will turn red |
| Two sentences stated as fact what only a merge and a build make true (§1, §9) | Yes | Stated as intent |
| Web: « Calendrier » and « Liste » keep the old list after a creation from a grid cell, a drag or a panel action | Yes — **read, not run** (`setItems` at `RendezVousClient.tsx:79` and `:349` only; the grid is given `loadJournal`) | **Left** (§1.3, §11.3): the day view is right; the repair covers three triggers, wants a request-order guard of its own, and the page has no component test to add a case to — its own change, with its own spec'd tests |
| The journal store reloads the day and the week also when « Ma journée » is not on the stack | Yes — read | **Left** (§7), with the reason |

**Mutations, this round — 34**, on committed code, with the same harness rules
as §8.3 (exact-anchor assert, targeted files, `git checkout --`, clean tree
before and after):

| Area | What was broken on purpose | Result |
|---|---|---|
| The fix itself (4) | the old condition put back (loud whenever `isLoading`) — the four new unit cases and the two new flow cases red, the flow ones at « Found 0 widgets with key 'm1' »; the flag the refresh raised not lowered; `_dayKey` never written (23 red: every creation falls to the loud path); a day change not told apart from a refresh (the booking lands among another date's rows) | 4 red |
| The guards the review asked for, journal (3) | the `catch`'s sequence check removed (3 red, the flow's « thrown » case among them); no notification when the quiet day lands; the fallback asking for nothing (4 red — « when that load fails too » now among them) | 3 red |
| The lines around the rewritten block, run again (11) | not added to the day; added whatever its day; no quiet reload; a loud reload in its place; no notification after the row; the quiet reload not outdating what is in flight; no dot; added twice; whose booking not checked; a refused quiet reload dropping the day; the success-path sequence check removed | 11 red |
| The other stores (14) | `forbidden` not reported — home, then card; the registry walked without a copy (`ConcurrentModificationError`); a switch keeping the agenda's start date, its end date, its status; the card's switch not outdating; a refetch behind a failed home load; a loud home load keeping the stale flag; not outdating the refetch in flight; both; `clearStats` not outdating; `clearStats` without either of its two lines; the switch not outdating (a control: red before too) | 14 red |
| The two that cannot be held (2) | `_stale = false` removed from `clearStats`; from `resetForSalonSwitch` | **2 survived — equivalent**, as said above |

Two of the new cases were then asked which change turns them red — a defect or
a repair (`352982e8`): the card's switch case no longer breaks the day a switch
clears the card, and the failed-home-load case says it records a boundary.
Their two mutations were run once more on the adjusted cases: red both times.

**Run on the corrected code** (macOS, Flutter 3.44.9, targeted files only):

| Command | Result |
|---|---|
| The seven new or changed test files | **+93** — 12 flow, 29 + 14 + 14 + 9 unit, `manual_booking_test` 11, `mock_pro_service_test` 4 (88 of the 93 are this branch's) |
| 24 files — those seven and every other test file that names a changed provider, the registry, the form or the journal screen, `test/a11y/layout_test.dart` and the Pro goldens among them | **+407 ~14**, all passed (the 14 skipped are the Pro goldens, Linux only). *Not the same 24 as §8.4's, whose list was not kept: the seven files alone went from 75 to 93, so the equal total is a coincidence, not a sign that nothing was added* |
| 13 source-pin files that scan `lib/` (design system, French, route literals, motion, content width, titles, status labels, contrast…) | +215 |
| `flutter analyze` (the package) | No issues found |
| `dart format --set-exit-if-changed` on the 15 Dart files the branch touches | 0 changed |

**Still not run, not seen**: everything §8.4 lists — no device, no simulator, no
build, not the real API, not the full suite, not the goldens, not the web. The
pull-to-refresh case is a drag in a widget test that reports `android`; the
indicator of a real pull, held open by a request that never answers, was not
looked at on a phone.

**Found while probing, not this slice** (§11.4): the home store's *loud* load
has no request order at all. A probe held salon 1's first load, switched,
loaded salon 2, then released salon 1: `today=2`, then `today=1` — salon 1's
figures under salon 2. Read, not run: they stay, because the next load finds
figures for that salon and returns early. The same lines are on `main` at
`3d88d0e1`. It takes a salon switch while « Accueil » is still loading.

## 9. Rollout & scope discipline

No flag: it is a correction. V1 only. It is meant to ship in the next Pro
build — the one to be submitted to App Review and filmed; until the branch is
merged and that build exists, it ships nowhere (Status row). No backend
deploy, no migration.

## 10. Definition of done

- [x] `flutter analyze` 0 · `dart format` clean on the touched files · the
      targeted tests green (§8.4).
- [x] Every new guard watched red (§8.1 before the fix; §8.3 and §8.5 by
      mutation — two lines of §8.5 cannot be held, and it says which).
- [x] Spec indexed and cross-linked from the code; roadmap entry written.
- [x] Branch pushed; no PR, no merge, no build from this session.
- [ ] The full suite and the goldens, on CI, once a pull request exists.
- [ ] **Seen on a device** — a free slot becoming a booking, on the build that
      is filmed. Not done here.

## 11. Open questions

1. The detail screen's status changes (§1.2) — the same signal could carry
   them; it wants a decision on what the card shows meanwhile.
2. « Accueil »'s pull-to-refresh and its error state with no way out (§1.2).
   Whether a created booking should also be the retry of a home load that
   failed belongs here: today it asks for nothing, and a test says so.
3. The web's « Calendrier » / « Liste » after a creation from the grid (§1.3).
4. The home store's loud load has no request order: a salon switch while
   « Accueil » is still loading can leave the previous salon's figures under
   the new one (§8.5 — observed at the provider on this branch; the same
   lines are on `main`). The quiet refetch added here is ordered; the load it
   sits beside is not.
