# Web M7.3e-ii — pro Médias (Photos + Avant/Après) `/pro/medias`

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001 + FR-DISC-006, M7.3e-ii. The **last pro slice** (finishes M7). |
| **Mirrors** | the app's `/pro/photos` + `/pro/before-after` (`mobile/lib/screens/provider/photos/`). |
| **Surface** | `web/app/pro/(dash)/medias` + pro-BFF upload/save routes — **no backend change**. |
| **Skill** | `myweli-web-guardrails`. Memory: [[web-mirror-app-flow]]. |
| **Status** | **Built (Option A)** — `/pro/medias` Photos (grid, reorder/remove, upload) + Avant/Après (pairs, upload); full browser upload via `/uploads/sign` → R2; 5 unit + 1 e2e. **Finishes M7.** |

## 1. Goal & app parity
Manage the salon's **Photos** (ordered gallery; 1st = couverture) and **Avant/Après**
pairs on the web, mirroring the app's two editors.

## 2. The pipeline (exists)
`POST /uploads/sign {contentType, purpose:'gallery'}` (provider role) → presigned
**POST** `{uploadUrl, fields, publicUrl}`; the browser POSTs the file to R2
directly, then saves the URL via `PUT /providers/{id}/gallery` (ordered
`imageUrls`) or `PUT /providers/{id}/before-after` (≤12 `{before,after,caption?}`).
R2 is configured at the **accounts phase** (no creds in dev/CI).

## 3. Upload approach — DECISION (OQ-7.3e-ii-1)
- **Option A — full browser upload (recommended).** File picker → `/uploads/sign`
  → presigned POST to R2 → save URL. Parity-complete ("client is king", matches the
  editable-Profil call). The R2 POST only succeeds once storage is live (accounts
  phase); **e2e stubs `/uploads/sign` + the upload endpoint**. Heaviest UI.
- **Option B — manage existing + add-in-app.** Web reorders/removes existing photos
  & pairs (no upload); **adding new images stays in the app** (like the consumer
  deposit screenshot). No R2 dependency; fully testable now; smaller.

## 4. UX (assuming A) & flow
- **`/pro/medias`** (linked from Profil; "Médias" card → live). Authed gate as M7.0.
- **Photos** tab: ordered grid from `provider.imageUrls` (1st badged « Couverture »)
  · **Ajouter une photo** (file → upload → append) · remove (confirm) · reorder
  (↑/↓). Save → `PUT …/gallery`. Hint: « Ajoutez au moins 3 photos ».
- **Avant/Après** tab: list of pairs (before|after thumbnails + caption) · add a pair
  (two uploads + optional caption) · remove. Save → `PUT …/before-after` (≤12).
- States: loading · empty · **uploading** (progress/disabled) · error (upload/save) ·
  success.

## 5. Data / security (no backend change)
Pro BFF: `POST /api/pro/uploads/sign` (→ `/uploads/sign`, provider-scoped), then the
browser POSTs bytes **direct to R2** (never through our API), then
`PUT /api/pro/medias/gallery` / `…/before-after` (→ the provider endpoints; client
passes its own `providerId`; backend re-validates URL allowlist/caps + ownership).
Pro httpOnly cookies; `/pro/*` `noindex`.

## 6. Tests
- **Unit:** gallery reorder/remove + cover logic; before/after pair add/remove + the
  ≤12 cap; the upload helper's sign→POST→url sequence (mocked fetch).
- **e2e:** provider → `/pro/medias`: reorder/remove an existing photo → save; add a
  photo (stubbed `/uploads/sign` + upload endpoint) → appears. Stub the sign + R2 POST.

## 7. Open questions (proposed defaults)
- **OQ-7.3e-ii-1** Upload = **Option A (full browser upload)** → default (vs B).
- **OQ-7.3e-ii-2** One PR (Photos + Avant/Après) vs split (Photos → Avant/Après) →
  default one PR; split if it runs heavy.
