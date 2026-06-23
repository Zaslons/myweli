# Myweli — Current State & Build Plan

**Companion to [PRD.md](PRD.md).** This document establishes where the codebase actually is today, the strategy for building it out (frontend-first, with guardrails), the step-by-step sequence, and how we test, secure, and keep it fast at every step.

| | |
|---|---|
| **Last updated** | 2026-06-20 |
| **Build strategy** | Finish the **V1 frontend** on mock services → design & build backend → integrate → harden |
| **Non-negotiables** | Security and performance are first-order — continuous gates, not a final phase |
| **Reference device** | Low-end Android (2–3 GB RAM, Android 9) — the perf/UX bar |

---

## Part 1 — Current state (ground truth)

Established by reading the code and running `flutter analyze` on 2026-06-20.

### 1.1 Toolchain & repository
| Item | State | Action |
|---|---|---|
| Flutter SDK | ✅ Installed (`~/development/flutter`) | Pin version in `.fvmrc`/CI |
| App compiles | ✅ `flutter analyze` → **0 errors** | — |
| Lint health | ⚠️ **230 issues** (deprecations + correctness warnings) | Clean to zero (Phase 0) |
| Version control | ❌ **Not a git repo** | **`git init` today** — highest priority |
| CI/CD | ❌ None (`.github` absent) | Add in Phase 0 |
| Tests | ❌ **1 smoke test** only (`test/widget_test.dart`) | Build test harness (Phase 0) |
| Lint config | ⚠️ Default `flutter_lints`, no strictness | Tighten (Phase 0) |
| Secrets/env | ⚠️ No env strategy yet (fine while mock-only) | Define before any key touches the app |

### 1.2 Notable code-health signals from `flutter analyze`
- ~Dozens of `deprecated_member_use` (`withOpacity` → `.withValues`) — SDK drift; mechanical fix.
- **Correctness warnings** (not just style): `unnecessary_null_comparison` and `unnecessary_non_null_assertion` in `lib/widgets/booking/appointment_card.dart` — these usually mean a model's nullability changed and a widget wasn't updated. **Treat as latent bugs, not noise.**
- `unused_import` / `unused_local_variable` (e.g., `mock_pro_artist_service.dart:52`) — dead code to prune.

### 1.3 What's DONE (frontend, on mock data)
Estimates of V1-frontend completeness by area (UI built & wired to mock services):

| Area | Done | Notes |
|---|---|---|
| **Consumer auth** (phone/OTP, splash, session) | ~99% | Real-OTP UX + session persistence + SMS auto-read (OS autofill hint) done. Remaining: real access/refresh tokens + Android SMS Retriever (backend). |
| **Consumer discovery** (home, list, detail, map, search) | ~80% | Strong. Missing: commune filter, price *ranges*, WhatsApp link, verified badge, before/after gallery. |
| **Booking flow** (hub, services, artist, date/time, confirm) | ~90% | Best part of the app (`booking_hub_screen.dart`). Duration-by-length + buffers now respected in slots. Missing: deposit step, rebook polish. |
| **Consumer appointments** (list, detail, cancel, reschedule, history) | ~95% | Done: policy-bound cancel + reschedule; rich visit history with auto-synced status. Remaining: deeper history (photos/receipts) post-backend. |
| **Reviews** (submit post-completion) | ~70% | Missing: photos, verified-booking badge, per-artist attribution. |
| **Favorites** (map + toggle) | ~80% | Solid. |
| **Profile** (view/edit) | ~95% | Account deletion (typed confirm) + data export (JSON copy) + avatar upload (mock pipeline) done. |
| **Notifications (consumer)** | ~10% | **Stub** (`EmptyState`). No feed, no center. |
| **Pro auth + register + KYC + onboarding** | ~95% | KYC + verification status done; guided onboarding checklist done (photos step now actionable). Salon photos + staff avatar upload on a mock pipeline. Missing: real bytes/CDN (backend). |
| **Pro dashboard** | ~70% | Stats wired to mock. |
| **Pro appointments / calendar** | ~95% | Accept/reject/complete/reschedule + no-show marking + manual (walk-in/phone) booking entry. |
| **Pro services / artists / availability** | ~95% | Price ranges + duration variants on services; buffer between appointments; per-staff working hours; break times. Missing: commission (V2). |
| **Pro earnings / reviews / profile** | ~70% | Basic earnings + reviews + profile. (Payouts retired — no-custody model; commission tracking is V2.) |
| **Pro "feature" screens (the 8)** | Gated off | Not routed **and** gated behind `FeatureFlags.futureProviderFeatures` (false) → each renders a "Bientôt disponible" placeholder. Deferred (V2 loyalty/memberships; V3 the rest). |

### 1.4 What's MOCKED (works, but simulated)
All data flows through `lib/services/mock/*` behind `lib/services/interfaces/*`. Simulated: OTP (`123456`), provider/appointment/favorites data, slot generation (30-min, ~90% availability), review eligibility, booking lifecycle. **This is the asset that makes frontend-first viable** (see Part 2).

