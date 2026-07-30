# Consumer web discovery map — the /recherche split view

| | |
|---|---|
| **Module** | `online-booking` (consumer discovery) — the LAST web-parity follow-up |
| **Status** | **Built** (2026-07-10) — layout signed off in chat; **design revision same day (user)**: full-bleed + the app MapScreen's design; **renderer upgrade same day (user)**: Leaflet retired for **MapLibre GL + the CARTO Positron VECTOR style** (the open-source version of Planity's Woosmap/OpenMapTiles stack; still keyless/free) |
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

- **Desktop (`lg:`)**: results list left (~55%) + the map right, **full-bleed
  — part of the screen, not a box** (no border/radius; flush to the right
  and bottom viewport edges; `sticky top-0 h-screen`, so it owns the full
  height once the static header scrolls by — the Planity behaviour). The
  search bar + **category chips** live INSIDE the left column so the map
  rises to the header. Chips re-query `/recherche` with the `category`
  param the page already accepts.
- **Two-way sync**: hovering a list card highlights (enlarges) its marker;
  clicking a marker opens a **popup mini-card** (name · ★ note · commune ·
  « à partir de » · Voir le salon / Réserver) AND scrolls the list to the
  matching card, highlighted with a ring. The app's marker→sheet flow,
  desktop-shaped.
- **Mobile web**: no split — the list keeps today's behaviour and a floating
  **« Carte »/« Liste »** toggle flips to a full-bleed, full-height map with
  the same markers + popups (the app experience on a small screen). The
  toggle transition requires `invalidateSize` — see §3.
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

- **MapLibre GL (`maplibre-gl` + `@vis.gl/react-maplibre`) with the CARTO
  Positron VECTOR style** (`basemaps.cartocdn.com/gl/positron-gl-style`) —
  the vector twin of the app MapScreen's `light_all` raster basemap: same
  design language, still keyless/free, crisper rendering and smooth zoom.
  This is the open-source equivalent of the Woosmap+OpenMapTiles stack
  Planity buys (renderer upgrade decided by the user 2026-07-10; Leaflet
  removed). **Dynamically imported with `ssr: false`** so the chunk (larger
  than Leaflet's — the WebGL trade-off, accepted) loads only on `/recherche`
  (noindex, force-dynamic — public-page CWV budgets untouched).
  Markers are **plain React elements replicating `_SalonMarker`**: a 44 px
  white-circle button (keyboard-focusable, aria-labelled), 2 px
  category-color ring, the category icon (Material spa / content_cut /
  face / store paths) — §7 tokens from `styles/tokens.ts` via
  `currentColor`; active state is just a class (`.is-active`; scale on the
  pin — MapLibre owns the wrapper transform). « Autour de moi » drops the
  app's 22 px info-blue user dot and flies to the user. **Popup gotcha
  (learned the hard way):** the selecting click bubbles to the map AFTER
  React mounts the popup, so the default `closeOnClick` closes it within
  the same gesture — the popup sets `closeOnClick={false}` (deselect = ✕
  or another marker). MapLibre observes its container size natively, so
  the mobile toggle's display:none mount needs no manual resize handling.
  Note: markers/popups render even if the style fetch fails (DOM overlay,
  not canvas) — the hermetic e2e aborts the CARTO host and still exercises
  the full interaction. CARTO's free basemap policy is fine at our
  traffic; swap the style URL to a paid host (e.g. MapTiler) if volume
  grows (noted, not built).
- Page stays a **server component** (same `searchProviders` fetch, same
  noindex) → passes results to a client `RechercheClient` (chips + list +
  hover state + mobile toggle) which mounts `ResultsMap`.
- **One map identity site-wide**: the style + salon pin live in
  `components/map/salon-pin.tsx`, shared with the salon page's Localisation
  map (`SalonLocationMap`, lazy in-view mount — web-m8-2-provider.md).
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
