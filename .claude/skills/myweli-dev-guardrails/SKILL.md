---
name: myweli-dev-guardrails
description: >-
  Development guardrails and a pre-flight / post-flight checklist for the Myweli
  beauty & wellness booking app (Flutter consumer + pro apps, with a future
  backend and web surfaces). Use this skill WHENEVER doing any development work
  in this repo — writing or editing Dart code, adding or changing a
  feature / screen / provider / service / route / model, touching the mock
  services, fixing a bug, refactoring, wiring an integration, or preparing a
  commit or PR — even if the user does not explicitly ask to "check the rules."
  It keeps every change aligned with the project's architecture patterns
  (interface→mock services, Provider state, go_router, dependency injection),
  its V1 scope discipline, and its first-order security and performance budgets
  and testing gates defined in docs/PRD.md and docs/ROADMAP.md, so nothing is
  missed and each change is correct, secure, fast, and tested.
---

# Myweli Dev Guardrails

This skill exists so that development on Myweli stays **step by step, secure, fast, and consistent** — and so we never quietly drift away from the plan we agreed on. The hard part of a project like this isn't writing one screen; it's writing the hundredth screen the same disciplined way as the first, while the codebase grows toward real payments, real user data, and low-end devices on bad networks. This is the always-on checklist that makes that happen.

The two source-of-truth documents hold the detail; this skill makes sure they're actually consulted and applied.

## Source of truth — read these, don't reinvent them
- **[docs/PRD.md](../../../docs/PRD.md)** — what we're building and the phasing (V1 / V2 / V3). Go here to confirm a feature exists, its requirement ID, and its phase.
- **[docs/ROADMAP.md](../../../docs/ROADMAP.md)** — current state, the build plan, the security model (Part 5), performance budgets (Part 6), the testing strategy (Part 4), and the Definition of Done / quality gates (Part 7).

If a rule below is ambiguous or a situation isn't covered, check these two docs first. If they don't answer it, ask the user — and propose updating the docs so the answer is captured for next time.

## The development loop: before → during → after

### UX first — design the experience before building (user-facing work)
For anything a user touches — a screen, a flow, a state, a control — **plan the UX in detail and align with the user before writing code.** Efficient and intuitive UX is a first-order goal here, not a polish pass at the end. Produce a short written UX plan and get agreement *first*; it must cover:
- **Goal & entry points** — what the user is trying to accomplish, and every place they arrive from.
- **The flow** — the happy path step by step, plus the branches; minimize taps-to-done.
- **All states** — loading, empty, error, success, offline, permission-denied, auth-gated.
- **Edge cases** — bad/slow network, slow or failed Mobile Money, missing data, long French strings, low-end Android.
- **Interaction detail** — what each control does, validation, feedback, back/navigation behavior, `returnTo` continuity.
- **Copy** — the French microcopy for labels, errors, and empty states.
- **Fit** — reuses existing components/patterns and respects the CI context (commune, FCFA, à domicile, WhatsApp).

Only once the UX plan is agreed do you move to the steps below. Do not jump straight to code on user-facing work.

### Before writing code
1. **Locate it in the plan.** Which PRD requirement and phase is this? If it's **V2 or V3** (e.g. the 8 `screens/provider/features/` modules, loyalty/membership UI, ERP), **stop and confirm with the user** — default is **V1 only**. Building screens we may cut is the top way "frontend-first" wastes time (ROADMAP §2.2).
2. **Find the existing pattern to copy.** Match the surrounding code's idiom rather than inventing a new one. Reference implementations:
   - Service interface → `lib/services/interfaces/provider_service_interface.dart`
   - Mock implementation → `lib/services/mock/mock_provider_service.dart`
   - State (ChangeNotifier) → `lib/providers/provider_provider.dart`
   - Routing → `lib/core/router/app_router.dart` (and `pro_router.dart`)
   - DI / service locator → `lib/core/di/dependency_injection.dart`
   - A well-built screen → `lib/screens/booking/booking_hub_screen.dart`
   - Shared widgets / states → `lib/widgets/common/` (`EmptyState`, `LoadingIndicator`, `AppButton`, `AppTextField`)
3. **Any new data access goes behind an interface.** No screen or provider calls a network/storage detail directly — it goes through a `*ServiceInterface` with a mock implementation. This is what makes the eventual backend swap mechanical (ROADMAP §2.1).

### While writing code — the patterns that must hold
- **Layering:** `models → services (interface + mock) → providers → screens/widgets`, with cross-cutting helpers in `core/`. Don't short-circuit a layer.
- **Services:** every backend-ish capability is an interface in `services/interfaces/` with a mock in `services/mock/`. Mocks **simulate latency, pagination, and error/empty responses** — otherwise we build UI that only works in a perfect world.
- **State:** `ChangeNotifier` + `provider`; expose `isLoading` / `error` / data; use scoped `Consumer`/`Selector` to avoid rebuild storms.
- **Routing:** `go_router` only; typed path/query params; preserve the `returnTo` auth-continuity pattern.
- **Models:** immutable, value-equality (`equatable`); `fromJson`/`toJson` shaped to the **real API DTOs** we're converging on (ROADMAP §2.2 guardrail #2) so mocks and the future backend agree.
- **Every screen handles four states:** loading, empty, error, success. A screen that only renders the happy path is not done.
- **Localization & locale fit:** French UI copy; use the FCFA / phone / duration formatters in `core/utils/`; use the Ivorian service taxonomy (PRD Appendix A), not generic categories.
- **Security inline (see checklist below):** no secrets in code, tokens only in `flutter_secure_storage`, validate every input, never log sensitive data, and assume the server re-validates everything — the client is never the authority on prices, IDs, or permissions.
- **Performance inline (see budgets below):** `const` constructors, paginate lists, lazy-load and cache images (`TimedCachedImage`), defer heavy init.

