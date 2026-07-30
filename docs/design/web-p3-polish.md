# Web P3 polish batch (audit 1.2 / 1.3 / 1.4 / 1.8-web / 2.6 / 2.7 / 2.8 / 2.15 / 3.5 / 4.1 / 15.2)

**Status:** Built (PR fix/parity-p3-web-polish) · **Audit:**
[parity-audit-modules-2026-07.md](parity-audit-modules-2026-07.md) ·
**No backend change** — every payload field (notes, artists, imageUrl,
deposit-screenshot signed GET) already existed.

## Consumer booking detail (1.2 · 1.3 · 1.4 · 1.8)

- **1.2 « Ajouter au calendrier »** — pure helpers (`lib/account/calendar.ts`,
  unit-tested): a Google-Calendar template URL + a client-built `.ics`
  download (UTC stamps, duration-based end, salon name + address). Rendered
  for upcoming bookings, like the app.
- **1.3 « Voir ma capture »** — new BFF
  `GET /api/appointments/{id}/deposit-screenshot` proxying the signed-GET;
  with `?redirect=1` it 307s to the signed URL so the UI is a plain
  new-tab link next to « Justificatif envoyé ».
- **1.4 Notes row** — the payload always carried `notes`; the detail now
  shows the row when present.
- **1.8 Spécialiste row** — the BFF enrichment (already fetching the full
  public provider) now maps `artistId` → `artistName`; the detail shows
  « Spécialiste » when the booking has one. (The app half ships in the
  app-side P3 PR.)

## Salon page (2.6 · 2.7 · 2.8)

- **2.6 Gallery lightbox** — a shared `Lightbox` component (fullscreen
  overlay, backdrop/✕ close — extracted from ReviewList's viewer, which now
  reuses it); the gallery grid becomes tappable.
- **2.7 « Vos rendez-vous ici »** + **2.8 review invite** — one client island
  (`SalonVisitsCard`): a single session probe (anonymous 401 → renders
  nothing, the HeaderBell pattern), then the signed-in client's bookings AT
  THIS salon — upcoming (date · heure, link to the detail) + « Voir tout » →
  /mon-compte, and « Donner votre avis » on the latest reviewable completed
  visit → its detail (the ReviewForm lives there).

## Discovery (2.15)

- Hearts on the /recherche result cards: the client fetches the favorites
  ONCE (anonymous → none), renders a heart overlay per card; toggling calls
  the favorites API; 401 → /connexion with returnTo. Map-marker hearts stay
  deferred (as audited).

## Pro dashboard (3.5 · 4.1)

- **3.5 artist photo** — the Équipe form gains an avatar upload
  (`uploadGalleryImage` pipeline) + preview + remove; `imageUrl` rides the
  existing artist PATCH allowlist.
- **4.1 custom tags** — the client-card tag editor gains the app's free-text
  input to mint a new tag (same PUT).

## Support (15.2)

- « Aide & Support » on /mon-compte → the existing wa.me pattern
  (`NEXT_PUBLIC_MYWELI_WHATSAPP`, the Abonnement precedent). The app's OWN
  dead « Aide & Support » button (audit undersold it — it's a
  « Fonctionnalité à venir » snackbar) gets wired in the app-side P3 PR.

## Tests

Unit: calendar URL/ics builders. e2e: detail (calendar hrefs · notes ·
spécialiste · « Voir ma capture » href on a pending-with-proof booking),
gallery lightbox open/close, salon visits card + review invite (signed-in),
/recherche heart toggle, artist photo field, minted custom tag, support link.
