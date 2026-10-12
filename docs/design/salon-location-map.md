# La carte de localisation de la page salon (mobile — client + Aperçu Pro)

| | |
|---|---|
| **Status** | **Built** (code, tests, docs) — reste : goldens Linux à régénérer et regarder (§9), essai sur appareil (§10) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-12 |
| **Module** | `online-booking` (la page salon de la marketplace) — [MODULES.md](../MODULES.md) |
| **PRD ref / phase** | FR-DISC-006 (page salon) · FR-FAV-001 (la carte) · V1 |
| **ROADMAP entry** | [2026-10-12-salon-location-map.md](../roadmap/entries/2026-10-12-salon-location-map.md) |
| **Governs** | `mobile/lib/widgets/providers/salon_location_preview.dart` (nouveau) · `mobile/lib/widgets/common/salon_map_marker.dart` (nouveau, extrait de `map_screen.dart`) · la carte « Contact » de `mobile/lib/screens/providers/provider_detail_screen.dart` · le focus `?providerId=` de `mobile/lib/screens/map/map_screen.dart` · `ProviderProvider.providerForMap` / `selectedProviderId` / `restoreSalon` · `CartoAttribution.sheet()` · le lien « Voir sur la carte » de `mobile/lib/widgets/booking/appointment_card.dart` · `CartoBasemapLayer.panBuffer` |
| **Guards** | `mobile/test/widget/salon_location_map_test.dart` (nouveau) · `mobile/test/unit/route_literals_test.dart` (nouveau) · `mobile/test/widget/carto_basemap_layer_test.dart` (la garde « chaque `FlutterMap(` passe par la couche ») |
| **Contract** | **Aucun changement** — `latitude` / `longitude` existent déjà sur `Provider` (`docs/api/openapi.yaml`) |
| **Skills checked** | myweli-dev-guardrails |

## 1. Goal & scope

Remontée du propriétaire : *« Voir sur la carte » sur la page salon mène à une
page morte.* Décision du propriétaire : **une carte sur la page salon, comme la
« Localisation » du site.**

**Vérifié dans le code avant d'écrire une ligne :**