### 1.5 What's MISSING entirely (no code yet)
- **Backend / API** (everything is mock).
- **Payments / Mobile Money deposits** — the core CI value prop. Not started.
- **Notifications**: push (FCM), SMS, WhatsApp — not started.
- **Image upload pipeline** (provider/artist photos are static assets).
- **KYC/verification flow** (data field exists, no UI/logic).
- **Web** (all 4 surfaces): per-provider pages, marketplace, provider dashboard, admin console.
- **Retention features**: cross-salon loyalty wallet, memberships/abonnements, gift certificates.
- **Security & perf infrastructure**: no CI scanning, no obfuscation config, no perf budgets/profiling.

### 1.6 Honest grade
**A well-architected, ~75%-complete V1 *consumer* frontend prototype, on mocks, with no backend, no payments, no tests, and no version control.** The architecture (interface→mock, Provider state, go_router, DI) is genuinely good and was clearly built to allow a clean backend swap. The risk isn't the UI — it's that everything that makes Myweli *defensible in CI* (deposits, WhatsApp, KYC, performance under real data) is exactly what hasn't been started.

### 1.7 Do this week (before any feature work)
1. **`git init`** + first commit + `.gitignore` review + push to a private remote.
2. Stand up **CI** (analyze + test on every push).
3. **Clear the 230 analyze issues to zero** and fix the `appointment_card.dart` correctness warnings.
4. Add the **test harness + first real tests** (Part 4).

---

## Part 2 — Strategy: frontend-first, endorsed *with guardrails*

You proposed finishing the frontend before the backend. **I agree — for this codebase specifically — but with three guardrails, because an unconstrained "finish the whole frontend" has two failure modes that would hurt a security/performance-first product.**

### 2.1 Why frontend-first fits here
- The **interface→mock architecture already exists**. Swapping `MockProviderService` for `ApiProviderService` is localized and low-risk. The codebase was *designed* for this.
- **UX is the product's riskiest assumption** and its differentiator. A polished, clickable app (on mocks) lets you validate flows with real Abidjan salons/customers and drive supply-side onboarding demos — before spending on backend.
- For a small team, finishing one coherent layer beats context-switching between FE and BE.

### 2.2 The three guardrails (these make or break the approach)
1. **Constrain to V1 scope.** "Finish the frontend" = finish the **V1** frontend (PRD §7.1). Do **not** polish V2/V3 screens (the 8 ERP features, loyalty UI, etc.) now. Building screens you may cut is the #1 way frontend-first wastes months.
2. **Lock the API contract early.** While finishing the FE, define the real **API/DTO schemas** and make the **mock services return those exact shapes**. This turns the eventual backend swap from a rewrite into a config change, and prevents the classic "mock data shape ≠ real data shape → rework" trap.
3. **Spike the two highest-risk integrations early — do NOT leave them for last.** Mobile Money **deposits** and **WhatsApp/SMS** cannot be validated on mocks, and they are the core CI value prop *and* the biggest unknowns (feasibility, security, operator coverage). Build a **thin vertical slice** of each (one real deposit end-to-end in a sandbox, one real WhatsApp template send) **during** the frontend phase. This retires the scariest risks while you still have flexibility.

### 2.3 What frontend-first must NOT mean
- It must not mean **deferring security and performance** to "the backend phase." Both are architected and gated **now** (Parts 5 & 6). A client app leaks secrets, mishandles sessions, or janks on a Tecno regardless of backend maturity.
- It must not mean **mock data that hides reality** (unbounded lists, instant responses, perfect images). Mocks must simulate **latency, pagination, errors, and large/missing images** so the UI is built for the real world.

### 2.4 The shape of the plan
```
Phase 0  Foundation & guardrails        (git, CI, lint, tests, security/perf baselines)
Phase 1  Finish V1 frontend on mocks    (screen-by-screen, tested as we go)
   └─ in parallel near the end:
Phase 2  API contract + backend design  (lock DTOs; mocks mirror them)
Phase 1b Risk spikes (deposit, WhatsApp)(thin real vertical slices)
Phase 3  Backend build + integration    (swap mocks via interfaces)
Phase 4  Productionize integrations      (payments, notifications, uploads, KYC)
Phase 5  Security hardening + perf pass   (pentest, SAST/DAST, profiling)
Phase 6  Closed beta (Cocody) → launch   (3 communes)
```

---

## Part 3 — Phases, step by step

Each phase lists its work, its **exit criteria** (Definition of Done), and the tests that gate it.

### Phase 0 — Foundation & guardrails
**Goal:** make the repo safe to build in, with quality gates wired before feature work.
- [ ] `git init`, `.gitignore` audit (ensure `build/`, `.dart_tool/`, secrets excluded), private remote, branch protection.
- [ ] CI pipeline: `flutter analyze` (must be 0), `flutter test`, format check, on every PR.
- [ ] Tighten lints: adopt a stricter ruleset (e.g., `flutter_lints` + selected `lints`/`very_good_analysis` rules); `analyze` clean to **zero**.
- [ ] Fix the correctness warnings (`appointment_card.dart`) and prune dead code/imports.
- [ ] Add test tooling: `mocktail`, `golden_toolkit`/`alchemist`, `integration_test`, coverage reporting.
- [ ] **Security baseline:** secrets strategy (`--dart-define`/env, never in VCS), dependency scanning in CI (`flutter pub outdated`, OSV/Snyk), no-secrets pre-commit hook, build obfuscation flags planned.
- [ ] **Performance baseline:** define budgets (Part 6), set up profiling on the reference device, record a baseline cold-start/jank trace.
- [ ] Error handling + logging strategy (typed failures off `ApiResponse`, no silent catches, crash reporting wired: Crashlytics/Sentry).
- [ ] Mock services upgraded to **simulate latency, pagination, and error states**.

