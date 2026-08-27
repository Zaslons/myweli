# « Définir comme photo principale » — design spec

| | |
|---|---|
| **Status** | Built |
| **Module** | `catalogue` (médias pro) — [docs/MODULES.md](../MODULES.md) |
| **Surfaces** | App pro (`pro_photos_screen.dart` + `pro_gallery_provider.dart`) · Web pro (`MediasClient.tsx` + `lib/pro/medias.ts`) |
| **Origin** | Curation feedback 2026-08-26 — promouvoir la photo n°6 coûte cinq flèches = cinq PUT |
| **Contract** | AUCUN changement — « Order is preserved: imageUrls[0] is the listing cover » est déjà le contrat |

## 1. Goal & scope

La couverture EST `imageUrls[0]` sur toutes les surfaces (cartes, détail,
Hero, OG, sitemap). Le seul chemin pour promouvoir une photo est aujourd'hui
la flèche voisine — n gestes, n écritures. Un geste direct : « Définir comme
photo principale ».

Hors scope : drag-and-drop (V2 si demandé), golden dédié (aucun n'existe
pour ces écrans — resté volontairement léger, noté), tout changement serveur.

## 2. UX & flows

- **App** — une étoile en haut-gauche des vignettes NON-couverture (le ✕ est
  en haut-droite, les flèches en bas, le badge « Couverture » en bas-gauche
  de la première vignette seulement — le coin est libre). Même idiome que le
  ✕ : zone 48px, pastille noire, `Semantics(button)` « Définir comme photo
  principale ». Tap → `setCover(i)` = `removeAt(i)` + `insert(0)` + **UN
  PUT** wholesale. Pas de confirm (réversible d'un geste, non destructif) ;
  pas de snackbar succès (le badge « Couverture » saute sur la vignette même
  — le feedback est sur la surface qui a causé le geste) ; snackbar erreur
  en échec — mieux que les flèches, qui jettent le futur.
- **Web** — un `IconBtn` ★ à côté de ↑ ↓ ✕ sur les vignettes non-couverture,
  `aria-label` « Définir comme photo principale ». STAGED comme tout
  l'onglet : `setPhotos(toCover(photos, i))`, persiste via « Enregistrer ».
- La règle du provider (`restorePhotoAt`) tenue : dériver de `_photos` AU
  MOMENT de l'appel, jamais d'une liste capturée.

## 3–4. API & data

Aucun. Le PUT galerie wholesale existant ; l'ordre est la donnée.

## 5. Architecture & patterns

App : `setCover` à côté de `movePhoto`, même forme succès/erreur. Web :
`toCover` pur dans `lib/pro/medias.ts` à côté de `moveItem`/`removeAt`.

## 6–7. Security & performance

Rien de nouveau — même écriture, mêmes portes (`catalogue.manage`), une
écriture au lieu de n.

## 8. Testing plan

- App unit (à côté de `gallery_reorder_test.dart`) : `setCover(2)` persiste
  `['c','a','b']` ; `i == 0` / hors bornes → aucun appel réseau ; l'échec
  remonte l'erreur ; dérive de la liste COURANTE (après un ajout, le PUT
  contient l'ajout).
- App widget (nouveau, harnais `availability_blocked_dates_test.dart`) :
  l'étoile absente de la vignette couverture, présente ailleurs ; tap →
  PUT avec le nouvel ordre.
- Web unit (à côté de `pro-medias.test.ts`) : `toCover` promeut en tête,
  ordre relatif du reste préservé, no-op à 0 / hors bornes.
- Mutations : insert en queue au lieu de la tête ; dérivation d'une liste
  capturée ; `toCover` identité ; étoile rendue aussi sur la couverture ;
  câblage du bouton retiré.

## 9–10. Rollout & DoD

Une PR, rejoint le lot versionCode 527. Gates verts · mutations rouges ·
ROADMAP entry · ce spec en Built.

## 11. Open questions

Aucune.
