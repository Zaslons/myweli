# Deep web ↔ app parity audit — module by module (2026-07)

| | |
|---|---|
| **Goal** | Not just feature presence: entry points · user flow · capabilities · UI states & copy, compared by READING the code on both surfaces (user directive 2026-07-10; supersedes the M8-era [web-parity-audit.md](web-parity-audit.md)) |
| **Method** | Per built module ([MODULES.md](../MODULES.md)): consumer app ↔ consumer web, pro app ↔ pro web. Severity: **❌ missing capability** · **⚠️ flow/UX divergence** · **ℹ️ deliberate adaptation** (fine per `web-design-latitude`). Findings are BIDIRECTIONAL — app gaps count too |
| **Status** | In progress — audited: **1 journal · 2 online-booking · 3 catalogue**. Next: 4 clients · 5 notifications · 8 payments · 9/10 finance+analytics · 11 access · 15 trust |

## Module 1 — `journal` (appointment lifecycle, both roles)

### Consumer: appointment list & detail

| # | Finding | Severity | Detail |
|---|---|---|---|
| 1.1 | **Consumer reschedule (« Reporter ») missing on web** | ❌ web | App detail: pending/confirmed + future → « Reporter » opens the slot picker prefilled (provider/services/artist) → `PUT /appointments/{id}/reschedule` → « Rendez-vous reporté ». Web mon-compte detail has cancel/rebook/review/deposit only — a web user cannot move a booking, only cancel + rebook (loses the salon-side history + deposit linkage) |
| 1.2 | **« Ajouter au calendrier » missing on web** | ❌ web | App: add_2_calendar on future bookings. Web equivalent = a Google-Calendar link and/or `.ics` download — cheap and idiomatic |
| 1.3 | **Deposit proof VIEW (« Voir ma capture ») missing on web** | ❌ web | App: after attaching, the consumer can view their uploaded screenshot (signed URL via `GET /appointments/{id}/deposit-screenshot`). Web (B4-era attach) only shows the text « Justificatif envoyé » |
| 1.4 | Booking `notes` not displayed on the web detail | ❌ web (minor) | App shows a Notes row when present |
| 1.5 | Cancel confirmation copy richer on web | ⚠️ app | Web warns « L'acompte peut ne pas être remboursé selon la politique du salon » when a deposit exists; the app's dialog is a bare « Êtes-vous sûr… » — the app should adopt the deposit warning |
| 1.6 | **App « Appeler » button is a fake** | ❌ app (bug) | Consumer appointment detail's « Appeler » shows « Fonctionnalité à venir » snackbar instead of launching `tel:` (the provider-detail screen does it properly). Web detail has no contact action at all — add `tel:`/WhatsApp to BOTH |
| 1.7 | Tabs & list parity | ✅ | À venir / Passés / Annulés on both; rebook on completed on both (web adds the ?services prefill; the app rebooks via the hub with initial ids — equal) |
| 1.8 | Neither surface shows the chosen **spécialiste** on the consumer detail | ⚠️ both (nicety) | The artistId is stored and used for reschedule prefill, but never displayed to the client |

### Pro: journal / rendez-vous lifecycle

