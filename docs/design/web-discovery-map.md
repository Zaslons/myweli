# Consumer web discovery map — the /recherche split view

| | |
|---|---|
| **Module** | `online-booking` (consumer discovery) — the LAST web-parity follow-up |
| **Status** | **Built** (2026-07-10) — layout signed off in chat (list left + sticky map right; user 2026-07-10) |
| **Trigger** | The app's map tab (`MapScreen`) has no web equivalent; `/recherche` renders a bare card grid |
| **Scope** | Web only, **no backend change** — markers come from the same `GET /providers` search results already fetched server-side |
| **Out of scope** | Geo-bounds search (`/providers` has no bbox param — markers reflect the fetched results, like the app) · favorites hearts on markers (session-dependent on a public page; deferred to the parity ledger) · « open now » (module gap, phased) |
| **Cross-refs** | `map_screen.dart` (the reference flow) · [web-m8-1-home-discovery.md](web-m8-1-home-discovery.md) (search + landings) · DESIGN-STANDARDS §7 (category colors — already mirrored in `styles/tokens.ts`) |

## 1. The app flow being mirrored (read 2026-07-10)

`MapScreen` (flutter_map + **OpenStreetMap** tiles, no key): Abidjan default
center (5.336, -4.026, zoom ~11.5) · geolocation centering with graceful
denial copy · **category-colored markers** (the §7 canonical mapping:
spa sage / barber taupe / salon slate, primary fallback) · tap a marker →
provider mini-sheet → detail. Providers without coordinates simply have no
marker.

## 2. UX — the split view (desktop) + « Carte » toggle (mobile web)

Signed-off layout, with the agreed refinements:

- **Desktop (`lg:`)**: results list left (~58%) + **sticky map right**
  (viewport-height, pinned while the list scrolls). Search bar + **category
  chips** (« Tous » + the canonical category list) above; chips re-query
  `/recherche` with the `category` param the page already accepts.
- **Two-way sync**: hovering a list card highlights (enlarges) its marker;
  clicking a marker opens a **popup mini-card** (name · ★ note · commune ·
  « à partir de » · Voir le salon / Réserver) AND scrolls the list to the
  matching card, highlighted with a ring. The app's marker→sheet flow,
  desktop-shaped.
- **Mobile web**: no split — the list keeps today's behaviour and a floating
  **« Carte »/« Liste »** toggle flips to a full-height map with the same
  markers + popups (the app experience on a small screen).
- **« Autour de moi »** button on the map → browser geolocation → fly to the
  user (denied → the app's copy « Autorisez la localisation pour vous
  centrer » as a transient note). Map auto-fits the result bounds otherwise;
  Abidjan default when no marker.
- Salons without coordinates stay in the list (no marker) — count line stays
  list-based.
- Four states: the page keeps its server-rendered results (loading = Next
  navigation), empty copy unchanged, the map pane shows « Aucun salon à
  afficher sur la carte » when no result has coordinates.

## 3. Tech & layering

- **Leaflet + react-leaflet@4** (React 18 pairing) with OSM tiles — the web
  twin of the app's flutter_map+OSM; no API key, no Google dependency.
  **Dynamically imported with `ssr: false`** so the ~40 KB gz loads only on
  `/recherche` (noindex, force-dynamic — public-page CWV budgets untouched).
  Markers are **`divIcon`s** (token-colored dots — avoids Leaflet's bundled
  PNG asset pitfalls and keeps colors on the §7 tokens from
  `styles/tokens.ts`). OSM public tile policy is fine at our traffic; swap
  to a paid tile host if volume grows (noted, not built).
- Page stays a **server component** (same `searchProviders` fetch, same
  noindex) → passes results to a client `RechercheClient` (chips + list +
  hover state + mobile toggle) which mounts `ResultsMap`.
- Pure helpers in `lib/discovery/map.ts` (unit-tested): `markerColor`
  (token mapping + primary fallback), `withCoords`, `boundsFor`,
  `ABIDJAN_CENTER`/`DEFAULT_ZOOM` (the app's constants).
- Security: nothing new — public data, no session, no new endpoint. The
  only external host is the OSM tile server (images).

## 4. Tests

- Unit: `markerColor` mapping/fallback · `withCoords` filtering ·
  `boundsFor` (none/single/multi).
- e2e (tile requests aborted — hermetic): desktop split (list + map + a
  marker) → marker click → popup mini-card → « Voir le salon » href; card
  ring on selection; mobile viewport → « Carte » toggle → map, « Liste »
  back.

## 5. Rollout

One PR (`feat/web-discovery-map`): spec + split view + map + toggle + tests;
README index + ROADMAP refreshed (**web parity list: cleared**). Gates:
tsc/lint/build · unit · e2e.
