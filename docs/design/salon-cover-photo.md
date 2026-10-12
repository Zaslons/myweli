# La photo de couverture de la page salon (mobile — client + Aperçu Pro)

| | |
|---|---|
| **Status** | **Built** (code, tests, docs, goldens Linux regardés) — reste l'essai sur appareil (§10) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-12 |
| **Module** | `online-booking` (la page salon de la marketplace) — [MODULES.md](../MODULES.md) |
| **PRD ref / phase** | FR-DISC-006 (« Provider profile: hero gallery… ») · V1 |
| **ROADMAP entry** | [2026-10-11-salon-cover-photo.md](../roadmap/entries/2026-10-11-salon-cover-photo.md) |
| **Governs** | `mobile/lib/screens/providers/provider_detail_screen.dart` — l'en-tête, la bande « Photos », le cœur. Un seul écran pour `/provider/:id` (client) **et** `/pro/apercu` (`SalonPreviewScreen` → `GET /me/provider` → `ProviderDetailScreen(preview: true)`) ; et `mobile/lib/widgets/common/default_status_bar_style.dart`, posé dans `main.dart` et `main_pro.dart` (la barre d'état au retour, §2.1) |
| **Contract** | **Aucun changement.** `imageUrls[0]` est déjà la couverture (`docs/api/openapi.yaml`, `imageUrls` : « `imageUrls[0]` is the listing cover ») ; `logoUrl` : [salon-logo.md](salon-logo.md) |
| **Skills checked** | myweli-dev-guardrails |

## 1. Goal & scope

Le propriétaire, dans l'« Aperçu » Pro : *« je ne vois pas la photo de fond
comme sur le site »*. Vérifié dans le code avant d'écrire une ligne :

| | site (`web/components/provider/Hero.tsx`) | app (avant) |
|---|---|---|
| couverture | `imageUrls[0]` pleine largeur, `object-cover`, 224 px téléphone / 320 px dès `sm`, `priority` | **aucune** — `FlexibleSpaceBar.background` = `Container(color: AppColors.secondary)` ; l'en-tête ne lisait jamais `imageUrls` |
| logo | cercle 64 px cerclé de blanc, en bas à gauche **de la photo** ; absent sans logo | 72 dp à côté du nom ; pastille « magasin » sinon |
| galerie | `imageUrls.slice(1)` — la couverture n'est pas répétée ; absente si vide | toutes les photos ; section toujours là |

