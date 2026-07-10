# Design specs

Every non-trivial part of Myweli gets a **design spec here before any code is written**. A spec is the single, authoritative description of how that part should work — so the build is deliberate, professional, and nothing is missed.

This is a standing rule, not a suggestion (see the `myweli-dev-guardrails` / `myweli-backend-guardrails` skills and the `design-spec-per-part` memory).

> **Before any UI/design work, read [DESIGN-STANDARDS.md](DESIGN-STANDARDS.md)** — the canonical design + UX standards (identity, tokens, components, the four-states/French rules, the consistency sweep). Plus the part's spec below. (Rule: `check-design-standards-first`.)
>
> **Working on the web (`web/`)?** Read **[WEB-DESIGN-STANDARDS.md](WEB-DESIGN-STANDARDS.md)** (web design system) + **[../WEB.md](../WEB.md)** (web architecture/conventions) first, and invoke the **`myweli-web-guardrails`** skill.

## The workflow — for every part

1. **Invoke the relevant guardrails skill** (`myweli-dev-guardrails`, and `myweli-backend-guardrails` for anything under `backend/`).
2. **Re-confirm fit** with the agreed ROADMAP, rules, security model, patterns, structure, and architecture — don't drift.
3. **Write the spec** as `docs/design/<part>.md`, copying [`TEMPLATE.md`](TEMPLATE.md). Fill in every applicable section in detail.
4. **Align** on the spec with the user *before* building.
5. **Cross-link** the spec from the files it governs — the [ROADMAP](../ROADMAP.md) entry, the code files (a `// Design: docs/design/<part>.md` reference near the top), and the [API contract](../api/openapi.yaml) — so the design stays discoverable as the source of truth.
6. **Build** to the spec. If reality forces a change, **update the spec in the same PR** (keep it honest, like the PRD/ROADMAP).

When is a spec required? Any new feature, slice, endpoint, screen, or integration. Trivial fixes (typos, a one-line bug, a dependency bump) don't need one.

## Spec status legend

`Draft` (being written / under review) → `Approved` (aligned, ready to build) → `Built` (shipped; spec reflects what exists) → `Superseded` (replaced — link the successor).

## Index

