# Pro catalogue app wiring (ApiProService → backend) — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro services + availability management (app) · V1 |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-dev-guardrails ✓ |
| **Backs** | [provider-services-availability-backend.md](provider-services-availability-backend.md) (the endpoints this consumes) |

## 1. Goal & scope

Swap `ApiProService`'s **services + availability** methods from the embedded `MockProService` to the real backend endpoints shipped in #62/#63 — so the pro app's service-list / service-form / availability screens manage the real catalogue when `--dart-define=USE_API_BACKEND=true`.

**In scope (the 7 methods that now have a backend):**
- `getProviderServices` → `GET /providers/{id}/services`
- `createService` → `POST /providers/{id}/services`
- `updateService` → `PATCH /providers/{id}/services/{serviceId}`
- `deleteService` → `DELETE /providers/{id}/services/{serviceId}`
- `setServiceActive(serviceId, bool)` → `PATCH …/services/{serviceId}` with `{active}` (**replaces** the old `toggleServiceAvailability(serviceId)` — signed off; the UI already knows the current state, so no read-then-write)
- `getProviderAvailability` → `GET /providers/{id}/availability`
- `updateAvailability` → `PUT /providers/{id}/availability`

**Out of scope (no backend yet → stay delegated to `MockProService`):** dashboard stats, gallery photos, earnings, deposit policy, manual booking, pro-side reschedule. (Each is its own future slice.)

**Fit:** pure service-layer swap behind the existing `ProServiceInterface` — same pattern as the consumer `ApiAppointmentService` and the pro-appointments wiring already shipped. Authenticated calls reuse the existing `RefreshingHttpClient` (provider session + `/auth/provider/refresh`) → **provider silent refresh comes for free**. Mocks remain the default; nothing changes unless `useApiBackend` is on.

## 2. UX & flows
**No UX change.** This is a swap behind the interface; `service_list_screen`, `service_form_screen`, and `availability_screen` keep their existing loading/empty/error/success handling. Error copy is surfaced via `ApiResponse.error` (French), already consumed by those screens.

## 3. API & contract
**No contract change** — the 6 endpoints already exist (`docs/api/openapi.yaml`, B-cat). DTO mapping:
- Service create/update: the screen's `serviceData` map is the request body (server ignores `id`/`providerId`, sets them); response → `Service.fromJson` (now incl. `active`).
- `getProviderServices`: `GET` → `{items:[Service]}` → `List<Service>`.
- Availability: `getProviderAvailability` → `Availability.fromJson`; `updateAvailability` → body `availability.toJson()` → response `Availability.fromJson`.

## 4. Data model
None (app-side only).

## 5. Architecture & patterns
- All seven calls go through `_authed.send(...)` (the existing `RefreshingHttpClient`) → bearer + **silent refresh** on 401 → retry. `/availability`/`/services` are provider-only, so no public path here.
- **Resolving `providerId`:** the four `…(String providerId, …)` methods use the argument. The three `serviceId`-only methods (`updateService`, `deleteService`, `toggleServiceAvailability`) read the salon id from the **persisted `ProviderSession.provider.providerId`** (the app's own linked salon — not a client-trusted value; the backend re-checks ownership regardless). So `ApiProService` keeps a `SessionStore` reference and a `_providerId()` helper. If it's null (unlinked) → return a clear error without a network call.
- **`toggle`** = read-then-write: fetch the salon's services, find `serviceId`, `PATCH {active: !current}`. Service-not-found → error.
- The other `ProServiceInterface` methods keep delegating to the embedded `MockProService`.
- DI already injects the provider `SecureSessionStore`; no DI change beyond passing it (already passed).

## 6. Security & authz
- Provider access token attached by `RefreshingHttpClient`; ownership enforced **server-side** (token's account `providerId` must equal the path `{id}` → 403). The app never sets authoritative ids — it sends its own session's `providerId` in the path, and the server is the authority.
- Backend error codes mapped to French: `forbidden` → "Action non autorisée pour ce salon.", `not_found` → "…introuvable.", `invalid_input` → a generic invalid message, `unauthorized` → "Veuillez vous reconnecter." (extend `ApiProService._messageFor`).
- No secrets; tokens stay in secure storage; nothing sensitive logged.

## 7. Performance
- Small payloads; one extra `GET` for `toggle` (read-then-write) — acceptable (toggles are rare, pro-side). No list pagination needed (a salon's services are few). Budgets respected.

## 8. Testing plan
- `ApiProService` MockClient tests: each method hits the right method+path with the bearer and parses the response; `getProviderServices` parses the `items` envelope; `createService`/`updateService` send the body and parse `Service` (incl. `active`); availability get/put round-trip; **`toggle` does GET-then-PATCH with the negated `active`**; a **401 triggers provider silent refresh + retry**; `forbidden` → error with code; unlinked/no-session → fail fast (no HTTP). Delegated methods (e.g. dashboard) still hit the mock (no HTTP).
- `flutter analyze` 0; full mobile suite green.

## 9. Rollout & scope discipline
- Behind `AppConfig.useApiBackend`; mock is the default. V1; no V2/V3 surface touched.
- Backend already shipped + green, so this is purely additive on the app.

## 10. Definition of done
- [ ] `flutter analyze` 0 · format clean · mobile tests green.
- [ ] All four screen states still work (unchanged); error copy surfaces.
- [ ] No contract change needed (verify the app shapes match the shipped DTOs).
- [ ] Spec cross-linked from `ApiProService`; ROADMAP updated; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions (signed off)
1. **Toggle → `setServiceActive(serviceId, bool active)`** replaces `toggleServiceAvailability(serviceId)` on `ProServiceInterface` (+ mock + the screen call site). The screen passes the desired state; `ApiProService` does a single `PATCH {active}`. ✓
2. **`providerId` for the `serviceId`-only methods** → read from the persisted `ProviderSession.provider.providerId`; the backend re-checks ownership. ✓
