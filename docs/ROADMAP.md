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
| **Consumer auth** (phone/OTP, splash, session) | ~95% | Real-OTP UX done (5-min expiry, attempts→lockout, resend cap, inline states). Remaining: session persistence across restarts, SMS auto-read. |
| **Consumer discovery** (home, list, detail, map, search) | ~80% | Strong. Missing: commune filter, price *ranges*, WhatsApp link, verified badge, before/after gallery. |
| **Booking flow** (hub, services, artist, date/time, confirm) | ~85% | Best part of the app (`booking_hub_screen.dart`). Missing: deposit step, buffers, duration-by-length, rebook. |
| **Consumer appointments** (list, detail, cancel, reschedule, history) | ~95% | Done: policy-bound cancel + reschedule; rich visit history with auto-synced status. Remaining: deeper history (photos/receipts) post-backend. |
| **Reviews** (submit post-completion) | ~70% | Missing: photos, verified-booking badge, per-artist attribution. |
| **Favorites** (map + toggle) | ~80% | Solid. |
| **Profile** (view/edit) | ~90% | Account deletion (typed confirm) + data export (JSON copy) done. Missing: avatar upload. |
| **Notifications (consumer)** | ~10% | **Stub** (`EmptyState`). No feed, no center. |
| **Pro auth + register** | ~80% | Missing: KYC upload UI, guided onboarding (empty `onboarding/`). |
| **Pro dashboard** | ~70% | Stats wired to mock. |
| **Pro appointments / calendar** | ~70% | Accept/reject/complete/reschedule present. Missing: manual booking entry, no-show marking. |
| **Pro services / artists / availability** | ~75% | Missing: price ranges, duration variants, buffers, per-staff hours, commission. |
| **Pro earnings / reviews / profile** | ~65% | Missing: payouts, commission tracking. |
| **Pro "feature" screens (the 8)** | UI-only mocks | Hardcoded values, empty handlers, **not routed**. Defer (V2 loyalty/memberships; V3 the rest). |

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
2. **Auth** — ✅ real-OTP UX (5-min expiry, attempts/lockout, resend cap, inline error states); remaining: session persistence, SMS auto-read affordance.
3. **Discovery** — add commune filter, price ranges, WhatsApp link, verified badge, before/after gallery; perf-test long lists (pagination, image placeholders).
4. **Booking + deposit (UI)** — add the **deposit step UI** (operator picker, one-tap, amount = deposit, balance shown), buffers, duration-by-length, rebook; wire to a mock payment service.
5. **Appointments** — ✅ policy-bound cancel/reschedule UI; ✅ rich visit history with auto-synced status.
6. **Reviews** — photos, verified-booking badge.
7. **Notifications** — real in-app feed + center (replace stub), preferences UI.
8. **Profile** — ✅ account deletion (typed confirm) + data export (JSON); remaining: avatar upload.
9. **Pro V1** — KYC upload UI, guided onboarding (fill the empty `onboarding/`), manual booking entry, no-show marking, price ranges/duration variants/buffers/commission fields, payouts UI.
10. **Hide/remove** the unrouted V2/V3 feature screens behind a flag so they don't ship.

**Exit:** all V1 screens meet the per-screen DoD; flows pass integration tests against mocks; analyze = 0; coverage gate met; perf budget met on reference device for every screen.