Le même écran sert le client et l'Aperçu : **un correctif couvre les deux**.
Constats en passant : **le cœur « favori » était invisible** (non favori, peint
en `secondary` #FFFFFF sur l'en-tête blanc) ; `gallery-set-cover.md` §1 et la
ligne 2.9 de `parity-audit-modules-2026-07.md` affirmaient que la couverture
s'affichait déjà sur le détail mobile — faux.

**Hors périmètre** : web / backend / contrat (le site fait déjà juste) ; un
titre dans la barre repliée (§13.3 : un titre n'interpole pas de donnée) ;
parallaxe ; une hauteur tablette (l'app n'a pas de mise en page `medium`,
SYSTEM §10/§22) ; le repli `via.placeholder.com` de `ProviderCard` (§11).

## 2. UX & flows

**Points d'entrée** (inchangés) : accueil, liste, carte, favoris, `/provider/:id`, `/pro/apercu`.

### 2.1 Branche A — au moins une photo (`imageUrls[0]` non vide)

De haut en bas :

1. **La couverture** — `imageUrls[0]`, pleine largeur, **224 dp sous la barre
   d'état** (le `h-56` du site), bord à bord : elle passe sous la barre d'état
   et sous la barre d'outils. `BoxFit.cover` (l'`object-cover` du site).
2. **Un dégradé en haut** — noir 60 % → transparent, sur la barre d'état + la
   barre d'outils. Le voile des stories (§19, `story_viewer.dart`, 0x99) : il
   garde lisibles les icônes **claires** de la barre d'état sur un mur blanc.
3. **La barre d'outils** — « Retour » et le cœur sur des **pastilles blanches à
   90 %** (l'idiome de `provider_card.dart`) : glyphe `textPrimary` (`favorite`
   une fois favori), disque 40 dp, **cible 48 dp**, info-bulles inchangées.
4. **Le logo** — 64 dp, **anneau blanc de 2 dp**, ombre `elevation3`, en bas à
   gauche de la photo à `spacingM` (16) : le `bottom-m left-m h-16 w-16
   border-2` du site. **Absent sans logo**, comme sur le site — une pastille
   générique sur une photo n'identifie rien. Décoratif pour le lecteur d'écran
   (le nom suit) ; il fait partie de la couverture, donc un tap dessus ouvre la
   visionneuse comme partout ailleurs sur la photo.
5. **Sous la photo, sur la surface blanche** (`secondary`) : nom (+ badge
   vérifié), ville, note — **pleine largeur** (312 dp à 360), **hauteur
   intrinsèque**, sans plafond de lignes : rien ne borne le nom, donc rien ne
   le tronque (§13.3).

**Seul le texte suit la taille du texte** ; la photo est du chrome constant.

**Défilement.** La barre reste épinglée. La photo défile avec le contenu
(ancrée en bas, sans parallaxe), reste **opaque jusqu'à mi-course**, puis se
fond linéairement dans la barre (`background`). **La barre d'état passe des
icônes claires aux sombres quand l'opacité descend sous 0,5** — un seul nombre
(`_coverVisibility`) pilote le fondu ET la barre d'état. Entièrement fondue,
la couverture ignore les taps (pas de photo invisible ouverte par un tap sur
la barre repliée). Repliée, les deux pastilles restent sur `background`.

**Au retour, la barre d'état redevient sombre.** Trouvé en revue : l'accueil
n'a pas d'`AppBar`, donc aucune `AnnotatedRegion` sous la barre d'état ;
Flutter n'envoie alors rien (`RenderView._updateSystemChrome` s'arrête), la
plateforme garde le dernier style reçu, et les icônes **claires** de la
couverture restaient sur l'accueil presque blanc (même cause après les
stories). `DefaultStatusBarStyle` — le style sombre des `AppBar` — enveloppe
le `builder` des deux apps ; la région la plus profonde l'emporte toujours,
donc la couverture garde ses icônes claires tant qu'elle est à l'écran.

**Tap sur la photo** → la visionneuse existante (`_FullScreenPhotoGallery`),
**sur la photo 1**, sur la liste complète.

**« Photos »** saute la couverture (le `slice(1)` du site). La vignette de la
photo `i` (vrai index dans `imageUrls`) ouvre la visionneuse **à `i`** : la
première vignette ouvre « Photo du salon 2 sur N », un glissement ramène à la
couverture. **Couverture seule → la section disparaît** (le site rend `null`) :
« Aucune photo pour le moment. » y serait faux.

### 2.2 Branche B — aucune photo

**L'en-tête d'avant, à l'identique** : fond blanc, logo 72 dp (ou pastille
« magasin ») à côté du nom, la mécanique A13 inchangée — empilement au-delà de
**1,6×** (1,45× vérifié), hauteur `textScaledBound(68 | 148, 92)`, nom à 2
lignes. « Photos » garde « Aucune photo pour le moment. ».

### 2.3 Les deux branches

- **Le cœur est visible** : `textPrimary` non favori (était `secondary`),
  `favorite` favori.
- Aperçu Pro : pas de cœur (inchangé), « Retour » sur pastille en branche A,
  bandeau « Aperçu — voici ce que verront vos clients. » inchangé.

### 2.4 États

| État | Rendu |
|---|---|
| Chargement de la page | `LoadingIndicator` (inchangé) |
| Chargement de la photo | le substitut de `TimedCachedImage` (surface + `BrandLoader`) **dans la bande** — géométrie fixe, rien ne saute |
| **Photo en échec** | **Décision : la bande neutre, pas un retour à la branche B.** `TimedCachedImage` peint sa surface « image indisponible » dans les mêmes 224 dp ; dégradé, pastilles, logo et texte restent en place, la bande reste tapable. Revenir à la branche B exigerait un signal d'échec que le widget n'expose pas, et **déplacerait la page sous le pouce** après coup |
| Photo trop lente (12 s) | le voile « Réessayer » de `TimedCachedImage`, sur la bande |
| Aucune photo | branche B |
| Salon introuvable / hors ligne | `SalonUnavailableView` (inchangé) |
| Non connecté | le cœur mène à la connexion avec `returnTo` (inchangé) |
| Photo déjà vue, hors ligne | le cache disque (`TimeoutCacheManager.images`) — même URL que la carte de l'accueil |

