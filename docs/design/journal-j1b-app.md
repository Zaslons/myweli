# Journal J1b — the pro-app day timeline (mobile-first « Ma journée »)

| | |
|---|---|
| **Module** | `journal` — slice **J1b** (app) of [docs/modules/journal.md](../modules/journal.md) (§4.3; signed off 2026-07-08) |
| **Status** | **Signed off** (2026-07-09) — §8 resolved: flutter_slidable for swipes (+ long-press a11y fallback) · 7-day count prefetch · timeline is the phone default |
| **Scope** | The salon owner's day-at-a-glance ON A PHONE — the mobile-first equivalent of the web « Journée » grid (J1b web, Built). **App only** — the backend (J1a) is already live: it consumes `GET /providers/{id}/journal`, `arrive`, and reschedule-with-`artistId` unchanged |
| **Out of scope** | Any backend change · a cramped desktop-style grid on the phone (deliberately — see §1) · waitlist (J3) · group/recurring (J4) |
| **Decisions inherited** | 15-min semantics · « Client arrivé » in-day status · « Sans artiste » kept · badge 1-neutral/≥2-red — all locked at the journal §10 sign-off |
| **Cross-refs** | [journal-j1-grid.md](journal-j1-grid.md) (the web sibling) · [clients-c1.md](clients-c1.md) (badge + prefill) · `docs/api/openapi.yaml` (`/providers/{id}/journal`, `/appointments/{id}/arrive`) |

## 1. Goal & the mobile-first principle

The web grid packs artist columns side-by-side; a 360 px phone can't. YCLIENTS's
own phone app doesn't cosplay the grid either — it shows a **vertical day
timeline**. So J1b-app is « Ma journée »: the owner opens the app and scrolls
one column of time, filtered by artist, with the same information and the same
actions as the grid — just laid out for a thumb. No horizontal artist columns,
no drag-on-a-grid.

## 2. Ground truth (already built)

- Backend: `GET /providers/{id}/journal?date=` (one payload: hours+breaks,
  artists, enriched day), `POST /appointments/{id}/arrive`, reschedule with
  optional `artistId` — all live (J1a, #188).
- App: `Appointment` model already carries `salonClientId` /
  `clientNoShowCount` / `arrivedAt` / `artistId` / `durationMinutes` (C1c +
  J1a); `ProAppointmentProvider` + `ProServiceInterface` have accept/reject/
  complete/no-show/reschedule/manual-booking; the accept-moment badge is on
  the pro appointment rows + detail. **Missing:** a `journal` fetch, an
  `arrive` call, and the timeline screen itself.

## 3. User stories (from journal.md §3, phone-shaped)

1. Morning open → « Ma journée »: every booking today, top-to-bottom, who
   hasn't confirmed flagged.
2. Client walks in → swipe/ tap **« Arrivé »**; at the end **« Terminé »**.
3. Filter to one artist (Awa) to see just her day.
4. A gap at 14 h → tap the **« Libre »** slot → manual booking prefilled at 14 h.
5. Reschedule Thursday's braids → long-press → « Reprogrammer » → slot picker,
   ≤3 taps.
6. Glance the week strip to see which days are busy.

## 4. UX — « Ma journée » (new screen `screens/provider/journal/`)

**Entry:** the pro dashboard tile « Rendez-vous » → this screen becomes the
salon's default appointment view (the existing calendar/list stays reachable
via a top toggle « Journée · Agenda », mirroring the web's Journée/Calendrier/
Liste — nothing removed).

### 4.1 Header
- **Date row:** ‹ ›, the date (« Aujourd'hui » / « lun. 13 juil. »), a calendar
  icon → date picker; « Aujourd'hui » shortcut when off today.
- **Week strip:** 7 day-pills (Lun–Dim) under the date, each with a load dot
  whose size/opacity ∝ that day's booking count; tap a pill to jump. (A cheap
  week overview without a week grid — reuses the journal day-count idea; the
  strip fetches counts lazily or derives them from a light 7-day prefetch —
  implementation choice, budget-bound.)
- **Artist filter chips:** horizontally scrollable — « Tous » (default) · one
  avatar chip per artist · « Sans artiste » when the day has unassigned
  bookings. Selecting filters the timeline client-side (the day payload already
  holds every artist's bookings).

### 4.2 Timeline body
- The day's bookings **time-ascending** as cards. Each card: time range
  (« 09 h 00 – 10 h 00 »), client name, service(s), artist avatar/name, the
  **status chip** (En attente/Confirmé/**Arrivé**/Terminé/Annulé/Non présenté —
  the one colour language from the grid), a deposit badge (₣) when paid, and
  the **no-show badge** (« 1 absence » neutral / « 2 absences » red) beside the
  client — the accept-moment signal, on the timeline too.
- **Free-gap slots:** between consecutive cards, a gap ≥30 min renders a slim
  tappable **« Libre — 14 h 00 › »** row → `/pro/appointment/new` prefilled
  with that start time (+ the filtered artist, if one is selected). Story #4.
- Cancelled bookings hidden by default; a header overflow action « Voir les
  annulés » shows them as muted/strikethrough cards (matches the grid toggle).
- Tapping a card → the existing **pro appointment detail** screen (already has
  the badge + « Voir la fiche client »); this screen adds the **« Client
  arrivé »** action to that detail's confirmed-state buttons (see §5).

### 4.3 Quick actions (per card)
- **Swipe right** → the state-appropriate positive action: confirmed →
  « Arrivé » (first swipe) then « Terminé »; pending → « Accepter ».
- **Swipe left** → « Reprogrammer » (the existing slot-picker flow, prefilled).
- **Long-press** → an action sheet with the full set (Accepter/Refuser ·
  Arrivé · Terminé · Non présenté · Reprogrammer) — discoverability + a11y,
  since swipes aren't announced. Guards mirror the app/grid (Terminé before end
  time confirms; Non présenté only after start).
