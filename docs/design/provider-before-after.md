# Provider before/after showcase (FR-DISC-006)

| | |
|---|---|
| **Requirement** | FR-DISC-006 (provider profile: before/after gallery) |
| **Phase** | Phase 3 — backend build + integration (discovery polish) |
| **Status** | PR1 backend ✅ · PR2 pro app ✅ · **PR3 consumer app — next**. |
| **Decision** | Build the full vertical, UX-first. Consumer display = **drag-to-reveal slider** (signed off 2026-06-27). |
| **Reuses** | The gallery pattern ([pro-gallery.md](pro-gallery.md)) + image-upload pipeline ([pro-image-upload-pipeline.md](pro-image-upload-pipeline.md)) — **no migration**, same signed upload. |

## 1. Goal & scope
A salon curates **before/after pairs** of its work; consumers see them on the
profile as an interactive drag-to-reveal slider. Three thin slices, each
spec-first + tested:
- **PR1 (backend):** store + validate the pairs; `GET`/`PUT
  /providers/{id}/before-after`; surface `beforeAfters` on the public provider.
- **PR2 (pro app):** an "Avant / Après" management screen (add/list/delete pairs
  via the existing image uploader).
- **PR3 (consumer app):** the "Avant / Après" profile section (slider + thumbs +
  tap-to-fullscreen).

Out of scope: video, AI auto-pairing, per-pair ordering UI beyond add/remove.

## 2. Data model (no migration)
Pairs live in the provider's `data` jsonb, alongside `imageUrls` — exactly like
the gallery, so **no migration**:
```jsonc
"beforeAfters": [
  { "before": "<url>", "after": "<url>", "caption": "Tresses collées" }
]
```
- `before`, `after`: image URLs uploaded out-of-band via the signed pipeline
  (public bucket), validated like gallery URLs.
- `caption`: optional, ≤120 chars, trimmed.
- Caps: ≤12 pairs; each URL non-empty, ≤2048 chars, and (when public delivery is
  configured) **origin-allowlisted** (anti-SSRF/hotlink) — same rule as gallery.

## 3. Contract / endpoints (mirror `/gallery`)
- `GET /providers/{id}/before-after` → `{ "beforeAfters": [...] }`. **Provider-only
  + ownership** (the token's account must manage `{id}`) → 403 otherwise.
- `PUT /providers/{id}/before-after` body `{ "beforeAfters": [{before, after,
  caption?}] }` — replaces the list wholesale (same model as gallery). 400
  `invalid_input` on a bad shape/URL/caption; 404 unknown provider.
- **Public read:** the consumer `GET /providers/{id}` already returns the whole
  `data` doc, so `beforeAfters` surfaces automatically (no extra endpoint).

## 4. Layering / impl
- `ProviderCatalogService.beforeAfters` + `updateBeforeAfters` — validation +
  ownership, mirroring `gallery`/`updateGallery` (`_allowedImageOrigins`,
  `_maxUrlLength`; new `_maxBeforeAfterPairs = 12`, `_maxCaptionLength = 120`).
- `ProvidersRepository.updateBeforeAfters(providerId, List<Map>)` — in-memory sets
  `p['beforeAfters']`; Postgres read-modify-writes the `data` jsonb `FOR UPDATE`
  (identical to `updateGallery`).
- Route `routes/providers/[id]/before-after.dart` (GET/PUT) — thin, copies
  `gallery.dart`.

## 5. Security (threat model — extends T12 catalogue mgmt)
- Provider-only + **ownership** on read and write (cross-salon → 403).
- **Boundary validation** of every URL (length + origin-allowlist) and caption
  length; the server stores only validated strings — **no bytes through the API**
  (uploaded to object storage out of band, like gallery). Same posture as T12;
  no new trust boundary.

## 6. Consumer UX (PR3)
- A dedicated **"Avant / Après"** section on the salon profile (above reviews),
  shown only when `beforeAfters` is non-empty (else omitted — not an empty box).
- Each pair = a **drag-to-reveal slider** (one frame; a draggable handle wipes
  between before/after, labelled *Avant*/*Après*), an optional caption, and a
  thumbnail strip to switch pairs; tap → fullscreen. `TimedCachedImage`, tokens
  only, low-end-Android-cheap (a clip-rect wipe, no heavy compositing).

## 7. Pro UX (PR2)
- "Avant / Après" management screen (entry from the profile/gallery area): list
  existing pairs (before+after thumbs + caption, delete); **Ajouter** → pick
  *avant* → upload, pick *après* → upload, optional caption → **Enregistrer**
  (`PUT`). Reuses `ImageUploadServiceInterface`. Four states; French.

## 8. Tests
- Service: save ok · >12 pairs → invalid · pair missing `after` → invalid · bad
  URL/origin → invalid · caption >120 → invalid · cross-salon → 403 · unknown → 404.
- Route: GET/PUT happy + 403 (consumer) + 405.
- App (PR2/PR3): provider model `beforeAfters` round-trips; pro add/delete; the
  consumer section renders pairs + hides when empty.

## 9. Rollout
Pure feature, flag-free; empty for every salon until pros add pairs. No migration,
no config. Photos ride the existing upload pipeline (real bytes need R2 — already
the case for the gallery).