**Exit:** CI green on a real PR; analyze = 0; ≥1 unit + ≥1 widget + ≥1 golden test running in CI; crash reporting receiving events; budgets documented.

**Status (2026-06-20) — Phase 0 substantially complete:**
- ✅ Git + private GitHub remote (`Zaslons/myweli`); CI (format + strict analyze `--fatal-infos --fatal-warnings` + tests with coverage) green.
- ✅ Analyzer cleared to 0 under a **stricter ruleset** (added `unawaited_futures`, `avoid_dynamic_calls`, `cancel_subscriptions`, `prefer_single_quotes`, etc.); real fixes (async-gap, fire-and-forget, dynamic-call, dead code), not suppression.
- ✅ One-time `dart format` applied; CI enforces formatting.
- ✅ Test tooling: `mocktail` + first unit/widget/provider tests; coverage uploaded as a CI artifact.
- ✅ Error/observability **seam**: `AppLogger` + `runZonedGuarded` + `FlutterError.onError` in both entrypoints (ready for Sentry/Crashlytics).
- ✅ Dependabot (pub + github-actions).
- ⏳ **Deferred (need a decision or external account):** crash-reporting SDK wiring (needs Sentry DSN / Firebase project — seam is ready); **golden + integration tests** (cross-platform golden rendering needs a pinned-platform CI job; integration needs an emulator job); **branch protection** (would block our current direct-push-to-`main` flow — enable when we move to PR-based work); dependency **CVE gate** beyond Dependabot (OSV-Scanner) and `strict-casts`/`strict-raw-types` language modes (larger cleanup).

### Phase 1 — Finish the V1 frontend (on mocks)
**Goal:** every V1 screen complete, accessible, fast, and tested — using mock services.
Work the PRD V1 surface, prioritized by the booking → deposit → show-up loop. For **each screen/flow**, the Definition of Done is in Part 7. Suggested order:

1. **Design-system audit** — confirm theme tokens, spacing, components (`AppButton`, `AppTextField`, `EmptyState`, `LoadingIndicator`); add loading/error/empty variants everywhere; golden-test the component library.
2. **Auth** — ✅ real-OTP UX (5-min expiry, attempts/lockout, resend cap, inline error states); ✅ session persistence (secure storage); ✅ SMS auto-read affordance (OS autofill hint).
3. **Discovery** — add commune filter, price ranges, WhatsApp link, verified badge, before/after gallery; perf-test long lists (pagination, image placeholders).
4. **Booking + deposit (UI)** — ✅ deposit step UI, ✅ duration-by-length, ✅ buffers, ✅ rebook; deposit wired to a mock payment service.
5. **Appointments** — ✅ policy-bound cancel/reschedule UI; ✅ rich visit history with auto-synced status.
6. **Reviews** — photos, verified-booking badge.
7. **Notifications** — real in-app feed + center (replace stub), preferences UI.
8. **Profile / photos** — ✅ account deletion (typed confirm) + data export (JSON); ✅ image-upload pipeline (mock) wired into salon gallery + staff avatar + consumer profile avatar. Remaining: real bytes/CDN (backend).
9. **Pro V1** — ✅ KYC submission + verification status; ✅ guided onboarding checklist; ✅ no-show marking; ✅ manual booking entry; ✅ price ranges + duration variants on services; ✅ buffer between appointments; ✅ per-staff working hours; ✅ break times. (Payouts retired under the no-custody model; commission tracking is V2.)
10. ✅ **Flag-hidden** the unrouted V2/V3 feature screens behind `FeatureFlags.futureProviderFeatures` — each renders a placeholder while off, so they can't ship.

**Exit:** all V1 screens meet the per-screen DoD; flows pass integration tests against mocks; analyze = 0; coverage gate met; perf budget met on reference device for every screen.