- Optimistic update with rollback + a snackbar on failure (« Créneau
  indisponible » on a 409 reschedule).

### 4.4 States (all four, per the guardrails)
- Loading = timeline skeleton (BrandLoader).
- Empty day = the axis-free « Aucun rendez-vous ce jour » + « + Nouveau
  rendez-vous » (→ manual booking at the next quarter-hour).
- Error = retry block.
- Pull-to-refresh = BrandRefresh (mark loader), like every list.

## 5. Layering (interface → mock → API → provider → screen)

- **`ProServiceInterface`** += `getJournalDay(providerId, DateTime date)` →
  `ApiResponse<JournalDay>` and `arriveAppointment(id)` → `ApiResponse<bool>`.
  (`JournalDay` = a new model mirroring the DTO: `date`, `hours?`
  {open, close, breaks[]}, `artists[]`, `appointments: List<Appointment>`.)
- **Mock** (`mock_pro_service.dart`): a realistic seeded day (a couple of
  artists, a few bookings incl. one with prior no-shows, a mid-day gap) with
  latency; `arrive` flips `arrivedAt`. Powers the widget tests.
- **API** (`api_pro_service.dart`): `GET /providers/{id}/journal?date=` and
  `POST /appointments/{id}/arrive` via the provider `RefreshingHttpClient`.
- **`ProJournalProvider`** (new ChangeNotifier): `day`, `selectedDate`,
  `artistFilter`, `showCancelled`, loading/error; `load(providerId, date)`,
  `setDate`, `setArtist`, `arrive/accept/complete/noShow/…` delegating to the
  existing provider actions then refetching the day. (Reuse
  `ProAppointmentProvider`'s action methods where they exist — add `arrive`.)
- **Screen** `screens/provider/journal/pro_journal_screen.dart` +
  a `_TimelineCard` + `_WeekStrip` + swipe via **`flutter_slidable`** (new
  dependency, approved 2026-07-09): rich swipe panels — right-swipe reveals the
  state-appropriate positive action(s), left-swipe reveals « Reprogrammer ».
  A **long-press action sheet** with the full set stays as the discoverable +
  accessible fallback (swipes aren't announced to screen readers).
- Router: `/pro/journal` (default target of the « Rendez-vous » tile); the
  existing list/calendar stays at its route behind the toggle.

## 6. Security / performance / tests

- Security: nothing new — same provider session + the J1a ownership boundary
  (T41); no client PII beyond what the appointment already carries. Actions hit
  the same guarded endpoints (T42/T43).
- Performance: one journal fetch per day; filter/toggle are in-memory; the
  timeline is a `ListView.builder`; week-strip counts are a light prefetch or
  derived — keep within the low-end Android budget; `const` where possible.
- Tests: `flutter analyze` 0; unit (JournalDay parse; ProJournalProvider load/
  filter/date/arrive incl. mock error path); widget (timeline renders cards +
  badges + gap slots; empty/error/loading; swipe → arrive; artist filter;
  cancelled toggle; tap → detail); mock realism (latency + a 409 on a clashing
  reschedule). Target: the full mobile suite stays green (+~15).

## 7. Rollout — one PR

| PR | Contents | Gate |
|---|---|---|
| J1b-app | `JournalDay` model · interface+mock+API `getJournalDay`/`arrive` · `ProJournalProvider` · `ProJournalScreen` (+ timeline card, week strip, gap slots, swipe/long-press, arrive on the detail) · router default · tests | analyze 0 · full mobile suite green |

After merge: journal.md status note (app timeline ✅), MODULES.md §1, ROADMAP.
Conventional commit `feat(journal): …`; user merges.

## 8. Decisions (user sign-off, 2026-07-09)

1. **Swipe: add `flutter_slidable`** — rich swipe panels (right = positive
   action(s) by state, left = Reprogrammer), YCLIENTS-style. The **long-press
   action sheet** with the full action set ships alongside as the discoverable
   + accessible fallback (swipes aren't announced to screen readers).
2. **Week strip: one 7-day count prefetch** on screen open fills all dots (a
   single light call / reuse of the appointments list); dots are non-critical
   context.
3. **Timeline is the phone default** — the « Rendez-vous » tile opens
   `/pro/journal`; the existing calendar + list stay one tap away behind the
   « Journée · Agenda » toggle (nothing removed), matching the web making
   « Journée » default.
