# Web pro reviews — « Avis » on the pro dashboard

| | |
|---|---|
| **Module** | `reviews` (consumer reviews, salon-side view) — web parity slice |
| **Status** | **Built** (2026-07-10) — one PR: page + sidebar entry + BFF + tests |
| **Trigger** | Parity follow-up flagged on the ROADMAP (web-pro-registration audit): the pro app has an « Avis » dashboard tile → `ReviewsScreen`; the web pro dashboard has nothing |
| **Scope** | Web only, **no backend change** — reads the public paginated `GET /providers/{id}/reviews` (the same source the app uses), salon resolved **server-side from the pro session** |
| **Out of scope** | Replying to reviews / pro-side reporting (`POST /reviews/{id}/report` is consumer-only by design, FR-REV-005; a YCLIENTS-style salon reply belongs to the future reviews module doc) · moderation (admin console A2, built) |
| **Cross-refs** | `reviews_screen.dart` (the reference) · [web-parity-audit.md](web-parity-audit.md) · MODULES.md §2 (reviews live in `online-booking`) |

## 1. The app screen being mirrored (read 2026-07-10)

`ReviewsScreen`: a **summary card** (star + average to 1 decimal + « n avis »,
and the **5→1 rating distribution** as labelled progress bars with counts)
over a **list of review cards** (initial avatar · name · 5 stars · short date
· text). Read-only — no reply/report on the pro side. Empty state: « Aucun
avis » / « Les avis de vos clients apparaîtront ici ».

## 2. UX — `/pro/avis` (web-adapted, desktop-native)

- **Sidebar** gains « Avis » (the app's dashboard tile equivalent).
- **Summary card**: average (1 decimal) + « n avis » on the left, the 5→1
  distribution bars (count + percentage width) on the right — the app card,
  responsive (stacks on narrow).
- **Review cards**: initial avatar · `userName` · star row · date (fr) ·
  `text` · the visit context the web type already carries
  (`serviceName` · « avec {artistName} ») · `photoUrls` thumbnails when
  present (consumer photo reviews).
- **Pagination**: « Charger plus » (pageSize 50 — the server clamp; stats are
  computed over the loaded items, which pre-launch means all of them).
- Four states: loading text · the app's empty copy · error + « Réessayer » ·
  success.

## 3. Layering & security

- **BFF `GET /api/pro/reviews?providerId=&page=`** — the established pro-BFF
  idiom (the client sends its own providerId; here the upstream endpoint is
  **public** data, so nothing is exposable); kept behind the pro
  httpOnly-cookie session like every `/api/pro/*` route. No new trust
  boundary.
- Pure helpers in `lib/pro/reviews.ts`: `reviewStats(items)` → average /
  total / per-rating counts + percentages (unit-tested; the app's summary
  math).
- Page = client component on the existing pro-dash pattern (`getMyProvider`
  session probe → redirect to `/pro/connexion` on 401).

## 4. Tests

- Unit: `reviewStats` (empty, single, mixed distribution, rounding).
- e2e: login → sidebar « Avis » → summary (average + « 2 avis » +
  distribution) + review cards visible; stub serves a photo review.

## 5. Rollout

One PR (`feat/web-pro-reviews`): page + sidebar + BFF + helpers + stub +
tests + this spec; README index + ROADMAP refreshed. Gates: tsc/lint/build ·
unit · e2e.