**Status (2026-06-21) — Phase 1 in progress (consumer side advancing):**
- ✅ **Discovery — commune filter** (FR-DISC-002): pill on home + list, picker (search / "Près de moi" / all), persisted, mock providers tagged by commune.
- ✅ **Discovery — trust polish** (FR-DISC-006 / FR-BOOK-005): WhatsApp contact row on provider detail (`wa.me`), and **price ranges** (`Service.priceMax`) shown on detail / selection / confirmation, with "À partir de" totals (deposit math unchanged, on the from-price).
- ✅ **Booking + deposit** (FR-PAY-001): confirmation shows Total / Acompte / Solde; the deposit sheet is the **no-custody facilitated transfer** (Wave deep link / copy-number + optional screenshot → pending booking the salon confirms). Provider-side **deposit settings** (toggle + % + receiving handle).
- ✅ **Notifications** (FR-NOTIF-002): in-app feed replaces the stub (flat list, unread cues, "Tout lire", tap → mark read + deep link).
- ✅ **Reviews** (FR-REV-001/002/003): verified-booking badge, stylist attribution, photo display **and attach** (before/after, via the image pipeline, cap 3). Submission routed through `ReviewServiceInterface` (was local-only) and entered from the completed-appointment detail as well as the provider page.
- ✅ **Booking — rebook** (FR-BOOK-009): tapping a *past* appointment in the salon-page "appointments at this salon" carousel re-opens the booking hub pre-filled with the same services + stylist (sanitized against current provider data) and lands on Date & heure; past tiles show a "Réserver à nouveau" hint, upcoming appointments still open the detail.
- ✅ **Appointments — policy-bound cancel + reschedule** (FR-APPT-003/004/005): per-salon `cancellationWindowHours` (default 24h, snapshotted onto each appointment at booking); cancel shows the deposit consequence (forfeited within the window vs refunded outside, mock refund); reschedule reuses the `/booking/date-time` picker (deposit carries over, no penalty). Pros set the window in the existing "Acompte" settings screen. *(Real refund lands with the payment backend.)*
- ✅ **Auth — real-OTP UX** (FR-AUTH-002): the mock now enforces a 5-attempt lockout, 5-minute code expiry, and a 3-resend cap, returning typed error codes (`otp_invalid`/`otp_expired`/`otp_locked`/`otp_resend_limit`); the OTP screen renders inline error / locked / expired states with red boxes + attempts-remaining, plus backspace-to-previous, paste-to-fill, auto-submit, and a debug-only demo-code hint. *(Session persistence + SMS auto-read deferred to follow-ups.)*
- ✅ **Profile — account deletion + data export** (FR-PROF-008): authenticated users can **export their data** ("Mes données" → profile + rendez-vous + favoris, copied as JSON) and **delete their account** (type "SUPPRIMER" to confirm → clears session + favorites → back to login). Both behind `AuthServiceInterface` (`deleteAccount`) with a pure, unit-tested export builder. *(Real file download/share + server-side erasure land with the backend.)*
- ✅ **Appointments — rich visit history + auto-sync** (FR-APPT-005): the "Passés" tab is now a visit history — past, non-cancelled appointments auto-sync to "Terminé" (pure `effectiveAppointmentStatus`, a placeholder until backend completion events), grouped by month with a spend summary (visit count + total) and one-tap "Réserver à nouveau".
- ✅ **Auth — session persistence** (FR-AUTH): the session (mock token + user) is persisted in **`flutter_secure_storage`** and restored on cold start, so users stay logged in across restarts; logout and account deletion clear it. New `Session` model + `SessionStore` interface (secure + in-memory impls), behind `AuthServiceInterface`. *(Real access/refresh + rotation land with the backend; chosen lifetime: until logout, with a ready `expiresAt` field.)*
- ✅ **Auth — SMS auto-read** (FR-AUTH): the OTP boxes form an `AutofillGroup` and the first box requests `AutofillHints.oneTimeCode`, so iOS surfaces the SMS code in the keyboard QuickType bar (one tap) and Android autofill can fill it; the OS code lands in the first box and the existing paste-distribution fills the rest and auto-submits. No dependency, no permission. *(Zero-tap Android SMS Retriever needs the backend SMS to embed the app hash — deferred.)*
- ✅ **Pro — KYC & verification** (FR-PRO-KYC-001): a pro submits KYC documents (pièce d'identité + photo du visage required; RCCM required for salons, optional for freelancers à domicile; justificatif d'adresse optional) and sees their status (en attente / vérifié / refusé + motif); the screen surfaces that deposits are gated on verification. Behind `ProKycServiceInterface`; `kycDocs[]` + `rejectionReason` on `ProviderUser`. *(Mock document selection — real upload lands with the image pipeline; admin approval is backend.)*
- ✅ **Pro — guided onboarding checklist** (FR-PRO-ONB-001): the `/pro/onboarding` hub shows live progress over the steps (profil · services ≥3 · équipe · disponibilités · acompte · vérification · photos), each linking to its screen, with a "Mettre en ligne" CTA gated on the self-serve essentials. Pure `buildOnboardingChecklist`/`canGoLive` helper; `ProOnboardingProvider` aggregates the data; entries on the pro dashboard + profile. *(Photos step is informational until the image pipeline; "go live" publish is backend.)*
- ✅ **Pro — no-show marking** (FR-PRO): new `AppointmentStatus.noShow` (handled across all status chips; excluded from the consumer's completed visit history); the pro marks a confirmed, past-due appointment "absent" from the detail screen, with a confirmation noting the deposit is kept per the salon's cancellation policy. `markNoShow` behind `ProServiceInterface`.
- ✅ **Pro — manual booking entry** (FR-PRO-CAL): a `/pro/appointment/new` form (entered via "+" on the appointments list) where the pro records a walk-in/phone booking — multi-select services, date + time (now+future), client phone (required, with a "sans numéro" walk-in opt-out), optional name + note, and a (deferred) "Envoyer la confirmation + lien par SMS" toggle for client acquisition. Created `confirmed`, no online deposit. `createManualBooking` behind `ProServiceInterface`; `clientName`/`clientPhone` added to `Appointment`. *(Real SMS invite lands with the notifications backend; framed as a transactional confirmation.)*
- ✅ **Scope hygiene — flag-hide V2/V3 screens** (#10): the 8 unrouted `provider/features/` screens are gated behind `FeatureFlags.futureProviderFeatures` (false) and each early-returns a "Bientôt disponible" placeholder, so the cut features can't ship even if accidentally wired.
- 🗑️ **Pro — payouts of collected deposits** (FR-PRO-PAYOUT-001) — **retired (removed).** Built in #21 assuming Myweli holds deposits; superseded by the no-custody decision (PRD OQ-1) — nothing to pay out under direct client→salon payment. Screen/route/provider/service + tests deleted; recoverable from #21 / git history if escrow via an aggregator is added post-incorporation.
- ✅ **Pro — service price ranges + duration variants** (FR-PRO-SVC-001): the service form now takes an optional **prix maximum** (unlocking the range the consumer UI already renders via `formatPriceRange`) and an optional **"varie selon la longueur"** toggle with **court / moyen / long** durations (`DurationVariants` on `Service`, shaped per §548). The provider profile shows the variant durations. *(Booking slots driven by the client's chosen length — `FR-BOOK-006` — is the deferred follow-up; it touches the slot engine.)*
- ✅ **Booking — duration by hair length** (FR-BOOK-006): when a selected service declares duration variants, the booking hub shows a **"Longueur des cheveux"** selector (court/moyen/long, auto-defaulting to the middle bucket) that drives the **estimated duration → slot availability** (via the pure `booking_duration` helper); the choice is carried through `/booking/confirm` and shown in the summary. Single length per booking (the client's hair). *(Step-by-step screens `/booking/artist`→`/booking/date-time` and persisting the chosen length onto the booking DTO are follow-ups.)*
- ✅ **Booking — buffer between appointments** (FR-BOOK-004 / FR-PRO-AVAIL-001): the pro sets a provider-wide buffer (Aucun / 10 / 15 / 30 min, default Aucun) on the availability screen; consumer slot computation pads each existing booking by that buffer on both sides so new bookings keep the gap. `Availability.bufferMinutes`; mock `updateAvailability` now persists so the choice reaches slots.
- ✅ **Pro — per-staff working hours** (FR-PRO-AVAIL-001 / FR-PRO-STAFF-001): a staff member can follow salon hours (default) or have custom weekly hours (one range per day) via a shared `WeeklyHoursEditor` in the artist form; consumer slot computation only offers times that member works (within salon hours), in both the artist-specific and "any eligible artist" paths. `Artist.workingHours`; mock `create/updateArtist` persist into `MockData.providers` so slots reflect it.
- ✅ **Image-upload pipeline (frontend on mock)** (#8): `ImageUploadServiceInterface` + mock (simulated progress + hosted-URL contract; real impl = picker → compress/resize → CDN scan). Wired into a pro **"Photos du salon"** screen (`Provider.imageUrls`, add/remove, cover, four states) and **staff avatar** in the artist form, via a dependency-free mock image picker. `ProService.get/updateGalleryPhotos` persist into `MockData.providers` so the consumer hero gallery reflects edits.
- ✅ **Consumer — profile avatar** (#8): the user can set a profile photo (edit-profile screen, mock picker + upload) shown on their profile; `User.avatarUrl`, saved via `AuthService.updateUser`.
- ✅ **Pro — break times** (FR-PRO-AVAIL-001): a recurring daily break (e.g. lunch, one range/day) set on the availability screen via the shared `WeeklyHoursEditor`; consumer slot computation offers nothing overlapping a break (`Availability.breaks` + `overlapsBreak` helper). Demo: provider1 lunch 13:00–14:00 Tue–Sat.
- ✅ **Booking — step-screen length parity** (FR-BOOK-006): the hub's hair-length selector is now a shared `LengthVariantSelector` widget, also used by `date_time_selection_screen` (the reschedule/rebook + step-flow path), so that screen computes slot length from the chosen variant and carries it through to confirmation — matching the hub.
- 🧪 **Risk spike — WhatsApp/SMS messaging seam** (FR-NOTIF-001): scaffolded the outbound-messaging seam — `MessagingServiceInterface` + mock (WhatsApp-first with SMS fallback, delivery status, transactional-vs-promotional opt-in, in-memory outbox), a typed template catalog for the FR-NOTIF-001 events, and the booking-confirmed message wired (best-effort) at confirmation. The real **WhatsApp Business BSP** (template approval) + **reminder scheduler** (24h/2h) are the backend behind this seam.
- ⏳ **Still V1-open:** the **Mobile Money deposit** spike (on hold pending product decision); real WhatsApp BSP + reminder scheduling behind the messaging seam. The V1 frontend is otherwise complete on mocks.
- ⏳ **Deferred to later phases:** à-domicile end-to-end, and the risk spikes below (real Mobile Money + WhatsApp) — still pending. (Real image bytes/CDN/scan behind the mock pipeline are backend.)

### Phase 1b — Risk spikes (run during Phase 1, not after)
- ✅ **Mobile Money deposit (V1, no custody)** (FR-PAY-001/002):
  - **Salon side:** `Provider`/`Appointment`/`DepositPolicy` deposit-handle + screenshot fields; `depositRequired` default → **off**; deposit-settings screen takes the **receiving Mobile Money handle** (operator + number); `waveDeepLink` helper. Demo: provider2 requires 50% to its Wave number.
  - **Consumer side:** the deposit sheet is now a **facilitated transfer** — *Payer avec Wave* deep link (when the salon uses Wave) / number + **Copier** for the others, an **optional screenshot**, then **"J'ai payé"** → the booking is created **`pending`** (never auto-confirmed). The pro sees the deposit amount + screenshot on the appointment detail and **confirms** after receiving it. The old mock-pay path (`payDepositAndBook` + the entire `PaymentService` interface/mock + DI registration) is removed. *(Aggregator sandbox + escrow deferred to post-incorporation.)*
- [ ] **WhatsApp spike:** one real template message via the chosen BSP (OQ-5) — proves approval flow + deliverability.
- [ ] Decision memos on OQ-1 (deposit custody) and OQ-3 (store IAP vs web billing) — both have legal/architecture lead time.

### Phase 2 — API contract & backend design (overlaps end of Phase 1)
- ✅ **Stack chosen: Dart + `dart_frog`** (REST), in `backend/` of this monorepo. One language app↔server (shared Dart DTOs, zero drift); public web stays Next.js/React on the same API via generated TS. *(PRD §8.2 decision, 2026-06-23.)*
- 🟡 **API contract** seeded as **OpenAPI 3.1** — [`docs/api/openapi.yaml`](api/openapi.yaml) — mirroring the app DTOs field-for-field (B0). First slice locked: health, `/providers` read, `/auth/otp/*`; more added per slice.
- ✅ **B0 foundation shipped:** `backend/` scaffold (dart_frog), `/health` route, strict analyze + tests, a dedicated **backend CI job** (`dart analyze --fatal-infos --fatal-warnings` + `dart test`).
- ✅ **Backend engineering guide + security model** — [`docs/BACKEND.md`](BACKEND.md): layering, conventions, the server-side security model (**JWT access + rotating refresh**, OTP rate-limit/lockout, secrets via env, deny-by-default authz, input validation), performance budgets, testing strategy, a living **STRIDE threat model**, and the backend PR DoD. Wired into the dev-guardrails skill. **CI security gates added:** secret scanning (gitleaks) + dependency-vulnerability scan (OSV). Built **before** the auth slice, by design.
- [ ] Auth model (phone/OTP, JWT/refresh) + the **slot engine** design (server-authoritative) — detailed as B2/booking slices land.
- [ ] Threat model the API (Part 5) before the first write endpoints.

### Phase 3 — Backend build + integration
- 🟡 **B3a — repository seam:** `ProvidersRepository` + `AuthRepository` are now **interfaces** with `InMemory*` impls, built in one composition root (`backend/lib/src/dependencies.dart`) and provided to routes via middleware. Makes the Postgres swap a one-place change. Pure refactor — no contract change.
- 🟡 **Double-booking prevention (backend):** `POST /appointments` and reschedule now **validate the requested time against the slot engine** server-side — a closed/past/break/already-booked/non-aligned time is rejected with `slot_unavailable` (409). Closes the ROADMAP Phase 3 "double-booking prevention" gap at the app level; a DB unique-constraint/transaction for true concurrency lands with the Postgres appointment impl. 72 backend tests (incl. a real double-book attempt → conflict). Threat model T11.
- 🟡 **Appointment lifecycle (pro, backend):** `POST /appointments/{id}/{accept,reject,complete,no-show}` — **provider-role token only**, and the account's `providerId` must match the appointment's salon (cross-salon or unlinked → **403**), with a state-guarded machine (pending→confirmed→completed; pending→cancelled; →noShow; bad transition → **409**). Provider accounts gain an optional `providerId` link (set at registration) + `ProviderAuthRepository.accountById`; `ProAppointmentService`. 69 backend tests (state machine, role 403, cross-salon 403, ownership). This closes the core booking state machine — a `pending` booking can now be confirmed by its salon.
- 🟡 **Appointment lifecycle (consumer, backend):** `POST /appointments/{id}/cancel` + `/reschedule` (auth + **ownership** → 403; state guard → 409 on terminal status). Cancel records status only (deposit is salon↔client, no custody); reschedule moves the date with deposit/balance carried over. `AppointmentLifecycleService` + `AppointmentRepository.update`. 64 backend tests. *(Pro-side transitions — accept/complete/no-show — are a follow-up: they need the provider-account ↔ Provider link + provider authz.)*
- 🟡 **Slot engine (backend):** `GET /availability?providerId=&date=` (public) — **server-authoritative** bookable start times computed from the provider's weekly schedule, blocked dates, breaks, a setup/cleanup buffer, the requested duration (from `serviceIds` or `durationMinutes`), and existing non-cancelled bookings (buffer-padded). UTC throughout (Abidjan is UTC+0). `SlotService` (reads `ProvidersRepository` + `AppointmentRepository`); seed providers gained a Mon–Sat 09:00–18:00 schedule. 59 backend tests (open day, closed day, duration-fit, booking exclusion, blocked date, break, route 400/404/405). *(Provider-level v1 — per-artist working hours + eligible-artist-by-service is a follow-up.)*
- 🟡 **Appointments (backend, book + read):** authenticated `POST /appointments` (created **`pending`**; the salon confirms, never auto-confirmed — PRD OQ-1), `GET /appointments` (caller's, status filter), `GET /appointments/{id}` (ownership → **403** for another user's booking). **Server-authoritative pricing**: total/deposit/balance computed from the provider's service prices + deposit policy — a client-sent price is ignored. `AppointmentRepository` + `BookingService` (reads `ProvidersRepository`); contract + `Appointment` schema. 48 backend tests. *(Slot engine / `getAvailableTimeSlots`, lifecycle (cancel/reschedule/pro accept-complete-no-show), Postgres impl, and app wiring are follow-ups.)*
- 🟡 **Provider auth (backend):** `POST /auth/provider/otp/request` · `/auth/provider/register` · `/auth/provider/otp/verify` — hashed OTP + attempt/resend budgets (same rigor as consumer), registration (duplicate → 409), and a **provider-role JWT** on verify; **registration is required before login** (verify → 404 if absent — tighter than the old auto-creating mock). `ProviderAuthRepository` interface + in-memory impl + routes + contract (`ProviderUser` schema). 41 backend tests green. *(App-side `ApiAuthService` swap off the mock + a Postgres provider impl are follow-ups; provider auth still uses in-memory regardless of `DATABASE_URL` for now.)*
- 🟡 **B3c — Postgres persistence:** `PostgresProvidersRepository` + `PostgresAuthRepository` (`package:postgres`, parameterized queries, transactions on multi-write paths) behind the same interfaces; selected in the composition root when `DATABASE_URL` is set (unset → in-memory). Embedded SQL migrations + provider seed (`lib/src/db/migrations.dart`), run at startup via a custom `main.dart` entrypoint. **A Postgres service container** in the backend CI job exercises the DB-backed repo tests (OTP lockout, refresh reuse→revoke, update/delete, provider query/byId); they skip locally without `DATABASE_URL`. *(JSONB-document storage for providers; normalized tables for users/otp/refresh. Real DB verified in CI, not locally.)*
- 🟡 **B3b — async repository interfaces:** the repository methods now return `Future`s (I/O-ready), with the in-memory impls + routes + tests updated. Required before a Postgres impl can satisfy them. 33 backend tests green, analyze 0, no contract change. *(**B3c** adds the Postgres impls + SQL migrations + a CI Postgres service, where the real DB is exercised in CI.)*
- 🟡 **B2 — auth slice shipped:** backend `POST /auth/otp/{request,verify}` + `/auth/refresh` + protected `PATCH/DELETE /me`. **JWT access (HS256, ~15 min) + rotating opaque refresh** (hashed at rest, reuse → family revoke); OTP **hashed + server-side rate-limit/lockout**; deny-by-default `/me` scoped to the token `sub`. `ApiAuthService` swaps `AuthServiceInterface` behind `AppConfig.useApiBackend` (provider-auth delegates to the mock until its own slice; mocks stay default). Backend security/negative tests (lockout, expiry, refresh reuse→401, ownership) + app `MockClient` tests. *(Client silent-refresh wiring + real SMS are later slices.)*
- 🟡 **B1 — provider read slice shipped:** backend `GET /providers` (search/filter/paginate, rating-sorted) + `GET /providers/{id}` over a seeded in-memory store mirroring the mock data; `ApiProviderService` implements `ProviderServiceInterface` and is wired in by DI **only when `AppConfig.useApiBackend=true`** (`--dart-define`), so mocks remain the default for tests/demos. Contract-faithful, with backend + app tests. Next: auth (B2) → Postgres (B3).
- [ ] Build endpoints by domain; swap mock implementations for real ones **one interface at a time** (auth → providers → booking → favorites → pro), behind a build flag so mock mode still runs for tests/demos.
- [ ] **Contract tests** ensure each real service matches the interface the UI already depends on.
- [ ] Server-authoritative availability + **double-booking prevention** under concurrency.

### Phase 4 — Productionize integrations
- [ ] **Payments:** deposits, balance, refunds, payouts, subscription billing; signed callbacks; reconciliation.
- [ ] **Notifications:** push (FCM) + SMS fallback + WhatsApp orchestration with delivery tracking.
- [ ] **Image upload pipeline:** compress/resize/CDN + moderation hooks.
- [ ] **KYC** submission + admin approval (web console).
- [ ] **Offline:** cached reads + queued mutations + sync/conflict handling.

### Phase 5 — Security hardening & performance pass
- [ ] External **penetration test**; SAST/DAST in CI; dependency CVE gate; MASVS checklist.
- [ ] Cert pinning, obfuscation, jailbreak/root awareness as appropriate; secrets audit.
- [ ] Load test the slot engine + payment callbacks; perf profiling on reference device under real data volumes; APK size budget enforced.

### Phase 6 — Closed beta → launch
- [ ] Cocody closed beta (15–25 verified providers), field-onboarded; validate deposit→show-up lift.
- [ ] Fix retention loop; staged store rollout; expand to Marcory + Plateau on density gates (PRD §19).

---

## Part 4 — Testing strategy (test everything on the way)

Testing is continuous and gates each phase. Flutter test pyramid:

| Layer | Tooling | What we test | Gate |
|---|---|---|---|
| **Unit** | `flutter_test`, `mocktail` | Models (serialization, equality), providers (state transitions, error handling), utils (formatters: FCFA, phone, duration; validators), the booking draft/slot logic | ≥80% on `models/`, `providers/`, `core/utils/` |
| **Widget** | `flutter_test` | Each screen renders loading/empty/error/success; key interactions; auth gating; `returnTo` continuity | Every V1 screen has ≥1 widget test |
| **Golden** | `golden_toolkit`/`alchemist` | Visual regression of the component library + key screens (incl. small/large text scale) | Components + critical screens covered; runs in CI |
| **Integration / E2E** | `integration_test`, optionally `patrol` | Full flows on mocks: login→book→deposit→confirm→cancel; pro accept→complete; rebook | Critical flows green in CI |
| **Contract** | custom harness | Real service impls satisfy the same interface + DTO shapes the mocks do (Phase 3) | Every interface has a contract test |
| **Manual QA** | Reference low-end Android + iOS | Real-device feel, jank, slow-network behavior, French copy, RTL-safety | Pre-release checklist per build |
| **Backend** | stack-dependent | Unit, API contract, **load** (slot engine, payment callbacks), **security** (authz, rate limits) | Gates Phase 3/4 |

**Principles:** write tests alongside each screen in Phase 1 (not after); CI blocks merge on analyze≠0 or red tests or coverage drop; mocks simulate latency/errors so tests cover the unhappy paths; every bug fix ships with a regression test.

---

## Part 5 — Security (first-order, continuous)

Security is gated from Phase 0, not deferred. Reference: **OWASP MASVS** (mobile) + **OWASP ASVS** (backend).

### During the frontend phase (now)
- **No secrets in the client or VCS.** Keys via `--dart-define`/secure config; CI secret scanning + pre-commit hook.
- **Secure storage** for tokens (already using `flutter_secure_storage`) — verify usage; no PII in `shared_preferences` or logs.
- **Input validation** on every field (phone, OTP, amounts); never trust client-entered prices/IDs — design so the server re-validates.
- **Session model designed now:** short-lived access + refresh, rotation, explicit logout clears storage, OTP rate-limit/lockout UX.
- **Build hardening planned:** obfuscation (`--obfuscate --split-debug-info`), no debug logging in release, no `print` of sensitive data.

### Backend & integration phase
- **Authentication/authorization:** every endpoint authz-checked; users can only access their own data; provider scoping; admin RBAC + audit log.
- **Payments:** signed/verified Mobile Money callbacks; idempotency keys; server-side amount authority; reconciliation; **deposit custody decision (OQ-1)** drives AML/KYC obligations.
- **PII & KYC docs:** encryption at rest + transit; least-privilege, access-audited KYC storage; data-subject delete/export (PRD §18, ARTCI).
- **Abuse:** rate limiting, OTP/SMS-pumping protection, referral/promo fraud checks, off-platform-leakage monitoring.

### Pre-launch (Phase 5)
- External **penetration test**; SAST + DAST in CI; dependency CVE gate; threat-model review; MASVS/ASVS checklist signed off.

---

## Part 6 — Performance (first-order, continuous)

Budgeted against the **reference low-end Android (2–3 GB RAM, Android 9)** from day one.

### Budgets (enforced in CI/manual QA)
- Cold start **p95 < 3.5s**; key screens interactive **< 1.5s** on 3G.
- Steady **60fps** scroll on lists/galleries; no frame >16ms in critical flows.
- Initial **APK < 30 MB**; monitor size per release.
- Memory stable on image-heavy screens (provider detail, galleries, stories).

### Practices
- **Continuous profiling:** DevTools timeline + memory on the reference device each milestone; record baselines, alert on regressions.
- **Images:** compress/resize server-side; cached, lazy-loaded (existing `TimedCachedImage`); never autoplay media on cellular; placeholders to avoid layout jank.
- **Lists:** pagination everywhere (already in interfaces); `const` constructors (analyze flagged misses); avoid rebuild storms (scoped `Consumer`/`Selector`).
- **Data thrift:** small payloads, cache reads offline, dedupe in-flight requests (the booking hub already tracks a `slotsRequestId` — good pattern to generalize).
- **Startup:** defer non-critical init; lazy-load heavy deps (maps, calendar).

---

## Part 7 — Definition of Done & quality gates

**Per screen/feature (Phase 1):**
- [ ] Loading, empty, error, and success states implemented.
- [ ] Wired to a mock service that simulates latency + errors.
- [ ] Widget test + golden; flow covered by an integration test if it's part of a critical path.
- [ ] French copy reviewed; text scaling + tap targets + contrast checked.
- [ ] Meets perf budget on the reference device; no analyze issues.
- [ ] No secrets, no sensitive logging; inputs validated.

**Per PR (CI gates):**
- [ ] `flutter analyze` = 0; format clean; tests green; coverage not decreased; dependency scan clean.

**Per phase:** the phase's exit criteria (Part 3) are met and signed off.

---

## Part 8 — Immediate next actions (ordered)

1. **`git init` + first commit + private remote** (today).
2. **CI** running analyze + test on every push.
3. **Clear analyze to zero**; fix `appointment_card.dart` correctness warnings; prune dead code.
4. **Test harness** + first unit/widget/golden tests on existing models, providers, and the booking hub.
5. **Upgrade mocks** to simulate latency/pagination/errors.
6. **Lock V1 scope**; flag-hide V2/V3 feature screens.
7. **Start Phase 1** screen-by-screen, **and** kick off the **deposit + WhatsApp spikes** (Phase 1b) in parallel.
8. **Draft the API contract** so mocks mirror real DTOs.

> The single biggest risk to "frontend-first" is treating payments + WhatsApp as a backend-phase afterthought. They're the CI value prop and the biggest unknowns — spike them **while** the frontend is being finished, not after.