**Status (2026-06-21) — Phase 1 in progress (consumer side advancing):**
- ✅ **Discovery — commune filter** (FR-DISC-002): pill on home + list, picker (search / "Près de moi" / all), persisted, mock providers tagged by commune.
- ✅ **Discovery — trust polish** (FR-DISC-006 / FR-BOOK-005): WhatsApp contact row on provider detail (`wa.me`), and **price ranges** (`Service.priceMax`) shown on detail / selection / confirmation, with "À partir de" totals (deposit math unchanged, on the from-price).
- ✅ **Booking + deposit** (FR-PAY-001): confirmation shows Total / Acompte / Solde; `DepositPaymentSheet` (Wave/OM/MTN/Moov, remembered operator, processing/success/failure); deposit-to-confirm on a mock payment service. Provider-side **deposit settings** (FR-PRO-PAY-001) shipped too (toggle + % slider).
- ✅ **Notifications** (FR-NOTIF-002): in-app feed replaces the stub (flat list, unread cues, "Tout lire", tap → mark read + deep link).
- ✅ **Reviews** (FR-REV-002/003): verified-booking badge, stylist attribution, photo **display** (attach deferred to the Phase 4 image pipeline).
- ✅ **Booking — rebook** (FR-BOOK-009): tapping a *past* appointment in the salon-page "appointments at this salon" carousel re-opens the booking hub pre-filled with the same services + stylist (sanitized against current provider data) and lands on Date & heure; past tiles show a "Réserver à nouveau" hint, upcoming appointments still open the detail.
- ✅ **Appointments — policy-bound cancel + reschedule** (FR-APPT-003/004/005): per-salon `cancellationWindowHours` (default 24h, snapshotted onto each appointment at booking); cancel shows the deposit consequence (forfeited within the window vs refunded outside, mock refund); reschedule reuses the `/booking/date-time` picker (deposit carries over, no penalty). Pros set the window in the existing "Acompte" settings screen. *(Real refund lands with the payment backend.)*
- ✅ **Auth — real-OTP UX** (FR-AUTH-002): the mock now enforces a 5-attempt lockout, 5-minute code expiry, and a 3-resend cap, returning typed error codes (`otp_invalid`/`otp_expired`/`otp_locked`/`otp_resend_limit`); the OTP screen renders inline error / locked / expired states with red boxes + attempts-remaining, plus backspace-to-previous, paste-to-fill, auto-submit, and a debug-only demo-code hint. *(Session persistence + SMS auto-read deferred to follow-ups.)*
- ✅ **Profile — account deletion + data export** (FR-PROF-008): authenticated users can **export their data** ("Mes données" → profile + rendez-vous + favoris, copied as JSON) and **delete their account** (type "SUPPRIMER" to confirm → clears session + favorites → back to login). Both behind `AuthServiceInterface` (`deleteAccount`) with a pure, unit-tested export builder. *(Real file download/share + server-side erasure land with the backend.)*
- ✅ **Appointments — rich visit history + auto-sync** (FR-APPT-005): the "Passés" tab is now a visit history — past, non-cancelled appointments auto-sync to "Terminé" (pure `effectiveAppointmentStatus`, a placeholder until backend completion events), grouped by month with a spend summary (visit count + total) and one-tap "Réserver à nouveau".
- ⏳ **Still V1-open:** booking buffers / duration-by-length (#4 partial); profile avatar upload (#8 partial); Pro V1 — KYC onboarding, manual booking entry, no-show marking, payouts (#9); flag-hide the unrouted V2/V3 feature screens (#10); auth session persistence + SMS auto-read.
- ⏳ **Deferred to later phases:** review photo upload, à-domicile end-to-end, and the risk spikes below (real Mobile Money + WhatsApp) — still pending.

### Phase 1b — Risk spikes (run during Phase 1, not after)
- [ ] **Mobile Money deposit spike:** one real sandbox deposit end-to-end via the chosen aggregator (PRD OQ-4) — proves feasibility, callback security, and the deposit-custody model (OQ-1).
- [ ] **WhatsApp spike:** one real template message via the chosen BSP (OQ-5) — proves approval flow + deliverability.
- [ ] Decision memos on OQ-1 (deposit custody) and OQ-3 (store IAP vs web billing) — both have legal/architecture lead time.

### Phase 2 — API contract & backend design (overlaps end of Phase 1)
- [ ] Define API (REST/GraphQL) + **DTO schemas** matching the data model (PRD §13).
- [ ] Make mock services return those exact shapes; generate typed models (e.g., `freezed`/`json_serializable`).
- [ ] Choose stack (Postgres + app server + object storage + Redis), auth model (phone/OTP, JWT/refresh), and the **slot engine** design (server-authoritative).
- [ ] Threat model the API (Part 5) before writing it.

### Phase 3 — Backend build + integration
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
