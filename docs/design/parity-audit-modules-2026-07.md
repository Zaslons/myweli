# Deep web ↔ app parity audit — module by module (2026-07)

| | |
|---|---|
| **Goal** | Not just feature presence: entry points · user flow · capabilities · UI states & copy, compared by READING the code on both surfaces (user directive 2026-07-10; supersedes the M8-era [web-parity-audit.md](web-parity-audit.md)) |
| **Method** | Per built module ([MODULES.md](../MODULES.md)): consumer app ↔ consumer web, pro app ↔ pro web. Severity: **❌ missing capability** · **⚠️ flow/UX divergence** · **ℹ️ deliberate adaptation** (fine per `web-design-latitude`). Findings are BIDIRECTIONAL — app gaps count too |
| **Status** | In progress — audited: **1 journal · 2 online-booking · 3 catalogue · 4 clients · 5 notifications**. **COMPLETE** — all built modules audited (1 · 2 · 3 · 4 · 5 · 8 · 9/10 · 11 · 15; modules 6/7/12/13/14 are unbuilt V2/V3 on every surface — nothing to compare). Synthesis at the end |

## Module 1 — `journal` (appointment lifecycle, both roles)

### Consumer: appointment list & detail

| # | Finding | Severity | Detail |
|---|---|---|---|
| 1.1 | ~~Consumer reschedule (« Reporter ») missing on web~~ **FIXED 2026-07-10** (mon-compte detail: « Reporter » → date + slot picker prefilled provider/services/artist → POST reschedule; 409 handled) | ✅ fixed | App detail: pending/confirmed + future → « Reporter » opens the slot picker prefilled (provider/services/artist) → `PUT /appointments/{id}/reschedule` → « Rendez-vous reporté ». Web mon-compte detail has cancel/rebook/review/deposit only — a web user cannot move a booking, only cancel + rebook (loses the salon-side history + deposit linkage) |
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
| 1.9 | ~~Cross-day reschedule missing on web pro~~ **FIXED 2026-07-10** (« Reprogrammer » date+heure on the pro detail page AND the journal panel; 409 → créneau indisponible) | ✅ fixed | App: Ma journée swipe-left / long-press → « Reprogrammer » → date picker (365 d) + time picker → any day. Web: reschedule exists ONLY as drag inside the single-day journal grid — a salon cannot move a booking to another day on web (no action on the detail page, the panel, or the list) |
| 1.10 | **« Client arrivé » absent from both DETAIL pages** | ⚠️ both | Web: only in the journal side panel. App: only as a Ma journée swipe (the J1b spec §4.2 said the detail screen would gain it — never done). A salon opening the detail can't mark arrival on either surface |
| 1.11 | App gap-slot prefill drops the artist | ❌ app (minor) | J1b spec: « Libre » rows prefill start time **+ the filtered artist** — the code passes only `dateTime` (`pro_journal_screen.dart` `_gap`). The web grid's quick-create DOES carry the column's artist |
| 1.12 | Journal views | ℹ️ | Web = artist-column day GRID (drag, now-line, ghosts) · app = day TIMELINE (swipes, week strip) — deliberate per-surface designs (journal-j1-grid / j1b specs), equivalent capabilities except 1.9 |
| 1.13 | Manual booking | ✅ | Multi-service + note + SMS seam + walk-in on both (web since #196); app entry points: FAB ×2 + gap rows + client card; web: grid cell + header CTA + client card — equal coverage |
| 1.14 | Pro detail extras | ✅ | Both show the deposit justificatif (web: image + « Voir le justificatif »; app: equivalent), the no-show badge, « Voir la fiche (client) » |

### Module 1 — proposed fixes (by priority)
1. ~~**Web consumer « Reporter »** (1.1)~~ ✅ fixed (PR fix/parity-p1b-reschedule).
2. ~~**Web pro cross-day reschedule** (1.9)~~ ✅ fixed (PR fix/parity-p1b-reschedule).
3. « Client arrivé » on both detail pages (1.10) + app gap-slot artist (1.11) + app cancel warning (1.5) + app « Appeler » fix (1.6) — small batch.
4. Web add-to-calendar (1.2) + deposit-proof view (1.3) + notes row (1.4) — small batch.

## Module 2 — `online-booking` (consumer discovery · salon page · funnel · favorites · reviews)

### Discovery & search

| # | Finding | Severity | Detail |
|---|---|---|---|
| 2.1 | ~~« Trier » missing on web search~~ **FIXED 2026-07-11** (Pertinence/Mieux notés/Prix croissant select on /recherche, ?sort=, default relevance like the app) | ✅ fixed | App list: sort sheet — Pertinence / Mieux notés / Prix croissant (`ProviderSort`). Web `/recherche` always sorts by rating server-side; the user has no control |
| 2.2 | ~~« Disponible aujourd'hui » filter missing on web~~ **FIXED 2026-07-11** (toggle pill → ?dispo=1 riding the existing availableToday param) | ✅ fixed | App list: a one-tap availability filter pill. No web equivalent |
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
| 2.10 | ~~Booking notes missing on web~~ **FIXED 2026-07-11** (« Notes (optionnel) » textarea on the confirm step; BFF forwards notes) | ✅ fixed | App confirmation has « Note (optionnel) » sent with the booking (salons see it in the journal). Web confirm step has no notes field and the BFF doesn't forward one |
| 2.11 | ~~Mobile-web summary not sticky~~ **FIXED 2026-07-11** (the app's pinned Total + « Confirmer » bottom bar under lg; desktop aside unchanged) | ✅ fixed | The app hub pins Total + « Confirmer » at the bottom permanently; on mobile web the summary/CTA is the last block below the sections — scroll required to confirm. `lg:` is sticky; small screens should get the app's fixed bottom bar |
| 2.12 | Hub flow parity | ✅ | Order-free hub, three orderings, capability dim/drop, earliest-slot auto-pick, variants, silent re-validation, deposit sheet — verified at K2 (built 2026-07-10) |

### Favorites & reviews

| # | Finding | Severity | Detail |
|---|---|---|---|
| 2.13 | ~~Review photos: web can neither SUBMIT nor DISPLAY them~~ **FIXED 2026-07-11** (deeper than audited: NO surface could submit against the real backend — added `purpose=review` to /uploads/sign (consumer, public, review/{userId}); fixed the app's provider-session/gallery-purpose upload; web ReviewForm ≤3 photos + public ReviewList thumbnails/lightbox) | ✅ fixed | App submit sheet attaches photos (picker → upload) and review tiles show them full-screen. Web `ReviewForm` = rating + text only; public `ReviewList` renders no `photoUrls` (the pro « Avis » page does — inconsistent) |
| 2.14 | ~~Review reporting UI missing on BOTH surfaces~~ **FIXED 2026-07-11** (« Signaler » on the app's tiles (opt-in callback; salon detail wires the dialog) AND the web public list (inline reason; 401 → login prompt)) | ✅ fixed | `POST /reviews/{id}/report` (consumer-only) + the admin moderation queue are LIVE — but neither the app's review tiles nor the web's have a « Signaler » action. FR-REV-005's consumer half was never surfaced |
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
| 3.1 | ~~`artistIds` settable NOWHERE~~ **FIXED 2026-07-10** (« Qui peut réaliser ce service ? » checkbox list on BOTH service forms; empty = toute l'équipe) | ✅ fixed | The backend accepts `artistIds` on service create/update, the booking hub dims incompatible stylists with it, and the K1 capacity engine computes the capable pool from it — but NO surface has UI to set it: the app's service form has no artist picker, the web catalogue form has none, and the artist forms assign no services. **The entire capability rule can only ever fire on seed data.** Same class of forget as the map pin (L1) |

### Services

| # | Finding | Severity | Detail |
|---|---|---|---|
| 3.2 | ~~Duration variants (court/moyen/long) missing on web~~ **FIXED 2026-07-11** (« Durée selon la longueur de cheveux » toggle + Court/Moyen/Long minute fields; app payload semantics) | ✅ fixed | App service form: full variant editor (three duration fields behind a toggle). Web catalogue form: name/description/price/priceMax/duration/active only — a web-managed salon can never offer hair-length variants, though the WEB booking hub renders them (K2) |
| 3.3 | Core fields | ✅ | name · description · price + priceMax · duration · active toggle on both; create/edit/delete on both |

### Team

| # | Finding | Severity | Detail |
|---|---|---|---|
| 3.4 | ~~Per-staff hours missing on web~~ **FIXED 2026-07-10** (« Horaires personnalisés » toggle + weekly editor on the Équipe form; {} = inherits the salon) | ✅ fixed | App artist form: custom weekly-hours editor (feeds the K1 engine — `_hoursCover`). Web Équipe form = name + specialization only (the 7.3b deferral was never picked back up, and it now matters: the capacity engine reads those hours) |
| 3.5 | **Artist photo missing on web** | ❌ web (minor) | App: avatar upload on the artist form. Web: no imageUrl field |

### Media

| # | Finding | Severity | Detail |
|---|---|---|---|
| 3.6 | **Photo reorder missing in the APP** | ❌ app (minor) | Web Médias: move up/down (the first photo is the listing hero — order matters). App photos screen: upload/remove only |
| 3.7 | Before/After | ✅ | Pair upload + optional caption + delete on both |

### Availability

| # | Finding | Severity | Detail |
|---|---|---|---|
| 3.8 | ~~Breaks editor missing on web~~ **FIXED 2026-07-10** (« Pauses » section on Disponibilités — one recurring pause per day, same PUT) | ✅ fixed | App: a recurring-pause editor per day (ex. déjeuner) — breaks feed the slot engine AND the journal grid's hatched zones. Web Disponibilités edits hours/tampon/dates bloquées; the `breaks` field is in its type but has NO UI |
| 3.9 | Hours/buffer/blocked dates | ✅ | Multi-slot weekly hours, tampon, dates bloquées round-trip on both |

### Profile
Fresh parity as of L1/L2 (2026-07-10): both surfaces edit every allowlisted field + category + the map pin. ✅

### Module 3 — proposed fixes (by priority)
1. **`artistIds` UI on BOTH surfaces** (3.1) — an artist multi-select on the service form (app + web); without it the capability rule and the per-artist capacity math are decorative for real salons.
2. **Web: per-staff hours** (3.4) + **breaks editor** (3.8) — the two remaining inputs the K1 slot engine reads that web salons can't set.
3. **Web: duration variants** (3.2) + artist photo (3.5).
4. App: photo reorder (3.6).

## Module 4 — `clients` (salon CRM)

Fresh on both surfaces (C1b/C1c, 2026-07-08) and it shows — near-parity.

| # | Finding | Severity | Detail |
|---|---|---|---|
| 4.1 | **Web cannot CREATE custom tags** | ❌ web (minor) | App tag sheet: presets + a free-text field to add a custom tag. Web tag editor offers presets + only the custom tags ALREADY on the card (no input to mint one) |
| 4.2 | Everything else | ✅ | Search (débounced) + tag filter + masked phones + MyWeli/absences badges + educational empty on both lists · card: tel/WhatsApp, tags, team-only notes (add/delete, 500), stats (Visites/Dépensé/Absences alert/Dernière), « Prochain rendez-vous », salon-scoped history, « Nouveau rendez-vous » prefilled · add-client with initial note + 409 dedupe → existing card on both |
| 4.3 | Pagination style | ℹ️ | App: infinite scroll · web: « Charger plus » — idiomatic per surface |

## Module 5 — `notifications`

| # | Finding | Severity | Detail |
|---|---|---|---|
| 5.1 | ~~Web has NO notification center~~ **FIXED 2026-07-11** (/mon-compte/notifications: list + mark-read + « Tout lire »; header bell with unread dot; account entry) | ✅ fixed | App: `notifications_screen` (list + mark-read + unread state) fed by `GET /me/notifications`. Web: nothing — no bell, no page; a web-only user never sees booking-lifecycle notifications in-product (only WhatsApp/SMS if configured) |
| 5.2 | ~~Web has NO notification preferences~~ **FIXED 2026-07-11** (« Préférences » block on the same page — the app's three toggles, optimistic + revert) | ✅ fixed | App: `notification_preferences_screen` (channel toggles → `/me/notification-preferences`). Web: nothing |
| 5.3 | Web push | ℹ️/⏳ | FCM device registration is app-side; web push (PWA) is a separate deferral already noted in the module map — not counted as parity debt yet |

### Modules 4–5 — proposed fixes
1. ~~**Web notification center + préférences** (5.1/5.2)~~ ✅ fixed (PR fix/parity-p1c-web-surfaces).
2. Web custom-tag input on the client card (4.1) — one small field.

## Module 8 — `payments` (no-custody deposits)

| # | Finding | Severity | Detail |
|---|---|---|---|
| 8.1 | ~~« Deposits require verification » is copy-only~~ **FIXED 2026-07-10** (T52: PUT 403 `verification_required` + locked editors with guidance on both surfaces) | ✅ fixed | Both KYC screens promise « Les acomptes sont activés une fois votre compte vérifié » — but nothing enforces it: `PUT /providers/{id}/deposit-policy` doesn't check `verificationStatus`, booking derives the deposit from `depositRequired` alone, and neither editor locks the toggle. **An UNVERIFIED salon can demand screenshot-based deposits — the exact fraud vector KYC exists to block.** Fix server-side (policy PUT 403 `verification_required` when not verified, or derive 0) + lock state with explanatory copy in both editors |
| 8.2 | Policy editors | ✅ | Toggle · percentage · fenêtre d'annulation · opérateur Mobile Money · numéro — same field set on both (app enum chips vs web select — idiomatic) |
| 8.3 | Consumer deposit flows | ✅ (cross-ref) | Booking estimate + in-flow proof + later attach on both (K2/B4); residual gaps already filed: web can't VIEW the attached proof (1.3), app cancel dialog lacks the deposit warning (1.5) |

## Modules 9 + 10 — `finance` + `analytics` (pro)

| # | Finding | Severity | Detail |
|---|---|---|---|
| 9.1 | ~~Earnings page missing on web~~ **FIXED 2026-07-11** (/pro/revenus: Aujourd'hui/Semaine/Mois/Tout tabs + total + ledger; sidebar entry) | ✅ fixed | App « Revenus »: total earnings + the per-transaction history (date · amount). Web: two stat cards (aujourd'hui / ce mois) on the pro home — no page, no history, no per-visit breakdown |
| 9.2 | ~~Revenue stats granularity~~ **FIXED 2026-07-11** (« Revenus cette semaine » card on the pro home — `weekRevenue` was already in the DTO) | ✅ fixed | The dashboard endpoint returns today/week/month; web shows today + month only (week dropped) |
| 10.1 | Dashboard counters | ✅ | À confirmer / Confirmés / Total du jour on both (web Aujourd'hui ↔ app dashboard tiles) |

### Module 8–10 — proposed fixes
1. **Enforce the deposit⇄KYC gate** (8.1) — backend rule + threat-model row + locked UI on both editors. Security-grade.
2. ~~**Web « Revenus »** page (9.1)~~ ✅ fixed (PR fix/parity-p1c-web-surfaces).

## Module 11 — `access` (auth + account management) — flow-by-flow

### Consumer sign-in (Google · Apple-seam · email OTP), step by step

| Step | App | Web | Verdict |
|---|---|---|---|
| Entry | `/login` (+ `returnTo` continuity) | `/connexion` (+ `returnTo`) AND inline in the booking confirm (no redirect) | ✅ — web's in-funnel inline login is smoother; app redirects with returnTo (equivalent outcome) |
| Options | Google · Apple (flag-hidden) · email | idem (env-gated) | ✅ |
| Code step | « Se connecter » + « Changer d'e-mail » + inline error | idem | ✅ |
| **Resend** | **none** (the dormant phone-OTP screen HAS the full cooldown+resend pattern) | **none** | ⚠️ **both** — an expired code forces backtracking; port the existing cooldown pattern to the email step on both |
| Mandatory contact phone | blocking step post-sign-in | idem (+ re-required, prefilled, at booking) | ✅ |

### Account management

| # | Finding | Severity | Detail |
|---|---|---|---|
| 11.1 | ~~Account DELETION missing on web~~ **FIXED 2026-07-10** (Confidentialité section, type-SUPPRIMER confirm — the app's flow; BFF DELETE ends the session) | ✅ fixed | App: « Supprimer mon compte » with double confirmation (AUTH-004; anonymizes salon CRMs — T48). Web mon-compte has nothing — a web-only user cannot delete their account (legal-grade gap) |
| 11.2 | ~~Data EXPORT missing on web~~ **FIXED 2026-07-10** (/mon-compte/donnees — same JSON shape as the app; download + copier) | ✅ fixed | App: dedicated export screen (AUTH-005). Web: nothing |
| 11.3 | ~~Name editing missing on web~~ **FIXED 2026-07-10** (inline edit on the profile card) | ✅ fixed | `PATCH /me` accepts `name`; the app edits it (« Modifier le profil »); web shows it read-only |
| 11.4 | Contact phone editing | ✅ | Both, with « Non vérifié » labelling |
| 11.5 | Pro account deletion/export | ⚠️ both (parked) | Exists on NEITHER surface for salon accounts — acceptable pre-launch, must exist before stores review |

### Pro auth

| # | Finding | Severity | Detail |
|---|---|---|---|
| 11.6 | Login + registration | ✅ | One-submit identity+business registration on both (name · type select · intl phone · address); not-found → « Créer mon compte » CTA on both; returnTo on both |

### Module 11 — proposed fixes
1. **Web account deletion + data export** (11.1/11.2) — endpoints live; legal-grade.
2. Email-code **resend with cooldown** on both (the pattern already exists in the dormant OTP screen).
3. Web name editing (11.3).

## Module 15 — `trust` (KYC · moderation · disputes · badges)

| # | Finding | Severity | Detail |
|---|---|---|---|
| 15.1 | ~~« Vérifié » badge unwired~~ **FIXED 2026-07-10** (admin approve/reject denormalizes `verified` onto the listing; contract + app model; badge on app card/detail + web card/hero) | ✅ fixed | Verification lives on the ACCOUNT (`provider_users.verification_status`); the public listing carries no `verified` field — backend payload, app `Provider` model and web type all lack it, and no consumer surface renders a badge. **KYC's entire consumer-visible payoff is unwired end-to-end** (and it compounds 8.1: today KYC gates nothing and shows nothing). PRD's Provider model explicitly lists `verified` |
| 15.2 | No in-product dispute/problem entry | ⚠️ both | Disputes are admin-created/resolved (manual intake — WhatsApp support). Acceptable pre-launch; the app at least has « Aide & Support » in the profile — **web mon-compte has no help/support entry at all** |
| 15.3 | KYC submit/status | ✅ | Full parity since web-pro-kyc (2026-07-10) |
| 15.4 | Review moderation | cross-ref | Consumer « Signaler » missing on both = finding 2.14; the admin queue is live |

---

# SYNTHESIS — consolidated priorities across all findings

## P0 — security · legal · trust correctness
*(ALL P0 FIXED 2026-07-10: 8.1 + 15.1 — PR #211 · 11.1/11.2 + 11.3 — PR #212)*
| Finding | Surfaces |
|---|---|
| **8.1** Deposit⇄KYC gate is copy-only: unverified salons can demand deposits | backend + both editors |
| **15.1** « Vérifié » badge unwired end-to-end (field → model → display) | backend + app + web |
| **11.1/11.2** Account deletion + data export missing on web (legal-grade) | web |

## P1 — core capabilities users will hit
| Finding | Surfaces |
|---|---|
| ~~**3.1** `artistIds` settable nowhere~~ ✅ fixed (PR fix/parity-p1a-capability) | app + web |
| ~~**1.1** Consumer reschedule · **1.9** pro cross-day reschedule missing on web~~ ✅ fixed (PR fix/parity-p1b-reschedule) | web |
| ~~**3.4** per-staff hours + **3.8** breaks on web~~ ✅ fixed (PR fix/parity-p1a-capability) | web |
| ~~**5.1/5.2** Notification center + préférences missing on web~~ ✅ fixed (PR fix/parity-p1c-web-surfaces) | web |
| ~~**9.1** « Revenus » page (earnings + history) missing on web~~ ✅ fixed (PR fix/parity-p1c-web-surfaces) | web |

## P2 — flow/UX & conversion
~~2.11 mobile-web sticky « Confirmer » bar · 2.10 booking notes on web · 2.1/2.2 « Trier » + « Disponible aujourd'hui » on web search~~ ✅ (P2a) · email-code RESEND with cooldown (both — pattern exists in the dormant OTP screen) · 1.10 « Client arrivé » on both detail pages · 1.5 app cancel dialog deposit warning · 1.6 app fake « Appeler » button · ~~3.2 web duration variants~~ ✅ (P2a) · ~~2.13 review photos · 2.14 « Signaler » (both)~~ ✅ (P2b)

## P3 — polish
1.2 web add-to-calendar · 1.3 web view-own-proof · 1.4 web notes display · 1.8 show the spécialiste (both) · 1.11 app gap-slot artist · 2.6 web gallery lightbox · 2.7 « Vos rendez-vous ici » on web salon page · 2.8 review invite on the web salon page · 2.15 hearts on web result cards · 3.5 web artist photo · 3.6 app photo reorder · 4.1 web custom tags · ~~9.2 web week-revenue card~~ ✅ (P1c) · 11.3 web name edit · 15.2 web support entry

## Proposed execution (themed batches, one PR each)
1. **P0 trust batch** — deposit⇄KYC enforcement (backend + threat row + both editors' lock states) + the verified badge end-to-end + web deletion/export.
2. **P1a capability batch** — `artistIds` UI both + web staff-hours + web breaks (the capacity-engine trio).
3. ~~**P1b reschedule batch**~~ ✅ done 2026-07-11 — web consumer « Reporter » + web pro « Reprogrammer » (cross-day).
4. ~~**P1c web-surfaces batch**~~ ✅ done 2026-07-11 — notification center/prefs + « Revenus » (+ 9.2 week card).
5. **P2 batches**: ~~P2a search+funnel (2.1/2.2/2.10/2.11/3.2)~~ ✅ done 2026-07-11 · ~~P2b reviews/trust (2.13/2.14)~~ ✅ done 2026-07-11 · P2c appointments+auth (1.10/1.5/1.6/resend) — then **P3 polish batches**, app and web sides grouped.