### 2.5 Cas limites

- **Salon vérifié à 200 %** : le badge coûte 28 dp — 284 dp à 360 pour
  « Excellence » (134,85 dp à 1×) : franchissement à **2,11×** (2,31× non
  vérifié), au-delà du contrat. **Aucun empilement en branche A**, tenu à 2× sur
  les trois largeurs par `salon_header_test.dart`.
- **Photo claire** : le dégradé. **Photo très large / haute** : `cover` recadre
  au centre, comme le site.
- **`imageUrls[0] == ''`** : « pas de couverture » (la vérité JavaScript du
  site) ; la bande « Photos » montre alors toute la liste.

### 2.6 Textes (français)

| Où | Texte |
|---|---|
| Couverture (lecteur d'écran) | « Photo du salon {nom} », indice « Agrandir la photo », rôle bouton |
| Vignette « Photos » (lecteur d'écran) | « Agrandir la photo {i} sur {N} » (vrai rang ; elle n'avait aucun libellé) |
| Visionneuse | « Photo du salon {i} sur {N} » (inchangé) |
| Cœur | « Ajouter aux favoris » / « Retirer des favoris » (inchangé) |

« Photo du salon Salon Excellence » bégaie — le site aussi (`alt="Salon
{nom}"`). Accepté : vocabulaire de la visionneuse, nom exact.

## 3. API & contract — 4. Data model

Aucun. `GET /providers/{id}` (client) et `GET /me/provider` (Aperçu) portent
déjà `imageUrls` (ordonné, `[0]` = couverture) et `logoUrl`.

## 5. Architecture & patterns

Tout dans `provider_detail_screen.dart` :

- `_coverAppBar` / `_noPhotoAppBar` — les deux en-têtes, choisis par
  `_coverUrl(p)` ; la branche A ajoute un `SliverToBoxAdapter` pour le nom.
- `_SalonCover` — l'espace flexible de la branche A : lit
  `FlexibleSpaceBarSettings`, calcule `_coverVisibility` une fois, en tire
  l'opacité **et** la `SystemUiOverlayStyle` — un `AnnotatedRegion` imbriqué
  dans celui de l'`AppBar` l'emporte (`AnnotatedRegionLayer.findAnnotations`
  interroge ses enfants d'abord).
- `_CoverLogo` — le logo cerclé. `_SalonIdentity` — nom / ville / note,
  extrait de l'ancien en-tête et partagé (branche B : `nameMaxLines: 2`, que
  sa borne calculée exige ; branche A : aucun plafond).
- `_favoriteAction` — le cœur, partagé. `_galleryIndices` — les vrais index
  de la bande « Photos ».
- `DefaultStatusBarStyle` (`widgets/common/`, hors de l'écran) — le style par
  défaut sous chaque route, posé dans le `builder` de `main.dart` et de
  `main_pro.dart` (pas de l'admin, une console de bureau). `MaterialApp`
  n'envoie le style sombre qu'en construisant son thème clair — au démarrage,
  jamais à un changement de route.
- Les pastilles : un `IconButtonTheme` autour du `SliverAppBar` de la
  branche A. L'`AppBar` le relit pour son `BackButton` implicite et ses
  actions (`app_bar.dart`, `style?.copyWith(...)` garde le
  `backgroundColor`), donc « faut-il un retour ? »
  (`impliesAppBarDismissal`) reste la logique du framework.

**Les dimensions ne sont pas des jetons, par la règle du système** (SYSTEM.md
§5 « What §5 does not govern » : pas d'échelle de tailles, une constante
nommée au point d'usage, cf. `ProviderCard._imageHeight`). Vérifié aussi : une
nouvelle `static const double` d'`AppTheme` rougit le miroir web
(`web/scripts/dart-tokens.mjs`, `unclaimedDoubles`) pour une valeur que le site
porte déjà (`h-56`). D'où `_coverHeight = 224`, `_coverLogoSize = 64`,
`_coverLogoRing = 2`. Le voile (`Colors.black` 60 % → `Colors.transparent`)
est l'exception §19 « alpha-black … for scrims and overlays only ».

## 6. Security & authz

Aucune surface nouvelle. Les URL viennent du serveur (validées à l'écriture de
la galerie / du logo) et passent par le même `TimeoutCacheManager` ; rien n'est
journalisé. L'Aperçu lit toujours `/me/provider`, **jamais** la route publique
(`salon_preview_test.dart` le tient, y compris pour la couverture).

## 7. Performance

Une image de plus — **la même URL** que la carte de l'accueil (cache disque) ;
« Photos » en charge une de moins. Géométrie fixe : aucun saut. Pas de
`memCacheWidth` dans `TimedCachedImage` : décodage à la taille d'origine (§11).

## 8. Testing plan

| Fichier | Ce qu'il tient |
|---|---|
| `test/widget/salon_cover_test.dart` (nouveau) | couverture = `imageUrls[0]`, rect `0,0 → W × (barre d'état + 224)` ; logo à 16 + 2 dp du coin, 60 dp dans un anneau de 2 dp ; nom sous la photo ; sémantique (libellé, indice, bouton, tap) → visionneuse « 1 sur 2 » ; sans logo → aucun disque ; couverture seule → pas de « Photos » ; branche B ; barre d'état **claire** puis **sombre** une fois repliée (`SystemChrome.latestStyle`, ce que le framework a réellement envoyé) ; le voile (couleurs, rect barre d'état + barre d'outils) ; repliée, un tap sur la barre n'ouvre rien (témoin : dépliée, le même point ouvre) ; photo en échec → la bande garde sa hauteur ; pastilles 90 % ≥ 48 dp ; cœur `textPrimary` dans les deux branches, sans pastille en B |
| `test/widget/photo_lightbox_test.dart` | la couverture ouvre la photo 1 (`contain`, libellé, barre claire) ; la bande ne répète pas la couverture et sa **première vignette ouvre la photo 2** |
| `test/widget/salon_preview_test.dart` | l'Aperçu rend la couverture **depuis la charge `/me/provider`** (service public interdit) ; une charge sans photo rend la branche B |
| `test/a11y/salon_header_test.dart` | les répliques A13 (branche B) restent ; l'écran réel (Aperçu, salon vérifié) : branche B **empile** et garde le nom entier à 1,5/1,6/1,7× sur 360/375/390 ; branche A garde le nom entier à 2× sur les trois largeurs, à la gouttière (rien à côté) |
| `test/a11y/layout_test.dart` | « the salon page fits » (branche A) + « the salon page without photos fits » (branche B), 3 largeurs × 2 échelles ; `expectAppBarTitleWhole` seulement en B (la barre de A ne porte aucun texte) |
| `test/widget/default_status_bar_style_test.dart` (nouveau) | accueil sans `AppBar` → page salon (couverture) → retour : **sans** le défaut, les icônes claires restent (témoin C : le défaut reproduit) ; **avec**, sombre → claire → **sombre** ; épingle de source, commentaires retirés : les deux racines téléphone l'installent |
| goldens | `consumer_provider_detail` (390 × 1×, branche A, sans logo — provider1 n'en a pas), `consumer_provider_detail_w360_x2` (360 × 2×), **nouveau** `consumer_provider_detail_no_photo` (390 × 1×, branche B, déconnecté). **Régénérés sur Linux** par le workflow `goldens.yml` (run 38185286424, commit `1badf5e0`) et regardés : la photo s'affiche, le cœur est lisible, la branche B est l'en-tête d'avant. Le défaut de barre d'état n'en change aucun : une `AnnotatedRegion` ne peint rien, et les goldens ne passent pas par le `builder` des racines |

Chaque garde est **regardée rouge** sur le code commité (mutation → test ciblé
rouge → `git checkout` → arbre propre) : **32 mutations, 36 exécutions** —
toutes rouges, sauf la déconnexion du golden sans photo, vue par l'image :

| Garde | Mutation → rouge |
|---|---|
| `salon_cover_test` | hauteur 224 → 200 (rect 224 ≠ 248) · couverture = `imageUrls.last` · anneau 2 → 4 (logo à 20 ≠ 18) · tap → photo 2 (« 1 sur 2 » absent) · indice retiré · pastille « magasin » sur une couverture sans logo · « Photos » gardé quand la couverture est seule · sans photo, `''` au lieu de `null` (rouge par le délai de `pumpAndSettle` — l'URL vide charge sans fin —, pas par une assertion) et sa jumelle : la barre de la branche B envoie des icônes claires (sombre attendu) · seuil 0,5 → 0 (claire une fois repliée) · voile 0,6 → 0,4 · voile réduit à la barre d'état (24 ≠ 80) · couverture fondue tapable (`Dialog` ouvert) · bande sans l'encart de la barre d'état (photo en échec : 224 ≠ 248) · pastille 90 % → 50 % · cible `shrinkWrap` (40 < 48) · cœur `secondary` |
| `photo_lightbox_test` | tap sur la couverture → photo 2 · vignette ouverte à sa position dans la bande (« 2 sur 2 » absent) · bande commencée à 0 (« Agrandir la photo 1 sur 2 » présent) |
| `salon_preview_test` | aucune couverture (le défaut du propriétaire) · couverture = `imageUrls.last` · l'Aperçu lit la route publique avant de rendre · « Aucune photo » retiré pour une charge sans photo |
| `salon_header_test` | branche B n'empile jamais (nom à 16 < logo à 68, ×3) · branche A : nom décalé de 88 (x = 112 ≠ 24, ×3) · branche A : rangée amputée de 88 à droite (`expectNoMidWordBreak` : 196,5 < 269,7, ×3) |
| `layout_test` | aucune couverture (témoin C, ×6) · nom plafonné à une ligne sous la couverture (témoin de `expectNoMidWordBreak` : toutes les occurrences en `maxLines: 1`, ×6) · borne de B sans la chrome empilée (débordement de 80 dp à 2×, ×3) |
| golden sans photo | « Aucune photo » retiré → rouge au témoin (ligne 206), avant la comparaison · **`logout` retiré : vu par l'image, pas par un rouge local** — un rendu macOS diffère toujours de la base Linux (3,59 % sans mutation, 16,46 % avec), et l'image mutée montre le cœur rouge et la carte de rendez-vous ; la porte reste la comparaison Linux de la CI |
| `default_status_bar_style_test` | le défaut ne pose rien (claire après le retour) · le défaut envoie clair · `main.dart` sans lui (épingle : `['lib/main.dart']`) · `main_pro.dart` sans lui |

## 9. Rollout & scope discipline

Pas de drapeau (un rendu, sans donnée nouvelle) ; prochain build des deux
apps ; le site ne change pas. V1.

## 10. Definition of done

- [x] `flutter analyze` = 0 · `dart format` propre · tests ciblés verts
- [x] mutations consignées (§8 : 32 mutations, 36 exécutions, sur le code commité)
- [ ] suite complète verte — la CI de la PR (pas rejouée localement depuis le défaut de barre d'état)
- [x] **goldens Linux régénérés et regardés** (`goldens.yml`, run 38185286424, commit `1badf5e0`)
- [x] la barre d'état au retour (§2.1) — `DefaultStatusBarStyle` aux deux racines, regardé rouge
- [x] spec indexée (`README.md`), liée depuis l'entrée de roadmap et depuis le code
- [x] docs corrigées : `gallery-set-cover.md` §1, `parity-audit-modules-2026-07.md` ligne 2.9, `mobile-a13-copy-and-breaks.md` §3, SYSTEM.md §5 (exemple) + §21 (ligne 62, ligne 91)
- [ ] essai sur appareil (iOS + Android) — barre d'état sur une photo claire, propriétaire

## 11. Open questions

- **Tablette** : le site passe à 320 px dès 640 px ; 224 dp tant que l'app n'a
  pas de mise en page `medium`. **Titre replié** : refusé par §13.3.
- **`memCacheWidth`** (Android bas de gamme) : à mesurer avec les autres images.
- **Signalé, non corrigé** : `ProviderCard` remplace une liste de photos vide
  par **`https://via.placeholder.com/400x300`** — deux fois (`_buildGridCard`
  et `_buildListCard`), et `app_constants.dart` en déclare deux autres : une
  URL tierce appelée depuis l'appareil pour un salon sans photo. À remplacer
  par la bande neutre de `TimedCachedImage` dans une tranche à part.