| # | Finding | Severity | Detail |
|---|---|---|---|
| 1.9 | **Cross-day reschedule missing on web pro** | ❌ web | App: Ma journée swipe-left / long-press → « Reprogrammer » → date picker (365 d) + time picker → any day. Web: reschedule exists ONLY as drag inside the single-day journal grid — a salon cannot move a booking to another day on web (no action on the detail page, the panel, or the list) |
| 1.10 | **« Client arrivé » absent from both DETAIL pages** | ⚠️ both | Web: only in the journal side panel. App: only as a Ma journée swipe (the J1b spec §4.2 said the detail screen would gain it — never done). A salon opening the detail can't mark arrival on either surface |
| 1.11 | App gap-slot prefill drops the artist | ❌ app (minor) | J1b spec: « Libre » rows prefill start time **+ the filtered artist** — the code passes only `dateTime` (`pro_journal_screen.dart` `_gap`). The web grid's quick-create DOES carry the column's artist |
| 1.12 | Journal views | ℹ️ | Web = artist-column day GRID (drag, now-line, ghosts) · app = day TIMELINE (swipes, week strip) — deliberate per-surface designs (journal-j1-grid / j1b specs), equivalent capabilities except 1.9 |
| 1.13 | Manual booking | ✅ | Multi-service + note + SMS seam + walk-in on both (web since #196); app entry points: FAB ×2 + gap rows + client card; web: grid cell + header CTA + client card — equal coverage |
| 1.14 | Pro detail extras | ✅ | Both show the deposit justificatif (web: image + « Voir le justificatif »; app: equivalent), the no-show badge, « Voir la fiche (client) » |

### Module 1 — proposed fixes (by priority)
1. **Web consumer « Reporter »** (1.1) — reuse the booking hub's time section as a reschedule picker; PUT reschedule via BFF.
2. **Web pro cross-day reschedule** (1.9) — a « Reprogrammer » action on the web pro detail + journal panel (date+time picker, 409 handling like drag).
3. « Client arrivé » on both detail pages (1.10) + app gap-slot artist (1.11) + app cancel warning (1.5) + app « Appeler » fix (1.6) — small batch.
4. Web add-to-calendar (1.2) + deposit-proof view (1.3) + notes row (1.4) — small batch.

## Module 2 — `online-booking` (consumer discovery · salon page · funnel · favorites · reviews)

### Discovery & search

| # | Finding | Severity | Detail |
|---|---|---|---|
| 2.1 | **« Trier » missing on web search** | ❌ web | App list: sort sheet — Pertinence / Mieux notés / Prix croissant (`ProviderSort`). Web `/recherche` always sorts by rating server-side; the user has no control |
| 2.2 | **« Disponible aujourd'hui » filter missing on web** | ❌ web | App list: a one-tap availability filter pill. No web equivalent |
| 2.3 | Home « À proximité » section missing on web | ⚠️ web | App home: nearby salons + « Voir la carte ». Web home is SEO-first (deliberate) and the map now has « Autour de moi » — but a geolocated « près de chez vous » block on the web home would close the flow gap |
| 2.4 | Announcement stories | ℹ️ | App home's story strip is STATIC promo content (hardcoded assets — a marketing-module V2 seed, not real data). No web port needed until `marketing` builds |
| 2.5 | Map discovery | ✅ | /recherche split view + full-bleed map + app-identical markers + « Autour de moi » (built 2026-07-10); hearts-on-markers deferred on web (noted in web-discovery-map.md) — the app map HAS favorite hearts |

### Salon page

| # | Finding | Severity | Detail |
|---|---|---|---|
| 2.6 | **Gallery lightbox missing on web** | ❌ web (minor) | App: tap any photo → full-screen swipeable viewer. Web `Gallery` = a static grid (29 lines, no interaction); review photos have the same viewer in-app |
| 2.7 | **« Vos rendez-vous ici » personal section missing on web** | ⚠️ web | App salon page shows the signed-in client's bookings AT THIS SALON (+ « Voir tout »). The web page is anonymous-only content; a signed-in web user gets nothing personal |
| 2.8 | Review submit entry point narrower on web | ⚠️ web | App: « Donner votre avis » directly ON the salon page (when a completed visit is reviewable) + from the appointment detail. Web: only from mon-compte detail — a web user browsing the salon page is never invited |
| 2.9 | Sections & SEO | ✅/ℹ️ | Hero, services, équipe, avant/après, horaires, avis, carte (now same map identity), contact — all present on both; web adds FAQ/JSON-LD (SEO latitude) |

### Booking funnel (post-K2)

| # | Finding | Severity | Detail |
|---|---|---|---|
| 2.10 | **Booking notes missing on web** | ❌ web | App confirmation has « Note (optionnel) » sent with the booking (salons see it in the journal). Web confirm step has no notes field and the BFF doesn't forward one |
| 2.11 | **Mobile-web summary not sticky** | ⚠️ web | The app hub pins Total + « Confirmer » at the bottom permanently; on mobile web the summary/CTA is the last block below the sections — scroll required to confirm. `lg:` is sticky; small screens should get the app's fixed bottom bar |
| 2.12 | Hub flow parity | ✅ | Order-free hub, three orderings, capability dim/drop, earliest-slot auto-pick, variants, silent re-validation, deposit sheet — verified at K2 (built 2026-07-10) |

### Favorites & reviews

| # | Finding | Severity | Detail |
|---|---|---|---|
| 2.13 | **Review photos: web can neither SUBMIT nor DISPLAY them (public page)** | ❌ web | App submit sheet attaches photos (picker → upload) and review tiles show them full-screen. Web `ReviewForm` = rating + text only; public `ReviewList` renders no `photoUrls` (the pro « Avis » page does — inconsistent) |
| 2.14 | **Review reporting UI missing on BOTH surfaces** | ❌ both | `POST /reviews/{id}/report` (consumer-only) + the admin moderation queue are LIVE — but neither the app's review tiles nor the web's have a « Signaler » action. FR-REV-005's consumer half was never surfaced |
| 2.15 | Favorites | ⚠️ web | App: hearts on the salon page, the map markers, favorites screen + home strip. Web: heart on the salon page + mon-compte section only — no hearts on /recherche result cards or map markers (deferred), no home strip (ℹ️ SEO home) |

### Module 2 — proposed fixes (by priority)
1. **Web booking notes** (2.10) + **mobile-web sticky summary bar** (2.11) — funnel conversion polish, small.
2. **Web « Trier » + « Disponible aujourd'hui »** on /recherche (2.1/2.2 — sort is already a backend param; available-today needs a query flag or client filter).
3. **Review photos on web** (2.13: display on the public page, then photo attach on the form) + **« Signaler » on both** (2.14 — the backend is waiting).
4. Salon-page personal touches (2.7/2.8) + gallery lightbox (2.6) + result-card hearts (2.15).

## Module 3 — `catalogue` (services · team · media · availability, pro side)

### The headline find

| # | Finding | Severity | Detail |
|---|---|---|---|
| 3.1 | **Per-service artist restriction (`artistIds`) is settable NOWHERE** | ❌ **both** | The backend accepts `artistIds` on service create/update, the booking hub dims incompatible stylists with it, and the K1 capacity engine computes the capable pool from it — but NO surface has UI to set it: the app's service form has no artist picker, the web catalogue form has none, and the artist forms assign no services. **The entire capability rule can only ever fire on seed data.** Same class of forget as the map pin (L1) |

### Services

| # | Finding | Severity | Detail |
|---|---|---|---|
| 3.2 | **Duration variants (court/moyen/long) missing on web** | ❌ web | App service form: full variant editor (three duration fields behind a toggle). Web catalogue form: name/description/price/priceMax/duration/active only — a web-managed salon can never offer hair-length variants, though the WEB booking hub renders them (K2) |
| 3.3 | Core fields | ✅ | name · description · price + priceMax · duration · active toggle on both; create/edit/delete on both |

### Team

| # | Finding | Severity | Detail |
|---|---|---|---|
| 3.4 | **Per-staff working hours missing on web** | ❌ web | App artist form: custom weekly-hours editor (feeds the K1 engine — `_hoursCover`). Web Équipe form = name + specialization only (the 7.3b deferral was never picked back up, and it now matters: the capacity engine reads those hours) |
| 3.5 | **Artist photo missing on web** | ❌ web (minor) | App: avatar upload on the artist form. Web: no imageUrl field |

### Media

| # | Finding | Severity | Detail |
|---|---|---|---|
| 3.6 | **Photo reorder missing in the APP** | ❌ app (minor) | Web Médias: move up/down (the first photo is the listing hero — order matters). App photos screen: upload/remove only |
| 3.7 | Before/After | ✅ | Pair upload + optional caption + delete on both |

### Availability

| # | Finding | Severity | Detail |
|---|---|---|---|
| 3.8 | **Breaks (« Pauses ») editor missing on web** | ❌ web | App: a recurring-pause editor per day (ex. déjeuner) — breaks feed the slot engine AND the journal grid's hatched zones. Web Disponibilités edits hours/tampon/dates bloquées; the `breaks` field is in its type but has NO UI |
| 3.9 | Hours/buffer/blocked dates | ✅ | Multi-slot weekly hours, tampon, dates bloquées round-trip on both |

### Profile
Fresh parity as of L1/L2 (2026-07-10): both surfaces edit every allowlisted field + category + the map pin. ✅

### Module 3 — proposed fixes (by priority)
1. **`artistIds` UI on BOTH surfaces** (3.1) — an artist multi-select on the service form (app + web); without it the capability rule and the per-artist capacity math are decorative for real salons.
2. **Web: per-staff hours** (3.4) + **breaks editor** (3.8) — the two remaining inputs the K1 slot engine reads that web salons can't set.
3. **Web: duration variants** (3.2) + artist photo (3.5).
4. App: photo reorder (3.6).
