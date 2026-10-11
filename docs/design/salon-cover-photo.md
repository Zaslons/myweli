# La photo de couverture de la page salon (mobile — consommateur + Aperçu Pro)

| | |
|---|---|
| **Status** | Built (2026-10-11) — branche `feat/salon-cover-photo`, goldens rendus sous Linux |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-11 |
| **Module** | `online-booking` (la page salon de la marketplace) — [MODULES.md](../MODULES.md) |
| **PRD ref / phase** | FR-DISC-006 (« Provider profile: hero gallery… ») · V1 |
| **ROADMAP entry** | [2026-10-11-salon-cover-photo.md](../roadmap/entries/2026-10-11-salon-cover-photo.md) |
| **Governs** | `mobile/lib/screens/providers/provider_detail_screen.dart` (l'en-tête, la bande « Photos », le cœur) — un seul écran pour `/provider/:id` (app client) **et** `/pro/apercu` (app Pro, `SalonPreviewScreen` → `ProviderDetailScreen(preview: true)`) |
| **Contract** | **Aucun changement.** `imageUrls[0]` est déjà la couverture (`docs/api/openapi.yaml` ~l. 1805 : « Order is preserved: `imageUrls[0]` is the listing cover ») ; `logoUrl` existe ([salon-logo.md](salon-logo.md)) |
| **Skills checked** | myweli-dev-guardrails |

## 1. Goal & scope

**Le constat du propriétaire**, dans l'« Aperçu » de l'app Pro : *« je ne vois pas
la photo de fond comme sur le site »*. Vérifié dans le code avant d'écrire une
ligne :

| | site (`web/components/provider/Hero.tsx`) | app (avant) |
|---|---|---|
| couverture | `imageUrls[0]` pleine largeur, `object-cover`, 224 px téléphone / 320 px dès `sm`, chargée en priorité | **aucune** — `FlexibleSpaceBar.background` était un `Container(color: AppColors.secondary)` |
| logo | cercle de 64 px cerclé de blanc, en bas à gauche **de la photo** ; absent si le salon n'en a pas | 72 dp à côté du nom ; pastille « magasin » si absent |
| « Galerie » / « Photos » | `imageUrls.slice(1)` — la couverture n'est pas répétée ; section absente si vide | toutes les photos, y compris la première ; section toujours là |

Le même écran sert le client (`/provider/:id`) et l'Aperçu Pro — **un correctif
couvre les deux**. Deux autres constats en passant, mesurés :

- **Le cœur « favori » était invisible** : non favori, il était peint en
  `AppColors.secondary` (#FFFFFF) sur l'en-tête blanc — blanc sur blanc
  (`provider_detail_screen.dart`, avant : `color: isFavorite ? favorite : secondary`).
  Il n'apparaissait qu'une fois rouge.
- `docs/design/gallery-set-cover.md` §1 et la ligne 2.9 de
  `parity-audit-modules-2026-07.md` affirmaient que la couverture s'affichait
  déjà « sur le détail » / que le « Hero » était présent « sur les deux » —
  faux pour le mobile. Corrigés dans la même PR.

**Dans le périmètre** : l'en-tête à deux branches (avec / sans photo), le tap
sur la couverture, la bande « Photos » qui saute la couverture, la barre d'état
et la barre d'outils au-dessus de la photo, le cœur visible, les tests, les
goldens, les docs.

**Hors périmètre** (et pourquoi) : tout changement web / backend / contrat
(le site fait déjà ce qu'il faut) ; un titre dans la barre repliée (§13.3 :
« a title may not interpolate data ») ; parallaxe / étirement ; une hauteur
tablette (le site passe à 320 px dès 640 px — l'app n'a pas de mise en page
`medium`, SYSTEM §10/§22) ; le repli `via.placeholder.com` de `ProviderCard`
(§11, signalé, pas corrigé ici).

## 2. UX & flows

**Points d'entrée** : accueil (cartes, favoris, derniers rendez-vous), liste,
carte, favoris, lien profond `/provider/:id`, et dans l'app Pro « Aperçu de ma
page » (`/pro/apercu`). Tous arrivent sur `ProviderDetailScreen` ; aucun ne
change.

### 2.1 Branche A — le salon a au moins une photo (`imageUrls[0]` non vide)

Ordre de lecture, de haut en bas :

1. **La couverture** — `imageUrls[0]`, pleine largeur, **224 dp sous la barre
   d'état** (le `h-56` du site sur téléphone), bord à bord : elle passe sous la
   barre d'état et sous la barre d'outils. `BoxFit.cover`, centré (le
   `object-cover` du site).
2. **Un dégradé en haut** (noir 60 % → transparent, du haut de l'écran au bas
   de la barre d'outils). C'est le voile §19 des stories — même valeur que
   `story_viewer.dart` (0x99) : il rend lisibles les icônes **claires** de la
   barre d'état sur n'importe quelle photo, y compris un mur blanc.
3. **La barre d'outils** — « Retour » et le cœur sur des **pastilles blanches
   à 90 %**, l'idiome de `provider_card.dart` : glyphe `textPrimary` (ou
   `favorite` quand favori), disque visuel 40 dp, **cible 48 dp**, info-bulles
   « Retour » / « Ajouter aux favoris » / « Retirer des favoris ».
4. **Le logo** — 64 dp, **anneau blanc de 2 dp**, ombre `elevation3`, en bas à
   gauche de la photo à `spacingM` (16) des bords : exactement le
   `bottom-m left-m h-16 w-16 border-2` du site. **Absent si le salon n'a pas de
   logo**, comme sur le site — une pastille « magasin » générique sur une
   photo n'identifie rien. Décoratif pour le lecteur d'écran (le nom suit
   immédiatement), et non tapable (il l'est aujourd'hui pas plus).
5. **Sous la photo, sur la surface blanche** (`secondary`, la même bande que
   l'en-tête d'aujourd'hui) : le nom (+ badge vérifié), la ville, la note —
   **pleine largeur** (W − 2 × 24 = 312 dp à 360), **hauteur intrinsèque**.
   Le nom n'a plus de plafond de lignes : rien ne le borne, donc rien ne le
   tronque (un nom de salon est une identité, §13.3).

**Seul le bloc texte suit la taille du texte** ; la photo est du chrome
constant (224 dp à toutes les échelles).

**Défilement.** La barre reste épinglée. La photo défile avec le contenu
(ancrée en bas, sans parallaxe), reste **pleinement opaque jusqu'à mi-course**,
puis se fond linéairement dans la barre (`background`). **La barre d'état
passe des icônes claires aux sombres quand l'opacité de la photo descend sous
0,5** — un seul nombre (`_coverVisibility`) pilote le fondu ET la barre d'état,
ils ne peuvent pas se contredire. Repliée, la barre montre les deux pastilles
sur le fond `background` — elles restent lisibles.

**Tap sur la photo** → la visionneuse existante (`_FullScreenPhotoGallery`)
s'ouvre **sur la photo 1** ; on peut glisser vers les suivantes.

**« Photos »** — saute la première photo, déjà affichée en couverture (comme
`Gallery images={imageUrls.slice(1)}` sur le site). La vignette de la photo
`i` (vrai index dans `imageUrls`) ouvre la visionneuse **à `i`**, sur la liste
complète — donc la vignette de gauche ouvre « Photo du salon 2 sur N », et un
glissement à gauche ramène à la couverture. **Si la couverture est la seule
photo, la section disparaît** (le site rend `null` pour une galerie vide) :
« Aucune photo pour le moment. » y serait faux, et « Aucune autre photo » est
du bruit.

### 2.2 Branche B — le salon n'a aucune photo

**L'en-tête d'aujourd'hui, à l'identique** : fond blanc, logo 72 dp (ou la
pastille « magasin ») à côté du nom / ville / note, la mécanique A13
inchangée — empilement du logo au-dessus du nom au-delà de **1,6×** (1,45×
pour un salon vérifié), hauteur `textScaledBound(68 | 148, 92)`. « Photos »
garde « Aucune photo pour le moment. ».

### 2.3 Les deux branches

- **Le cœur est visible** : `textPrimary` non favori (était `secondary`, blanc
  sur blanc), `favorite` favori.
- Aperçu Pro : pas de cœur (inchangé), « Retour » sur pastille dans la
  branche A, bandeau « Aperçu — voici ce que verront vos clients. » inchangé.

### 2.4 États

| État | Rendu |
|---|---|
| Chargement de la page | `LoadingIndicator` (inchangé) |
| Chargement de la photo | le substitut de `TimedCachedImage` (surface + `BrandLoader`) **dans la bande de 224 dp** — la géométrie est fixe, rien ne saute à l'arrivée de l'image |
| **Photo en échec** | **Décision : la bande neutre, pas un retour à l'en-tête d'aujourd'hui.** `TimedCachedImage` rend déjà une bande `surface` + l'icône « image indisponible » ; le dégradé, les pastilles, le logo et le bloc texte restent en place, la bande reste tapable (la visionneuse retente). Revenir à l'en-tête sans photo exigerait un signal d'échec que le widget n'expose pas, et **déplacerait la page sous le pouce du lecteur** après coup — un saut de mise en page asynchrone est pire qu'une bande grise |
| Photo trop lente (12 s) | le voile « Réessayer » de `TimedCachedImage`, par-dessus la bande |
| Vide (aucune photo) | branche B |
| Salon introuvable / hors ligne | `SalonUnavailableView` (inchangé) |
| Non connecté | le cœur mène à la connexion avec `returnTo` (inchangé) |
| Hors ligne, photo déjà vue | le cache disque (`TimeoutCacheManager.images`) — la même URL que la carte de l'accueil |

### 2.5 Cas limites

- **Nom très long** (« Institut de Beauté Cocody Riviera ») : il passe à la
  ligne autant qu'il faut ; le bloc est intrinsèque, aucune borne à recalculer.
- **Salon vérifié à 200 %** : le badge coûte 28 dp au nom (8 + 20) ; boîte de
  284 dp à 360 contre 269,7 pour « Excellence » à 2× — franchissement à
  **2,11×**, au-delà du contrat (non vérifié : 312 dp → 2,31×). **Aucun
  empilement nécessaire dans la branche A.**
- **Photo claire / blanche** : le dégradé (§2.1 point 2).
- **Photo très large ou très haute** : `cover` recadre au centre, comme le site.
- **`imageUrls[0] == ''`** : traité comme « pas de couverture » (la vérité
  JavaScript du site : `provider.imageUrls?.[0]` vide → pas de Hero).
- **360 / 375 / 390 dp, 1× et 2×** : tenus par `layout_test.dart` (§8).

### 2.6 Textes (français)

| Où | Texte |
|---|---|
| Couverture (lecteur d'écran) | libellé « Photo du salon {nom} », indice « Agrandir la photo », rôle bouton |
| Vignette « Photos » (lecteur d'écran) | « Agrandir la photo {i} sur {N} » (vrai rang ; le site dit « Agrandir la photo {i} ») |
| Visionneuse | « Photo du salon {i} sur {N} » (inchangé) |
| Cœur | « Ajouter aux favoris » / « Retirer des favoris » (inchangé) |

« Photo du salon Salon Excellence » se lit mal pour un salon dont le nom
commence par « Salon » — le site a le même travers (`alt="Salon {nom}"`).
Accepté : le vocabulaire est celui de la visionneuse, et le nom reste exact.

### 2.7 Réutilisation

`TimedCachedImage` (substitut, échec, délai), `_FullScreenPhotoGallery`
(inchangée), l'idiome pastille de `provider_card.dart`, le voile des stories
(§19), `AppColors` / `AppTheme` / `AppTextStyles` — aucun nouveau composant
partagé (un seul appelant).

## 3. API & contract

Aucun. `GET /providers/{id}` (client) et `GET /me/provider` (Aperçu Pro)
portent déjà `imageUrls` (ordonné, `[0]` = couverture) et `logoUrl`.

## 4. Data model

Aucun.

## 5. Architecture & patterns

Tout dans `provider_detail_screen.dart`, à côté de `_SalonLogo` :

- `_SalonCover` — l'espace flexible de la branche A : lit
  `FlexibleSpaceBarSettings` (fourni par `SliverAppBar`), calcule
  `_coverVisibility` une fois, et en tire l'opacité **et** la
  `SystemUiOverlayStyle` (un `AnnotatedRegion` imbriqué l'emporte sur celui de
  l'`AppBar` — `AnnotatedRegionLayer` interroge ses enfants d'abord).
- `_CoverLogo` — le logo cerclé.
- `_SalonIdentity` — nom / ville / note, **extrait** de l'en-tête d'aujourd'hui
  et partagé par les deux branches (la branche B le rend à l'identique, avec
  `maxLines: 2` que sa borne calculée exige).
- Les pastilles : un `IconButtonTheme` autour du `SliverAppBar` de la branche A
  — l'`AppBar` le relit pour son `BackButton` automatique (`app_bar.dart`,
  `iconButtonTheme.style?.copyWith(...)` garde le `backgroundColor`), donc la
  logique « faut-il un retour ? » (`impliesAppBarDismissal`) reste celle du
  framework au lieu d'être recopiée.

**Les dimensions ne sont pas des jetons, et c'est la règle du système**, pas une
exception : SYSTEM.md §5 « What §5 does not govern » — *« There is no sizing
scale… A layout dimension is a named constant at the call site »*
(`ProviderCard._imageHeight = 180`). La consigne de la tranche disait « ajouter
un jeton à `AppTheme` s'il n'en existe pas » ; vérifié : **toute nouvelle
`static const double` d'`AppTheme` rougit le miroir web**
(`web/scripts/dart-tokens.mjs`, `unclaimedDoubles` doit être vide) et
exigerait un jeton web — or la tranche ne touche pas au web, et le site a déjà
sa valeur (`h-56`). D'où trois constantes nommées au point d'usage,
documentées : `_coverHeight = 224`, `_coverLogoSize = 64`, `_coverLogoRing = 2` ;
SYSTEM.md §5 cite la couverture parmi ses exemples.

## 6. Security & authz

Aucune surface nouvelle. Les URL viennent du serveur (déjà validées à
l'écriture de la galerie / du logo), passent par le même `TimeoutCacheManager`
que partout ailleurs ; rien n'est journalisé. L'Aperçu Pro continue de lire
`/me/provider` et **jamais** la route publique (`salon_preview_test.dart` le
tient).

## 7. Performance

- Une image décodée en plus à l'ouverture — **la même URL** que la carte de
  l'accueil / de la liste, donc presque toujours un succès de cache disque ; la
  bande « Photos » en charge une de moins.
- Géométrie fixe pendant le chargement : aucun saut (CLS) quand la photo arrive.
- `TimedCachedImage` n'expose pas `memCacheWidth` : la couverture est décodée à
  sa taille d'origine, comme chaque photo de l'app aujourd'hui. Noté en §11.

## 8. Testing plan

| Fichier | Ce qu'il tient |
|---|---|
| `test/widget/salon_cover_test.dart` (nouveau) | branche A : la couverture est `imageUrls[0]`, libellée, tapable → visionneuse sur « Photo du salon 1 sur 2 » ; logo cerclé présent quand `logoUrl`, absent sinon ; « Retour » et cœur sur pastilles ; **cœur non favori `textPrimary`** dans les deux branches ; barre d'état **claire** couverture visible, **sombre** une fois repliée (lue là où le framework la lit, `layer.find`) ; une seule photo → pas de section « Photos » ; branche B : pas de couverture, en-tête d'aujourd'hui |
| `test/widget/photo_lightbox_test.dart` | la couverture ouvre la photo 1 ; la **première vignette** ouvre désormais la photo **2** (vrai index) ; `contain`, libellé, barre d'état claire (inchangés) |
| `test/widget/salon_preview_test.dart` | l'Aperçu rend la couverture **depuis la charge utile `/me/provider`** (sans toucher la route publique) ; une charge sans photo rend la branche B |
| `test/a11y/salon_header_test.dart` | les répliques géométriques A13 (branche B) restent ; **en plus**, l'écran réel (Aperçu, salon vérifié) : branche B **empile** dans la bande 1,5/1,6/1,7×, branche A tient le nom entier jusqu'à 2× sans logo à côté |
| `test/a11y/layout_test.dart` | « the salon page fits » (branche A) et un nouveau sujet « without photos » (branche B), 3 largeurs × 2 échelles chacun |
| goldens | `consumer_provider_detail` (390 × 1×, **avec un logo** pour photographier l'anneau), `consumer_provider_detail_w360_x2` (360 × 2×, sans logo), **nouveau** `consumer_provider_detail_no_photos` (390 × 1×, branche B) — rendus sous Linux, chaque PNG regardé |

Chaque nouvelle garde est **regardée rouge** sur le code commité (mutation →
test rouge → restauration), consignée dans le message du commit final.

## 9. Rollout & scope discipline

Pas de drapeau : c'est un rendu, sans donnée nouvelle. Arrive avec le prochain
build des deux apps. Le site ne change pas. V1.

## 10. Definition of done

- [x] `flutter analyze` = 0 · `dart format` propre · tests verts
- [x] goldens Linux régénérés et regardés
- [x] spec liée depuis le code (`provider_detail_screen.dart`), l'index, l'entrée de roadmap
- [x] docs corrigées : `gallery-set-cover.md` §1, `parity-audit-modules-2026-07.md` ligne 2.9, `mobile-a13-copy-and-breaks.md` §3, SYSTEM.md §5 + §21 (ligne 62 + ligne 91)
- [ ] essai sur appareil (iOS + Android) — barre d'état au-dessus d'une photo claire, propriétaire

## 11. Open questions

- **Tablette / `medium`** : le site passe à 320 px dès 640 px. L'app n'a pas de
  mise en page `medium` (SYSTEM §10/§22) ; 224 dp partout pour l'instant.
- **Titre dans la barre repliée** : refusé par §13.3 (un titre n'interpole pas
  de donnée) ; si on le veut, c'est une décision de système, pas de cette page.
- **`memCacheWidth`** pour la couverture sur Android bas de gamme : à mesurer
  avec le reste des images (`TimedCachedImage` n'a pas ce paramètre).
- **Signalé, non corrigé** : `ProviderCard` (grille) remplace une liste de
  photos vide par **`https://via.placeholder.com/400x300`**
  (`provider_card.dart`, `_buildGridCard`) — une URL tierce, appelée depuis
  l'appareil de l'utilisateur, pour un salon sans photo. À remplacer par la
  bande neutre de `TimedCachedImage` dans une tranche à part.
