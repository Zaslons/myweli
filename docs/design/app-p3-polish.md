# App P3 polish batch (audit 1.8-app / 1.11 / 3.6 / 15.2-app) — the FINAL parity batch

**Status:** Built (PR fix/parity-p3-app-polish) · **Audit:**
[parity-audit-modules-2026-07.md](parity-audit-modules-2026-07.md) ·
**No backend change** — the manual-booking POST already accepted `artistId`;
the gallery PUT already persists order.

## Scope — the last four findings

1. **1.8-app « Spécialiste » on the consumer detail** — the booking's
   `artistId` is resolved once (`getProviderById`, guarded post-frame lookup,
   cached in state) → an « Avec » info row. The web half shipped in P3-web.
2. **1.11 gap-slot artist prefill (J1b §4.2)** — « Libre » rows now carry the
   journal's ACTIVE artist filter into the manual booking: `artistId` threads
   `_gap` → router extra → `ProManualBookingScreen(initialArtistId)` → the
   create payload (interface → mock → API — the backend accepted it all
   along; the web grid already did this). The « Sans artiste » filter ('')
   and « Tous » (null) pass nothing.
3. **3.6 photo reorder** — the salon photos grid gains ←/→ controls per tile
   (grid idiom; web's list uses ↑/↓): `ProGalleryProvider.movePhoto` swaps
   and saves through the existing `updateGalleryPhotos` PUT (revert on
   failure). The first photo stays the cover, as the header copy says.
4. **15.2-app « Aide & Support »** — the profile row showed « Fonctionnalité
   à venir »; it now opens WhatsApp support (`AppConfig.supportWhatsApp`,
   the subscription screen's exact degrade: empty → « Contact bientôt
   disponible. »). The web half shipped in P3-web.

## Tests

- Widget: the detail shows « Avec {artist} » when the booking carries an
  artistId (mocked provider lookup); the photos screen reorders on → and
  saves the permuted list.
- Unit: `movePhoto` bounds + swap + revert-on-failure;
  `createManualBooking` forwards `artistId` (API service body).
- analyze 0 · full suite green.
