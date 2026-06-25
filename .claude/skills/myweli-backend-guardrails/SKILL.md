---
name: myweli-backend-guardrails
description: >-
  Backend guardrails and a pre-flight / post-flight checklist for the Myweli
  REST API (the `dart_frog` server in `backend/`). Use this skill WHENEVER doing
  any development work under `backend/` — adding or editing a route, service,
  repository, middleware, model/DTO, auth/token/OTP logic, or touching the API
  contract (`docs/api/openapi.yaml`) — even if the user does not explicitly ask
  to "check the rules." It enforces the backend architecture
  (routes → services → repositories → DTOs + middleware), the server-side
  security model (JWT access + rotating refresh, OTP rate-limit/lockout, secrets
  via env, deny-by-default authz + ownership, boundary input validation, server
  authority), performance budgets, the testing strategy (including the REQUIRED
  security/negative tests), the living STRIDE threat model, and the backend PR
  Definition of Done — all defined in docs/BACKEND.md. The app-side skill
  `myweli-dev-guardrails` still applies for cross-cutting rules (scope, git/PR
  workflow, no-Claude-attribution); this is its server-side companion.
---

# Myweli Backend Guardrails

The always-on checklist for `backend/`. It makes sure the deep rules in
**[docs/BACKEND.md](../../../docs/BACKEND.md)** (architecture, security model,
performance, testing, threat model, DoD) are actually consulted and applied on
every backend change — the server-side mirror of `myweli-dev-guardrails`.

> **Source of truth:** [docs/BACKEND.md](../../../docs/BACKEND.md) (rules) +
> [docs/api/openapi.yaml](../../../docs/api/openapi.yaml) (the contract). If a
> rule here is ambiguous, read those; if they don't answer it, ask the user and
> propose updating them. Keep them honest — a rule change lands in the docs in
> the same PR.

## Before writing code
0. **Write the design spec first.** Before any non-trivial slice, **invoke this
   skill, re-confirm it fits the ROADMAP / rules / security model / layering /
   architecture, then write a detailed design spec as its own Markdown file
   _before_ code** — `docs/design/<part>.md`, per
   [`docs/design/TEMPLATE.md`](../../../docs/design/TEMPLATE.md), indexed in
   [`docs/design/README.md`](../../../docs/design/README.md). Cover goal & scope,
   the endpoint(s) + DTO contract, data model/migrations, services/repos,
   security/authz (+ threat-model deltas), errors, performance, tests, rollout,
   open questions. Align first, then build; **cross-link** it from the ROADMAP
   entry and the routes/services/contract it governs. (Memory:
   `design-spec-per-part`.)
1. **Locate it.** Which PRD requirement / cutover slice (PRD §8.3) and which
   `*ServiceInterface` does this back? Stay in V1 scope; real Mobile Money,
   WhatsApp/SMS, FCM are deferred (PRD §8 / OQ-1).
2. **Lock the contract first.** Define/adjust the path + DTOs in
   `docs/api/openapi.yaml` so request/response shapes mirror the app's Dart
   models field-for-field. The contract changes *with* the code, never after.
3. **Find the pattern to copy.** `routes/health.dart` + `routes/providers/`
   (handlers), `lib/src/providers_repository.dart` (repository behind an
   interface). Don't invent a new shape.

## While writing code — the patterns that must hold
- **Layering (one direction):** `routes` (thin: parse → authorize → delegate →
  shape) → `services` (business logic, no `dart_frog`, no SQL — the testable
  core) → `repositories` (interface; in-memory now → Postgres later) → DTOs.
  A route never holds business rules or touches storage. (BACKEND.md §1)
- **Error envelope:** every non-2xx is `{ "error": "<machine_code>", "message"? }`
  with the right status (400/401/403/404/409/422/429/5xx) and a 405 for bad
  verbs. Never leak stack traces / SQL / framework errors. (§2)
- **Pagination:** lists return `{ items, page, pageSize, total }`; clamp
  `pageSize` server-side. No unbounded lists. (§2, §4)
- **Security inline (§3) — the non-negotiables:**
  - **AuthN:** access = signed JWT (HS256, ~15 min); refresh = opaque, **hashed
    at rest**, **rotated each use**, reuse → revoke the family.
  - **OTP:** hashed at rest, short TTL, **server-side rate-limit + lockout**;
    dev code returned inline only when `ENV != prod`; never logged.
  - **AuthZ:** deny by default; resolve the principal in middleware; **ownership
    check on every resource** (A's token must not touch B's data → 403).
  - **Validate every input** at the boundary (phone E.164, OTP, body schema,
    enums, ranges) → 400 + code. The **server is the authority** on prices,
    totals, ids, status — recompute/verify; never trust the client.
  - **Secrets:** none in code/git; config via env (`.env` gitignored;
    `.env.example` documents keys). 
  - **Logging:** structured + request-id; **never log** OTPs, tokens, refresh
    hashes, `Authorization`, or PII — redact.
  - **Idempotency:** money/booking mutations take an idempotency key (when those
    slices land).

## After writing code — run this every time
Treat any unchecked box as "not done":
- [ ] `dart format` clean · `dart analyze --fatal-infos --fatal-warnings` = **0**.
- [ ] Tests green: **unit** (services/repos), **handler** tests (success + 4xx +
      405), **contract** (matches OpenAPI), and — for anything auth-touching —
      the **REQUIRED security/negative tests**: expired/invalid/replayed tokens,
      missing auth, rate-limit/lockout, **cross-tenant access → 403**.
- [ ] **Contract updated** in the same PR; responses match it.
- [ ] **No secrets** added (gitleaks will fail otherwise); new config via env +
      `.env.example`. **OSV** dependency scan clean.
- [ ] **AuthZ:** deny-by-default + ownership checks on any new resource.
- [ ] **Threat model (BACKEND.md §7) updated** if the PR adds an endpoint or
      trust boundary.
- [ ] Errors use the standard envelope; correct status codes; no internal leak.
- [ ] **Performance:** paginated, no N+1, budgets respected (BACKEND.md §4).

## Before a commit / PR (shared with the app skill)
- **Feature-branch + PR**, never push `main`; open a PR and leave merging to the
  user. Conventional commit, **authored as the user — no Claude author /
  `Co-Authored-By`**.
- All CI jobs green (mobile · backend · security) before requesting merge.
- **Refresh `docs/ROADMAP.md`** (slice status) so the roadmap stays trustworthy.
- Never commit secrets, `.env`, or build artifacts.

## Keep the guardrails honest
When a real decision changes a rule (new pattern, revised budget, resolved
question), update **docs/BACKEND.md** (and the contract) in the same change.
Stale rules are worse than no rules.
