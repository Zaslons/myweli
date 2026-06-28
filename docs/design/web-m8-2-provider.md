# Web M8.2 — provider page extras + two-column layout

| | |
|---|---|
| **Requirement** | FR-WEB-PP-001; closes parity gap **G2** ([web-parity-audit.md](web-parity-audit.md)). |
| **Design** | web-own, **desktop two-column** + responsive ([[web-design-latitude]]), Planity-style sticky booking panel. |
| **Surface** | `web/components/provider/*` — **no backend change** (all fields on `Provider`). |
| **Status** | **Built.** |

## 1. What & why
The provider page is the conversion surface. It already had services, hours,
reviews, contact, **équipe** and a localisation **link**. M8.2 adds the missing
pieces + a desktop layout that uses the width.

## 2. Layout
- **Desktop: two columns** — main (gallery · services · Avant/Après · équipe ·
  horaires · avis · carte · contact · FAQ) + a **sticky booking panel** aside
  (à-partir-de price · Réserver → `/(slug)/reserver` · Appeler/WhatsApp).
- **Mobile: one column** + a **fixed bottom booking bar** (à-partir-de + Réserver);
  contact shown inline (the panel is desktop-only).

## 3. New / upgraded
- **Avant / Après** (`BeforeAfter`) — side-by-side pairs + caption (was missing).
- **Galerie** (`Gallery`) — the `imageUrls` beyond the hero cover (was hero-only).
- **Carte** (`MapEmbed`) — interactive **OpenStreetMap embed** (no API key) +
  Itinéraire link (was a link only).
- **Booking panel** (`BookingPanel`) + mobile bar — à-partir-de (`minActivePrice`).
- Équipe + Localisation address kept (restyled into the columns).

## 4. Data / SEO / perf (no backend change)
All from `Provider` (`imageUrls`, `beforeAfters`, `artists`, `latitude/longitude`).
JSON-LD unchanged (LocalBusiness/Review/FAQ/Breadcrumb already strong; geo in
LocalBusiness). Images = plain `<img loading="lazy">` (next/image allowlist at the
content phase); the OSM iframe is `loading="lazy"`. No CSP to amend.

## 5. Tests
- **Unit:** `minActivePrice` (skips inactive), `osmEmbedUrl` (bbox+marker),
  `directionsUrl`.
- **e2e:** provider page shows Avant/Après + the map iframe + the booking panel
  (à-partir-de + Réserver → `/beaute-divine/reserver`).

## 6. Open questions (resolved)
- Map = **OSM embed** (free, no key) + Itinéraire. · Avant/Après = side-by-side
  (drag-reveal slider deferred). · Booking = sticky aside (desktop) + bottom bar
  (mobile). **Closes G2.** Next: **M8.3** account extras (rebook · avis · favoris).