### After writing code — run this checklist every time
Treat any unchecked box as "not done."

- [ ] `flutter analyze` → **0 issues** (not just 0 errors — 0).
- [ ] Tests added/updated and `flutter test` green: unit for models/providers/utils, a widget test for the screen, a golden if it's UI, an integration test if it's on a critical flow (login→book→deposit→confirm, pro accept→complete).
- [ ] All four UI states present (loading / empty / error / success).
- [ ] **Security:** no secrets or keys added; tokens in secure storage; inputs validated; no PII/secret in logs; server-authority assumed.
- [ ] **Performance:** meets budgets on the reference low-end Android; `const` used where the analyzer asks; lists paginated; images compressed/lazy.
- [ ] **Scope:** V1 only; no V2/V3 screen shipped or made reachable; deferred feature screens stay flag-hidden.
- [ ] **Patterns:** interface+mock, Provider, go_router, DI all followed; no layer skipped.
- [ ] **Mock realism:** new mock simulates latency + error + (if a list) pagination.
- [ ] **API shape:** mock returns the agreed DTO shape, not an ad-hoc one.

### Before a commit / PR
- **Feature-branch + PR workflow:** don't commit or push to `main` directly — branch off main (`feat/…`, `fix/…`, `chore/…`), push the branch, and open a PR (`gh pr create`) for the user to review/merge; after CI is green, report the PR and leave merging to the user (see memory `git-workflow-feature-branches-prs`).
- `analyze` = 0, tests green, format clean, coverage not decreased, dependency scan clean (ROADMAP §7 gates).
- Conventional commit message, authored as the user — **no Claude author or `Co-Authored-By` trailer** (see memory `git-no-claude-attribution`).
- Never commit secrets, `.env`, build artifacts, or `build/` / `.dart_tool/`.
- This repo must be under git with CI — if it somehow isn't yet, that's the first thing to fix (ROADMAP §1.7).
- **After a feature ships, refresh `docs/ROADMAP.md` status** — mark what's done, note deferrals — so the roadmap stays a trustworthy source of truth (see memory `roadmap-status-refresh`).

## Security checklist — first-order (detail in ROADMAP Part 5; ref OWASP MASVS)
Security is gated from the start, not deferred to "the backend phase," because a client app can leak secrets, mishandle sessions, or trust the wrong input regardless of backend maturity.
- No secrets in the client or version control; keys via `--dart-define`/secure config; CI secret scanning.
- Tokens/PII only in `flutter_secure_storage`; nothing sensitive in `shared_preferences` or logs.
- Validate all inputs (phone, OTP, amounts); the client never sets authoritative prices/IDs — the server does.
- Session model: short-lived access + refresh, rotation, logout clears storage, OTP rate-limit/lockout.
- Release builds: obfuscation (`--obfuscate --split-debug-info`), no debug logging of sensitive data.
- For payments/KYC work: signed/verified Mobile Money callbacks, idempotency, encrypted + access-audited KYC docs, and respect the deposit-custody decision (PRD OQ-1).

## Performance budgets — first-order (detail in ROADMAP Part 6)
Budgeted against the **reference low-end Android (2–3 GB RAM, Android 9)** from day one, because that's the device most Ivorian users actually hold.
- Cold start **p95 < 3.5s**; key screens interactive **< 1.5s** on 3G.
- **60fps** on lists/galleries; no frame > 16ms on critical flows.
- Initial **APK < 30 MB**; watch size per release.
- Compress/resize images server-side; lazy-load + cache; never autoplay media on cellular; placeholders to avoid layout jank.
- Paginate everywhere; dedupe in-flight requests (the booking hub's `slotsRequestId` pattern); cache reads for offline tolerance.

## Scope & phasing discipline
The plan is **finish the V1 frontend on mocks first**, with three guardrails (ROADMAP §2.2): stay in V1 scope, keep mock data shaped like the real DTOs, and spike the two risky integrations (Mobile Money deposit, WhatsApp) early rather than last. The 8 `provider/features/` screens and the loyalty/membership/gifting UI are **V2/V3** — keep them flag-hidden and don't polish them now. This is enforced in code via `FeatureFlags.futureProviderFeatures` (`lib/core/config/feature_flags.dart`), which is `false` for V1; each of those screens early-returns a `ComingSoonScaffold` placeholder while off. Don't route them or flip the flag without confirming the phase with the user.

## Keep the guardrails honest
When a real decision changes a rule (a new pattern, a revised budget, a resolved open question), **update docs/PRD.md or docs/ROADMAP.md** in the same change. This skill is only as good as those documents — stale rules are worse than no rules.
