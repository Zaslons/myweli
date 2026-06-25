# <Part name> — design spec

> Copy this file to `docs/design/<part>.md` and fill it in **before** writing code. Delete sections that genuinely don't apply (say why). Keep it concise but complete — this is the source of truth for the part.

| | |
|---|---|
| **Status** | Draft · Approved · Built · Superseded |
| **Owner** | <who> |
| **Last updated** | YYYY-MM-DD |
| **PRD ref / phase** | <requirement id> · V1 / V2 / V3 |
| **ROADMAP entry** | <link to the ROADMAP line> |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails (if `backend/`) |

## 1. Goal & scope
- **What** we're building and **why** (the user/business value).
- **In scope** / **out of scope** (and what's deferred to a later slice).
- How it **fits the agreed architecture** — which layer(s), which `*ServiceInterface`, mock-first, etc.

## 2. UX & flows  *(user-facing parts)*
- **Entry points** — every place the user arrives from.
- **Happy path** step by step (minimize taps), plus the **branches**.
- **All states**: loading, empty, error, success, offline, permission-denied, auth-gated.
- **Edge cases**: bad/slow network, slow/failed Mobile Money, missing data, long French strings, low-end Android.
- **Copy** — the French microcopy for labels, errors, empty states.
- **Reuse** — existing components/patterns it builds on.

## 3. API & contract
- Endpoint(s): method, path, auth, request/response shape, status + error codes.
- The **`docs/api/openapi.yaml`** changes (DTOs mirror the Dart models field-for-field).
- Client service: which `*ServiceInterface` / `Api*Service` method maps to it.

## 4. Data model
- Tables / columns / indexes; **migrations** (id + statements).
- Time = UTC; money/units; nullability; relationships & cascade rules.

## 5. Architecture & patterns
- Where it sits in `routes → services → repositories → DTOs` (backend) or `models → services(interface+mock) → providers → screens` (app).
- New interfaces + mock impls; DI wiring; no layer skipped.

## 6. Security & authz
- AuthN/AuthZ: who can call it; **ownership checks**; deny-by-default.
- Input validation at the boundary; **server is the authority** on prices/ids/status.
- **Threat-model delta** (docs/BACKEND.md §7) — new rows if a surface/trust boundary changes.
- Secrets/PII handling; nothing sensitive logged.

## 7. Performance
- Budgets touched (cold start, 60fps lists, p95 read, payload size); pagination; N+1 avoidance; caching.

## 8. Testing plan
- **Unit** (models/services/repos), **handler/widget**, **contract**, and the **required security/negative tests** (expired/invalid/replayed tokens, missing auth, rate-limit/lockout, cross-tenant → 403). Golden/integration if on a critical flow.

## 9. Rollout & scope discipline
- Feature flag / `useApiBackend` gating; mock stays default until ready.
- V1-only; no V2/V3 surface shipped or made reachable.

## 10. Definition of done
- [ ] `analyze` = 0 · format clean · tests green · coverage not down.
- [ ] Contract + ROADMAP + threat model updated in the same PR.
- [ ] Spec cross-linked from the code/contract it governs; spec status updated.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Open questions
- <decisions still needed — resolve before/with the user>