| Part | Spec | Status |
|------|------|--------|
| Auth overhaul — Google + Apple + Email OTP (phone → contact) | [auth-social-email.md](auth-social-email.md) | **Building** — P1 backend built (verifiers · email OTP · migration 0022 · AUTH_METHODS gate); web → mobile → pro next |
| Pro auth — Google + Email OTP for salons (P4) | [pro-auth-social.md](pro-auth-social.md) | **Built** — login-only social + identity-inline registration (backend + pro app + pro web) + AUTH_METHODS gate on pro phone |
| Clients C1 — salon client base (list · card · notes · tags · badge) | [clients-c1.md](clients-c1.md) | **Built** — backend + web + app (#184/#185/C1c); first slice of [modules/clients.md](../modules/clients.md) |
| Journal J1 — the web journal grid (+ « Client arrivé ») | [journal-j1-grid.md](journal-j1-grid.md) | **Built** — backend (#188) + web « Journée » grid; C2 mini-card inside |
| Journal J1b — the pro-app day timeline (« Ma journée ») | [journal-j1b-app.md](journal-j1b-app.md) | **Built** — « Ma journée » default view; swipe + long-press actions, gap slots, week strip |
| App consumer auth — Google + Email OTP, Apple seam (P3) | [app-auth-social.md](app-auth-social.md) | **Built** — LoginScreen (Google + email + MANDATORY phone step; Apple flag-hidden) · service seam · profile phone edit · iOS plist |
| Web consumer auth — Google + Apple + Email OTP (P2) | [web-auth-social.md](web-auth-social.md) | **Built** — LoginOptions (email-first; Google/Apple env-gated) + booking-confirm sign-in + MANDATORY contact phone + account phone edit |
| Brand & launch-asset integration (logo · loader · icons · splash) | [branding-integration.md](branding-integration.md) | **Approved** — phased (P1 web · P2 admin · P3 app assets+loader · P4 icon+splash · P5 flavors+pro) |
| Admin / ops console — backend (KYC · moderation · mgmt · disputes · analytics) | [admin-console.md](admin-console.md) | Slices 1–3 built |
| Admin / ops console — UI (Flutter Web) | [admin-console-ui.md](admin-console-ui.md) | Complete — dashboard · KYC · moderation · mgmt + support views · disputes · audit log (Journal) |
| Messaging & notifications (WhatsApp + SMS, Twilio) | [messaging-notifications.md](messaging-notifications.md) | Built (PR A foundation + OTP · PR B events + reminder scheduler); real BSP creds = ops |
| Push notifications (FCM) — backend | [push-notifications-fcm.md](push-notifications-fcm.md) | Building (token registry + FCM v1 adapter + event wiring); app plugin + creds = ops |
| Push notifications (FCM) — app | [push-notifications-app.md](push-notifications-app.md) | Built (token-registration seam + permission UX on mocks; consumer + pro #2b); real firebase_messaging impl = accounts phase |
| Web — images + OG / brand | [web-images-og-brand.md](web-images-og-brand.md) | Built (next/image + CDN allowlist + OG image + favicon + logo.svg) |
| Provider before/after showcase (FR-DISC-006) | [provider-before-after.md](provider-before-after.md) | Complete — backend + pro editor + consumer drag-reveal slider |
| Discovery sort & filter (FR-DISC-007) | [discovery-sort-filter.md](discovery-sort-filter.md) | Complete — backend sort + available-today · app Trier sheet + toggle (à domicile = V2) |
| Web ↔ app parity audit (flow/user-story) | [web-parity-audit.md](web-parity-audit.md) | Recorded — most surfaces match; gaps G1 home discovery · G2 provider map/before-after/artistes · G3 pro Tableau de bord stats · G4 account rebook/avis/favoris; remediation M7.2→M7.3→M8 |
| Web surface — Next.js, SEO/AEO/GEO (FR-WEB-PP/MP) | [public-web.md](public-web.md) | Planned — OQ-8 resolved (Next.js for all web; shared API); milestone breakdown, awaiting sign-off |
| Auto-sync provider-entered bookings (FR-APPT-008) | [appointment-auto-sync.md](appointment-auto-sync.md) | Built — read-time match on the account's verified phone + "Réservé par votre salon" badge |
| Pro subscription — plan & trial (FR-PRO-SUB-001) | [pro-subscription.md](pro-subscription.md) | View built — derived trial (`GET /me/subscription`) + "Mon abonnement" screen; in-app billing deferred |
| Notification preferences (FR-NOTIF-004) | [notification-preferences.md](notification-preferences.md) | Complete — backend (prefs + send-path enforcement) · app preferences screen |
| Add appointment to calendar (FR-APPT-006) | [appointment-calendar.md](appointment-calendar.md) | Built — native add (add_2_calendar) from appointment detail; iOS plist set, Android `<queries>` TODO when scaffolded |
| In-app notification center (FR-NOTIF-002) | [notification-center.md](notification-center.md) | Complete — backend feed + write-on-events · app ApiNotificationService |
| Consumer deposit / Mobile Money flow | [consumer-deposit.md](consumer-deposit.md) | Built (B1 + B2) |
| Booking duration-overlap exclusion (btree_gist) | [booking-overlap-exclusion.md](booking-overlap-exclusion.md) | Built |
| Pro KYC (provider verification) | [pro-kyc.md](pro-kyc.md) | Built (provider side) |
| Pro staff (artists) management | [pro-artists.md](pro-artists.md) | Built |
| Consumer reviews | [consumer-reviews.md](consumer-reviews.md) | Built |
| Consumer favorites | [consumer-favorites.md](consumer-favorites.md) | Built |
| Pro deposit policy management | [pro-deposit-policy.md](pro-deposit-policy.md) | Built |
| Image upload pipeline (Cloudflare R2) | [pro-image-upload-pipeline.md](pro-image-upload-pipeline.md) | Built |
| Pro gallery photos (URL list) | [pro-gallery.md](pro-gallery.md) | Built |
| Pro-side reschedule | [pro-reschedule.md](pro-reschedule.md) | Built |
| Provider earnings detail | [provider-earnings.md](provider-earnings.md) | Built |
| Pro manual (walk-in/phone) booking | [pro-manual-booking.md](pro-manual-booking.md) | Built |
| Provider dashboard stats | [provider-dashboard-stats.md](provider-dashboard-stats.md) | Built |
| Pro catalogue app wiring (ApiProService → backend) | [pro-catalogue-app-wiring.md](pro-catalogue-app-wiring.md) | Built |
| Provider services & availability (backend) | [provider-services-availability-backend.md](provider-services-availability-backend.md) | Built |
| _Spec template_ | [TEMPLATE.md](TEMPLATE.md) | — |

> Add a row per spec as it's created. Keep newest at the top.
