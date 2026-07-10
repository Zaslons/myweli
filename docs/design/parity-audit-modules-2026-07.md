# Deep web ↔ app parity audit — module by module (2026-07)

| | |
|---|---|
| **Goal** | Not just feature presence: entry points · user flow · capabilities · UI states & copy, compared by READING the code on both surfaces (user directive 2026-07-10; supersedes the M8-era [web-parity-audit.md](web-parity-audit.md)) |
| **Method** | Per built module ([MODULES.md](../MODULES.md)): consumer app ↔ consumer web, pro app ↔ pro web. Severity: **❌ missing capability** · **⚠️ flow/UX divergence** · **ℹ️ deliberate adaptation** (fine per `web-design-latitude`). Findings are BIDIRECTIONAL — app gaps count too |
| **Status** | In progress — audited: **1 journal**. Next: 2 online-booking · 3 catalogue · 4 clients · 5 notifications · 8 payments · 9/10 finance+analytics · 11 access · 15 trust |

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