| constat | où | effet |
|---|---|---|
| Le lien pousse `/favorites?providerId=…` | `provider_detail_screen.dart` (ligne d'adresse de « Contact ») et `appointment_card.dart` (« Voir sur la carte » de Mes rendez-vous) | La route a été renommée `/carte` le 2026-08-22 (#491). `/favorites` n'existe plus dans aucun routeur : go_router affiche « Page Not Found ». Deux surfaces mortes depuis sept semaines, et aucun test ne lisait la cible d'un `push`. |
| La page salon sert aussi l'« Aperçu » Pro | `/pro/apercu` → `SalonPreviewScreen` → `ProviderDetailScreen(preview: true)` | `ProRouter` n'enregistre **ni `/carte` ni `MapScreen`** : dans l'app Pro, même la bonne route serait morte. |
| L'app n'a **aucune carte** sur la page salon | — | La ligne 2.9 de [parity-audit-modules-2026-07.md](parity-audit-modules-2026-07.md) affirmait « carte (now same map identity) … present on both » — faux pour l'app : seul un lien existait. |
| `/carte?providerId=` ne tient pas sa promesse | `map_screen.dart` | (a) le salon n'est cherché que dans `ProviderProvider.providers` — **la page 1 (20 salons) filtrée par la commune choisie** : un salon d'une autre commune, ou au-delà du 20ᵉ, n'est jamais trouvé, la carte s'ouvre sur Abidjan sans feuille ; (b) juste après avoir centré le salon, `_initLocation()` **recentre la caméra sur l'utilisateur** dès que la position arrive — la feuille s'ouvre, mais en la fermant on regarde chez soi, pas le salon. |

**Dans le périmètre**
1. Un aperçu de carte en tête de la carte « Contact », au-dessus de la ligne
   d'adresse, seulement si le salon a des coordonnées (§2.1).
2. Les deux liens morts réparés ; rien dans l'app Pro ne pousse une route
   réservée au client (§2.2).
3. `/carte?providerId=` centré sur le salon, sa feuille ouverte, **quel que soit
   le filtre de commune ou la page** (§2.3).
4. Trois gardes (§8) : chaque `FlutterMap(` du code passe par la couche CARTO ;
   chaque littéral de route poussé existe dans le routeur de chaque app qui
   peut l'atteindre ; le comportement de la carte, app par app.

**Hors périmètre** — le site (sa « Localisation » fait déjà juste, §2.6) ; une
carte interactive dans la page (§2.1 : elle se battrait avec le défilement) ;
un itinéraire dans l'app ; le comportement « sans coordonnées » de la carte de
rendez-vous (`appointment_card.dart` garde son message « Localisation non
disponible pour ce salon » — seule sa cible change) ; les écrans dormants qui
poussent des routes non enregistrées (`phone_login_screen.dart` →
`/verify-otp`, §11).

**Architecture** — aucune nouvelle donnée, aucun service : `latitude` /
`longitude` sont déjà sur le modèle. Un widget de présentation
(`SalonLocationPreview`), un marqueur partagé (`SalonMapMarker`, extrait tel quel
de `MapScreen`), une méthode de lecture sur `ProviderProvider` (couche
provider → service, rien de sauté).

## 2. UX & flows

**Points d'entrée** de la page salon (inchangés) : accueil, liste, carte,
favoris, `/provider/:id` ; Pro : `/pro/apercu`.

### 2.1 L'aperçu de carte — dans la carte « Contact »

De haut en bas dans la carte « Contact » : le titre « Contact », **l'aperçu**,
`spacingSM`, puis la ligne d'adresse, le téléphone, WhatsApp — comme avant.

| | valeur | pourquoi |
|---|---|---|
| hauteur | **160 dp**, constante nommée `SalonLocationPreview.height` | SYSTEM.md §5 « What §5 does not govern » : *il n'y a pas d'échelle de tailles, et c'est une décision* — la hauteur d'une boîte de carte est une constante nommée au site d'appel (le précédent : `_coverHeight = 224`), pas un jeton `AppTheme`. **Aucun jeton ajouté.** 160 et non les 256 du site (`h-64`) : ici c'est un aperçu dont la vraie carte est à un tap, pas la carte elle-même. |
| largeur | toute la largeur du contenu de la carte (`SizedBox(width: double.infinity)`) | |
| coins | `AppTheme.radiusLarge` (12) | le `rounded-lg` du site ; plus petit que les 16 de la carte qui le contient (rayon intérieur < rayon extérieur) |
| fond | `AppColors.surfaceVariant` (`MapOptions.backgroundColor`) | le `bg-surfaceVariant` du site avant le chargement ; c'est la surface neutre sur laquelle les tuiles arrivent |
| caméra | centrée sur le salon, **zoom 15** | le `zoom: 15` de `SalonLocationMap.tsx` |
| marqueur | `SalonMapMarker(category:)` — **le marqueur de `MapScreen`**, extrait sans changer un pixel : disque blanc 48 dp, anneau 2 dp et icône de la catégorie (`categoryColor`) | le `SalonPin` du site *est* déjà le `_SalonMarker` de l'app (`salon-pin.tsx`) ; pas de cœur « favori » ici (la page a déjà le sien) |
| fond de carte | `CartoBasemapLayer(panBuffer: 0)` + `CartoAttribution.sheet()` | la couche clé unique ([map-basemap-key.md](map-basemap-key.md)) ; `panBuffer: 0` car une carte qui ne bouge pas n'a pas besoin de l'anneau de tuiles d'avance (§7) |
| crédits | un « i » (`Icons.info_outline`, `iconM`, cible 48 dp, info-bulle « Crédits de la carte ») en bas à droite ; un tap ouvre **une feuille** « Données cartographiques » : « © OpenStreetMap contributors », « © CARTO » — le texte de `CartoAttribution`, une seule source | **Pas la bulle de flutter_map.** Sa `RichAttributionWidget` ouvre ses crédits *dans* la carte : une colonne de texte dans une boîte de 160 dp. Mesuré par la revue (390 × 844, tap sur « i ») : débordement de **56 px à 1,3×, 80 à 1,5×, 220 à 2,0×** — une `FlutterError` en debug, les crédits obligatoires coupés en release. SYSTEM.md §13.3 : *une boîte qui contient du texte n'a pas de hauteur fixe* ; ici la boîte est fixe par conception, donc le texte en sort. La feuille a toute la largeur, défile, et s'enroule à tout facteur. « Carte » et la carte du profil Pro gardent la bulle (`CartoAttribution()`) — voir §11. |
| gestes | **aucun** : `InteractionOptions(flags: InteractiveFlag.none)` | ni glisser, ni zoomer, ni pincer. Sans drapeau de glisser, flutter_map n'enregistre aucun reconnaisseur de glisser : un glisser vertical sur la carte **fait défiler la page** (testé, §8). Le site a besoin des *cooperative gestures* parce que sa carte est interactive ; celle-ci ne l'est pas. |
| focus clavier | `ExcludeFocus` | le nœud `Focus` interne de flutter_map serait un arrêt clavier sans indicateur ; la ligne d'adresse, juste dessous, est l'équivalent clavier |

**États**

- **Avec coordonnées** — l'aperçu s'affiche dès que la page a son salon.
  *Chargement* : le fond `surfaceVariant`, le marqueur et le « i » des crédits
  sont là immédiatement ; les tuiles arrivent par-dessus (le fondu par défaut de
  flutter_map, une opacité, pas un mouvement — §9.1 n'est pas concerné).
  *Échec des tuiles* (hors ligne, clé refusée) : le fond neutre reste, le
  marqueur et le lien restent — rien ne casse, rien ne saute. *Filigrane CARTO* :
  dessiné s'il est servi, jamais mis en cache (§5.3 de map-basemap-key.md).
- **Sans coordonnées** — **pas d'aperçu** ; la ligne d'adresse affiche
  l'adresse seule, **n'est plus un bouton** et ne promet plus « Voir sur la
  carte » (avant : un lien qui ouvrait un message d'erreur). Pas d'icône
  « Itinéraire » (inchangé).
- **Page en chargement / salon introuvable** — l'état de la page, inchangé : la
  carte « Contact » n'existe pas encore.

### 2.2 Où mène un tap — app par app

| geste | client (`/provider/:id`) | Aperçu Pro (`/pro/apercu`) |
|---|---|---|
| tap sur l'aperçu | `push('/carte?providerId=<id>')` | le **sélecteur d'app de cartes** (`Helpers.launchNavigation`) — celui de l'icône « Itinéraire » |
| tap sur la ligne d'adresse | idem | idem |
| icône « Itinéraire » | sélecteur (inchangé) | sélecteur (inchangé) |
| tap sur « i » (crédits) | ouvre la feuille « Données cartographiques », ne navigue pas | idem |

L'Aperçu reste une copie fidèle de la page client (même texte « Voir sur la
carte ») ; seule la destination diffère, parce que l'app Pro n'a pas de carte.
`ProviderDetailScreen` choisit sur `widget.preview` — comme pour le cœur, la
carte « Vos rendez-vous ici » et le bouton « Réserver ».

`appointment_card.dart` (Mes rendez-vous, client seulement) : même cible,
`/carte?providerId=<id>`.

### 2.3 `/carte?providerId=` — le salon, sa feuille ouverte

1. `MapScreen` **lance** la liste (marqueurs) et les favoris (cœurs) comme
   avant — **sans les attendre** pour le salon.
2. Le salon à montrer est résolu **tout de suite**, par
   `ProviderProvider.providerForMap(id)` : d'abord la liste déjà en mémoire,
   puis le salon que la page salon tient déjà (`selectedProvider` — le cas « je
   viens de la page salon » : **aucun réseau**, donc hors ligne aussi), sinon
   **une** lecture publique `getProviderById`, **en parallèle** de la liste,
   jamais après elle. Elle ne touche **aucun état partagé** : la page salon,
   encore montée sous la carte, lit `selectedProvider` et `isLoading`.
   *Avant la revue* : le focus attendait `loadProviders()` puis
   `loadFavorites()` — sur un réseau lent, la caméra restait sur Abidjan et la
   feuille fermée aussi longtemps que la liste, même quand le salon était déjà
   en main (aucun délai d'expiration n'est appliqué aux requêtes :
   `AppConstants.apiTimeout` est déclaré, jamais lu). Le prix : quand ni la
   liste en mémoire ni la page salon ne tiennent le salon, une lecture de plus
   que si l'on avait attendu une liste qui l'aurait contenu.
3. Coordonnées connues → caméra sur le salon au zoom 14 (inchangé), feuille du
   salon ouverte (« Voir le salon », « Y aller »). S'il n'est pas dans la liste
   (autre commune, au-delà de la page 1), **son marqueur est ajouté** — sinon la
   feuille se fermerait sur une carte vide à cet endroit.
4. La localisation de l'utilisateur continue (point bleu, « Me localiser »),
   **mais ne déplace plus la caméra** quand un salon a été centré. Un tap sur
   « Me localiser » / « Activer » recentre, comme avant.
5. Salon introuvable ou sans coordonnées (une lecture en échec) → la carte
   s'ouvre normalement et un message d'erreur : « Ce salon n’a pas pu être
   affiché sur la carte. »

### 2.4 Accessibilité (SYSTEM.md §13)

- **Lecteur d'écran** : l'aperçu est **un seul bouton**, « Voir {nom du salon}
  sur la carte » — le libellé du `SalonPin` du site (`aria-label`) ;
  `excludeSemantics` : ni tuiles, ni marqueur, ni bouton d'attribution annoncés
  un par un. La ligne d'adresse reste son propre bouton (adresse + « Voir sur
  la carte ») : deux arrêts pour une même action, assumé — l'adresse est une
  information en soi, et elle existe sans carte.
- **Cibles** : l'aperçu fait 160 dp × la largeur ; la ligne d'adresse garde
  `minHeight: 48` ; l'icône « Itinéraire » est un `IconButton` (48) avec
  info-bulle.
- **Texte à 200 %** : la boîte de 160 dp ne contient **aucun texte**, même
  ouverte — ses crédits s'ouvrent dans une feuille (§2.1, « crédits ») ; la
  première version l'affirmait alors que la bulle d'attribution de flutter_map
  *est* du texte, et débordait dès 1,3× (la revue l'a mesuré ; le test « 200 % »
  n'ouvrait jamais la bulle). La ligne d'adresse s'enroule, sans `maxLines` ;
  « Itinéraire » reste à droite. Testé à 360 dp × 2,0, **le « i » ouvert** :
  aucune exception, les deux crédits entiers dans la feuille.
- **Mouvement réduit** : la caméra est fixe ; rien ne s'anime hormis le fondu
  d'opacité des tuiles.
- **Couleur seule** : non — l'icône de catégorie porte la catégorie, comme sur
  la carte.

### 2.5 Texte

| où | texte |
|---|---|
| libellé sémantique de l'aperçu | « Voir {nom} sur la carte » |
| sous l'adresse (avec coordonnées) | « Voir sur la carte » (inchangé) |
| `MapScreen`, salon non résolu | « Ce salon n’a pas pu être affiché sur la carte. » |
| info-bulle du « i » de l'aperçu | « Crédits de la carte » |
| titre de la feuille des crédits | « Données cartographiques » |
| crédits (texte légal, non traduit — celui de `CartoAttribution`) | « © OpenStreetMap contributors » · « © CARTO » |

### 2.6 Parité avec la « Localisation » du site

| | site (`MapEmbed.tsx` + `SalonLocationMap.tsx`) | app |
|---|---|---|
| place | section « Localisation » après le contenu | en tête de la carte « Contact » |
| carte | MapLibre + Positron (CARTO), interactive, *cooperative gestures*, boutons de zoom | raster CARTO `light_all` (le même Positron), **fixe** ; la vraie carte est à un tap |
| zoom / marqueur | 15 / `SalonPin` | 15 / `SalonMapMarker` (le même dessin) |
| hauteur | 256 px téléphone, 320 px dès `md` | 160 dp |
| sans coordonnées | adresse seule | adresse seule |
| itinéraire | lien « Itinéraire » (Google Maps) | icône « Itinéraire » → sélecteur d'apps |
| chargement | `IntersectionObserver` : la carte ne se charge qu'en approchant | la page est une seule colonne : l'aperçu se construit avec elle (§7) |

Même identité de carte, deux usages : sur le site la carte **est** la
destination ; dans l'app elle est la porte vers « Carte ».

### 2.7 Une page salon montre son salon — jamais un autre

**Le défaut (revue, vérifié par une sonde)** : salon A → tap sur la carte →
`/carte` → marqueur de B → « Voir le salon » → `/provider/B` → retour →
retour : **la page de A affiche B** — sa carte, son adresse, son bouton
« Réserver » (qui réserverait chez B), ses rendez-vous. La cause est plus
ancienne que cette branche : `ProviderProvider.selectedProvider` est **une
seule case** partagée par toutes les pages salon de la pile, la page la lisait
sans la comparer à `widget.providerId`, et la page de B l'écrase en chargeant.
Sur `main`, ce chemin était inatteignable — le lien de la page salon vers la
carte était mort ; le réparer l'a ouvert.

**La règle** : une page salon (`!preview`) n'affiche que **son** salon.

| la case contient… | la page affiche |
|---|---|
| son salon (`selectedProvider.id == providerId`) | ce salon — et en garde **sa copie** |
| le résultat de **sa** lecture, en échec (`selectedProviderId == providerId`, `selectedProvider == null`) | l'état « salon indisponible » (§12), inchangé |
| sa lecture **en cours** (`selectedProviderId == providerId`, la case tient encore l'ancien salon) | le chargeur |
| le salon d'**une autre** page (ou son échec) | **sa copie** ; sans copie, le chargeur |

`selectedProviderId` (nouveau, sur `ProviderProvider`) dit **à qui** est la
case : l'id de la dernière `loadProviderById`, posé **avant** la lecture, ou
de `showPreloaded` / `restoreSalon`. `selectedProvider` seul ne peut pas le
dire : pendant une lecture il tient encore le salon précédent, et après un
échec il est `null` pour tout le monde.

**Reprendre la case** : quand la page redevient **la route du dessus**
(`ModalRoute.isCurrentOf`) et que la case est à une autre page, elle la
reprend après l'image en cours — `restoreSalon(copie)` (aucun réseau, aucun
chargeur : la page affichait déjà cette copie) ; sans copie,
`loadProviderById(providerId)`. **Jamais** tant qu'une autre page est
au-dessus : deux pages qui se reprendraient la case l'une à l'autre en
boucle. Rien à reprendre avant que la lecture initiale soit partie (pas de
double lecture à l'image 1).

Le corps, la barre « Réserver / Appeler » et la devise des prix lisent tous
le salon par ce seul chemin. **Conséquence voulue** : la page d'un salon
ouverte après un autre montrait l'**autre** salon pendant toute sa lecture
(la case n'est vidée qu'à la réponse) ; elle montre désormais le chargeur.
L'Aperçu Pro n'est pas concerné (une seule page, amorcée, sans lecture).
`booking_hub_screen.dart` et `booking_confirmation_screen.dart` lisent la
même case de la même façon ; aucun lien de la carte n'y mène — hors périmètre,
§11.

## 3. API & contract — aucun changement

## 4. Data model — aucun

## 5. Architecture & patterns

| fichier | rôle |
|---|---|
| `widgets/providers/salon_location_preview.dart` | `SalonLocationPreview({salonName, category, latitude, longitude, onOpen})` — la boîte de §2.1, sans état, sans navigation : l'appelant décide où mène `onOpen` |
| `widgets/common/salon_map_marker.dart` | `SalonMapMarker({category, isFavorite})` + `salonCategoryIcon` — **déplacés** de `map_screen.dart` (`_SalonMarker`, `_categoryIcon`), à l'identique |
| `widgets/common/carto_basemap_layer.dart` | `CartoBasemapLayer.panBuffer` (défaut 1 = celui de flutter_map, donc les deux cartes existantes ne changent pas) |
| `screens/providers/provider_detail_screen.dart` | `_openOnMap(p)` : `preview` → sélecteur, sinon `/carte?providerId=` ; la carte « Contact » ; `_salonOf` / `_reclaimIfUncovered` — la page ne montre que son salon (§2.7) |
| `screens/map/map_screen.dart` | focus via `providerForMap` **avant** la liste et les favoris (lancés, pas attendus), marqueur du salon focalisé s'il manque, la localisation qui ne vole plus la caméra |
| `providers/provider_provider.dart` | `providerForMap(id)` (§2.3) ; `selectedProviderId` et `restoreSalon(salon)` (§2.7) |
| `widgets/common/carto_basemap_layer.dart` | `CartoAttribution.sheet()` — les crédits dans une feuille, pour une boîte de carte fixe (§2.1) ; `cartoCredits`, le texte légal, une seule fois |
| `widgets/booking/appointment_card.dart` | la cible `/carte?providerId=` |

## 6. Security & authz

Rien de nouveau : coordonnées et identifiant déjà publics (`/provider/:id`,
`GET /providers/{id}`). L'identifiant passe dans la requête comme pour
`/booking?providerId=`. Les tuiles partent avec les mêmes en-têtes que les deux
autres cartes (clé, restriction plateforme). `providerForMap` n'utilise que la
lecture publique, déjà appelée par la page salon.

## 7. Performance

- **Tuiles** : 160 × ~326 dp au zoom 15, tuiles `@2x` de 256 dp logiques →
  2 à 6 tuiles par page salon ; `panBuffer: 0` évite l'anneau d'avance (≈ 4×
  plus sinon). Mises en cache par le cache intégré de flutter_map (sans le
  filigrane).
- **Quota** : le palier gratuit CARTO (1 M de requêtes / mois) est partagé par
  toutes les clés ([map-basemap-key.md](map-basemap-key.md) §7) ; chaque page
  salon de l'app en consomme désormais quelques-unes. À surveiller avec le
  reste.
- **Construction** : la page est une colonne unique, l'aperçu se construit même
  hors écran (comme toutes les sections). Un `FlutterMap` sans geste, un
  marqueur : négligeable devant les photos de la page.

## 8. Testing plan

`test/widget/salon_location_map_test.dart` :
- avec coordonnées : l'aperçu est dans la carte « Contact », au-dessus de
  l'adresse, 160 dp de haut, caméra sur le salon au zoom 15, marqueur de la
  bonne catégorie, la couche avec `panBuffer: 0`, l'attribution ;
- sans coordonnées : pas d'aperçu, pas de « Voir sur la carte », la ligne
  d'adresse ne navigue pas ;
- client : tap sur l'aperçu → `/carte?providerId=provider1` ; tap sur l'adresse
  → idem ;
- Aperçu Pro : tap → sélecteur « Ouvrir avec », **l'emplacement du routeur ne
  bouge pas** (un routeur sans `/carte`, comme `ProRouter`) ;
- sémantique : un bouton « Voir Salon Excellence sur la carte », avec action ;
- un glisser vertical sur l'aperçu fait défiler la page et ne navigue pas ;
- 200 % de texte à 360 dp : aucun débordement, l'aperçu garde 160 dp, la ligne
  d'adresse ≥ 48 dp et « Itinéraire » visible ;
- `MapScreen(focusProviderId:)` : un salon absent de la liste → résolu, centré,
  sa feuille ouverte, son marqueur ajouté ; la position de l'utilisateur
  arrive → la caméra reste sur le salon ; un salon introuvable → le message ;
- `appointment_card` : « Voir sur la carte » → `/carte?providerId=`.

`test/unit/route_literals_test.dart` — **le garde qui aurait vu `/favorites`** :
chaque littéral de chemin d'un `push` / `go` / `pushReplacement` / `replace`
(et le nom d'un `*Named`) du code de `lib/`, commentaires retirés — y compris
les branches d'un ternaire et les `returnTo` imbriqués — doit exister dans le
routeur **de chaque app dont le point d'entrée importe le fichier**
(`main.dart` → `AppRouter`, `main_pro.dart` → `ProRouter`, `main_admin.dart` →
`createAdminRouter`). Les routes sont lues sur les **vrais** routeurs, pas
re-parsées. Les exceptions sont une table : un écran partagé que l'app Pro
n'atteint qu'en Aperçu (`ProviderDetailScreen(preview: true)`), où chaque
navigation client est derrière `widget.preview`, et l'import de la constante
`SplashScreen.animationWidth` — chaque entrée porte sa raison, et une entrée
qui ne correspond plus à rien fait échouer le test. Contrôles positifs : le
scanner sur des sources synthétiques (`/favorites`, un ternaire, un `returnTo`
imbriqué, un `goNamed` inconnu), et des comptes minimaux par app.

`test/widget/carto_basemap_layer_test.dart` — la liste fixe des deux écrans
devient : **chaque fichier de code contenant `FlutterMap(` utilise
`CartoBasemapLayer(` et `CartoAttribution()`**, avec un compte exact (3) comme
contrôle.

**Mutations vues rouges** (sur le code commité, chacune restaurée par
`git checkout --` puis l'arbre vérifié propre) — 24 :

| # | mutation | garde |
|---|---|---|
| M1 | la page salon pousse de nouveau `/favorites` | `route_literals_test` |
| M2 | Mes rendez-vous pousse de nouveau `/favorites` | `route_literals_test` |
| M3 | idem | `salon_location_map_test` « Mes rendez-vous » |
| M4 | le tableau de bord Pro pousse `/journal` (aucune app ne l'a) | `route_literals_test` |
| M5 | la route imbriquée `/profile/data` disparaît du routeur client | `route_literals_test` |
| M6 | l'aperçu perd `CartoAttribution()` | `carto_basemap_layer_test` |
| M7 | l'aperçu perd `CartoBasemapLayer` | `carto_basemap_layer_test` |
| M8 | `panBuffer` n'atteint plus le `TileLayer` | `carto_basemap_layer_test` |
| M9 | l'aperçu charge l'anneau de tuiles (`panBuffer` par défaut) | « atop » |
| M10 | l'aperçu prend les gestes (`InteractiveFlag.all`) | « vertical drag » |
| M11 | `excludeSemantics: false` — **a d'abord survécu** : le test cherchait « Attributions » comme libellé, c'est une info-bulle ; corrigé (recherche par info-bulle, contrôle positif « Itinéraire »), puis rouge | « screen reader » |
| M12 | le libellé perd le nom du salon | « screen reader » |
| M13 | plus de branche `preview` : l'Aperçu pousse `/carte` | « Aperçu » |
| M14 | l'adresse reste un lien sans coordonnées | « no coordinates » |
| M15 | `maxLines: 1` sur l'adresse | « 200% » |
| M16 | zoom 14 | « atop » |
| M17 | hauteur 120 | « atop » |
| M18 | la position recentre de nouveau la caméra | « outside the loaded list » |
| M19 | pas de marqueur pour le salon focalisé | « outside the loaded list » |
| M20 | le focus ne lit que la liste (l'ancien comportement) | « outside the loaded list » |
| M21 | `providerForMap` ignore le salon de la page salon | « writes nothing » |
| M22 | `providerForMap` écrit `selectedProvider` | « writes nothing » |
| M23 | un salon introuvable échoue en silence | « cannot be found » |
| M24 | l'aperçu perd son fond `surfaceVariant` | « atop » |

## 9. Rollout & scope discipline

Pas de drapeau : une correction de lien mort et une section de page. V1.
**Goldens qui changent** (régénérés sur Linux par `goldens.yml`, jamais sur un
Mac) : `consumer_provider_detail_w360_x2` (cadre de 4 200 dp),
`consumer_provider_detail` et `consumer_provider_detail_no_photo` (cadres de
1 200 dp : le titre « Contact » mesuré à ~770 dp, l'aperçu à 804–964 dp, avec
la police de test — la marge est large). Sous `flutter test`, `PackageInfo` ne
répond jamais dans l'horloge simulée : la couche ne dessine aucune tuile, et
l'image montre le fond `surfaceVariant`, le marqueur et l'attribution.

## 10. Definition of done

- [x] `flutter analyze` = 0 · `dart format` propre · tests ciblés verts
      — les trois fichiers ci-dessus (13 + 11 + 18 cas), et les dix qui
      couvrent la page salon ou la carte : `salon_preview`, `salon_cover`,
      `salon_landing_states`, `photo_lightbox`, `default_status_bar_style`,
      `appointment_card`, `pro_reads_own_salon`, `design_system_pin`, a11y
      `salon_header` et `layout` (181 cas).
- [x] 24 mutations vues rouges (§8).
- [x] Spec liée depuis le code ; index `README.md` ; SYSTEM.md §11.1
      (`SalonMapMarker`, `SalonLocationPreview`) ; map-basemap-key.md §5.1 ;
      ligne 2.9 de l'audit de parité corrigée ; entrée de roadmap.
- [ ] Goldens Linux régénérés et regardés (`goldens.yml`).
- [ ] Essai sur appareil : client (tap → Carte centrée, feuille ouverte) ;
      Pro Aperçu (tap → sélecteur) ; défilement de la page par-dessus la carte.

## 11. Open questions

- **Hauteur** — 160 dp choisis ici (un aperçu) ; le site affiche 256. À
  confirmer par le propriétaire à l'écran.
- **Écrans dormants** — `phone_login_screen.dart` pousse `/verify-otp`, que
  plus aucun routeur n'enregistre ; le garde ne lit que les fichiers qu'une app
  importe. Le jour où l'écran revient dans un routeur, le garde le verra.
- **La carte du profil Pro (240 dp) garde la bulle de flutter_map** — même
  défaut de classe que l'aperçu (§2.1, « crédits ») : une boîte fixe. Par le
  calcul, pas par une mesure (contenu de la bulle ≈ 352 px à 2,0× sur 390 dp,
  ≈ 212 disponibles dans 240 dp), elle déborderait vers 1,5×. Hors de cette
  branche ; `CartoAttribution.sheet()` est la correction toute prête.
- **La case partagée, ailleurs** — `booking_hub_screen.dart` et
  `booking_confirmation_screen.dart` lisent `selectedProvider` comme le faisait
  la page salon (§2.7). Aucun chemin de la carte n'y mène aujourd'hui ; la
  règle de §2.7 s'y appliquerait telle quelle si un jour il en existe un.
