# MyWeli Pro — la promo « CARNET → DROP » — spec

| | |
|---|---|
| **Statut** | **Approuvé le 2026-10-19 par le propriétaire** (le storyboard « CARNET → DROP »), puis **construit et vérifié les 2026-10-19 et 2026-10-20** sur `feat/promo-reel` par `tool/promo_reel/` : deux coupes (30 s et 15 s), chacune en 9:16, 1:1 et 16:9 — six films, `verify --all` sort 0 sur les six (§9). **Décisions du propriétaire**, toutes le 2026-10-19 (§2 les cite une à une) : le concept « CARNET → DROP » ; l'amapiano à 112,5 BPM ; le carnet dessiné par le code, sans photo ; « Disponible sur l’App Store » ajouté sous la signature, publié seulement après la sortie App Store ; une mesure de plus (« Add one bar (Recommended) ») ; le soulignement et le coup de zoom de la carte de fin gardés (« Keep both ») ; le crochet 16:9 en deux moitiés gardé (« Keep the split ») ; le 16:9 remis en page (« Re-lay it ») ; le plancher 9:16 descendu vers y 1450 (« Extend to ~y 1450 », posé à y 1424, §2). **Puis le 2026-10-20** (§2) : le glissé et la suspension 9:16 acceptés, le 1:1 gardé, les trois retouches 16:9 (poussée sur le sol, cartes à pleine largeur de colonne, coupe franche du formulaire 15 s), le crédit de carte dans les mots de l'app, et la carte de fin « Sur l’App Store et Google Play » · « myweli.com ». **Pas fait** : le propriétaire n'a pas encore écouté la bande-son, et rien n'est publié — **à ne publier qu'une fois les DEUX apps Pro en ligne, iOS et Android** (§10). |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-20 |
| **PRD ref / phase** | Lancement — marketing · V1 (hors app : rien dans `mobile/`, `web/` ni `backend/` ne change) |
| **ROADMAP entry** | [2026-10-19-promo-reel.md](../roadmap/entries/2026-10-19-promo-reel.md) |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-verification-guardrails ✓ |
| **Governs** | `tool/promo_reel/` (son [README](../../tool/promo_reel/README.md) donne la construction, chaque règle et chaque décision prise contre le texte du storyboard, avec ses mesures). Frère de `tool/app_store_preview/` ([pro-app-preview.md](pro-app-preview.md)), dont il lit les prises, les journaux de gestes et les scans sans les modifier, et du Reel « Le trait » (`tool/marketing_video/`, `pro-marketing-reel.md` — tous deux sur la branche `feat/pro-marketing-reel`, pas encore fusionnée). |

## 1. Objectif et périmètre

**Quoi.** Une promo sociale de MyWeli Pro, écrite entièrement en code :
chaque image est dessinée avec skia et envoyée brute à ffmpeg, la musique est
synthétisée et **sert d'horloge**, et les pixels de l'app sont de vraies images
des prises enregistrées, dans leur ordre. Pas de logiciel de montage, pas de
modèle, pas de banque d'images.

**L'idée, « CARNET → DROP ».** Un crochet sombre et saccadé sur un carnet
papier qui déborde (« Votre carnet déborde ? », trois lignes barrées : « Rayé. /
Raturé. / Recopié. »), un souffle (« Respirez. »), puis une coupe franche du noir
au papier de l'app sur le *drop*. Ensuite les vraies prises de MyWeli Pro sur le
salon de démonstration « Maison Nala » prouvent une chose par mesure : une
cliente arrive, un créneau libre est réservé pour un client sans numéro, la
fiche client, le total du mois réalisé, la page que verront les clients. Un
second souffle noir répond au crochet, puis une seule révélation de marque :
l'animation d'ouverture de l'app Pro, seule, puis le mark qui se pose avec
« Plus de clients, moins de gestion. », « Sur l’App Store et Google Play » et
« myweli.com ».

**Dans le périmètre.**
- Deux coupes : **30 s** (15 mesures, 960 images, 32,0 s) et **15 s** (8 mesures,
  512 images, 17,07 s) — chacune avec une mesure de plus que son nom n'en
  tient : la mesure de sortie du propriétaire (§2).
- Trois formats par coupe, **remis en page, jamais recadrés** : 9:16
  (1080 × 1920), 1:1 (1080 × 1080), 16:9 (1920 × 1080).
- Une bande-son par coupe (amapiano, 112,5 BPM, do mineur), écrite dans sa propre
  partition (la 15 s est réécrite, jamais découpée dans la 30 s), partagée octet
  pour octet par les trois formats de la coupe.
- La vérification automatique (a)–(i) sur le MP4 écrit (§8).

**Hors périmètre.** La publication et son calendrier ; une image de
couverture ; les deux emplacements photo du storyboard (« COMPTOIR »,
« FAUTEUIL » : déclarés, laissés vides — décision « pas de photo ») ; la
nouvelle prise N2 (qui écrirait dans le salon de démonstration) ; une version
TikTok plus forte (−12 LUFS) ; tout changement à l'app.

**Comment ça s'insère.** Un dossier neuf, `tool/promo_reel/`, à côté des outils
App Store, qu'il importe sans les modifier (le contrat d'architecture l'interdit) :
les jetons de marque de `tool/app_store_preview/brand.py` et de
`mobile/lib/core/theme/*.dart`, les polices de `tool/app_store_screenshots/fonts`
(Poppins Medium, Inter), les SVG du logo, la Lottie
`mobile/assets/lottie/open/myweli_loader_mixed_pro.json`. Les prises restent dans
`build/` (ignoré par git) du dépôt principal ; rien de ce qu'elles contiennent
n'est commité. Sans objet ici, car rien de tout cela n'existe pour cet outil :
API et contrat (TEMPLATE §3), modèle de données (§4), couches de l'app (§5).

## 2. Les décisions du propriétaire (2026-10-19, 2026-10-20)

Le contrat d'architecture de l'outil les consigne. Les réponses du propriétaire
sont citées telles quelles ; les trois premières lignes sont citées dans les mots
du contrat, qui les transcrit.

| Décision | Ce qui a été construit |
|---|---|
| Le storyboard « CARNET → DROP » approuvé ; « build it » | `storyboard.yaml` en est la forme lisible par la machine et la seule source du pipeline |
| « amapiano 112.5 BPM » | `promo/audio/` : une noire = 16 images, une double croche = 4, une mesure = 64 images (2,1333 s), 1 image = 1 600 échantillons à 48 kHz |
| « hook = code-drawn carnet, NO photos (photo slots stay declared but empty) » | `promo/fx/carnet.py` : papier réglé procédural, gribouillis volontairement illisibles, aucune police manuscrite, aucun nom, aucun numéro. Les zones `slot_card` restent déclarées et vides ; la photo IA `hook-owner-notebook.webp` n'est pas utilisée |
| « ending ADDS « Disponible sur l’App Store » under the tagline (posted only after the release) » | La ligne Inter Medium 40 px #4A4A4A sous la signature, seule sur son repère (30 s : f848 ; 15 s : f400). `storyboard.py` refuse une ligne de magasin sous 40 px. **Remplacée le 2026-10-20** par « Sur l’App Store et Google Play » puis « myweli.com » (ci-dessous) |
| Carte de fin : « Add one bar (Recommended) » | 30 s : 14 → 15 mesures (960 images, 32,0 s) ; 15 s : 7 → 8 (512 images, 17,07 s) ; une mesure de sortie calme. La carte de fin tient ≈ 4,4 s et se lit à 13,5 caractères/s (60 caractères, f827→f960) |
| Carte de fin : « Keep both » | **Écart approuvé** au storyboard (qui disait le mark « only moved and scaled ») : sur le premier temps de la sortie, le trait des ratures du crochet souligne « moins de gestion. » (30 s f896, 15 s f448) ; sur le dernier coup de log drum, le mark donne un coup de zoom à 1,06× (3 images aller, 8 retour ; 30 s f928, 15 s f480) |
| Crochet 16:9 : « Keep the split » | **Écart approuvé** : la page du carnet, en portrait, sur la moitié droite (x 760–1960), les mots sur le noir à gauche (x 0–820) — au lieu de « la page couchée en travers du cadre » |
| Mise en page 16:9 : « Re-lay it » | Le téléphone **posé sur le sol** (le bas de la coque sur y 1026) ; une fenêtre plus haute (y 84–1026, 942 px, contre 918) ; les légendes à 88 px (72 × 1,22) et le compteur à 144 / 48 px, chacun avec sa raison écrite (`type_note`) ; tous les contrôles de confidentialité relancés sur ce cadrage |
| Plancher 9:16 : « Extend to ~y 1450 » | Dans les deux coupes 9:16, la fenêtre du téléphone descend jusqu'à **y 1424** (§6 dit pourquoi pas 1450) ; sous y 1248, seulement des pixels de l'app ; les clés de caméra re-résolues ; tous les contrôles de confidentialité relancés |
| **2026-10-20** — glissé 9:16 : « Keep it » ; suspension 9:16 : « Accept it » ; suspension 1:1 : « Keep as is » | **Écarts approuvés** : le glissé « Arrivé » se joue à y ≈ 1290–1410, sous la ligne de texte (pixels de l'app ; le propriétaire vérifie sous l'interface Reels/TikTok) ; sur le bas du journal et la fin du formulaire, le téléphone s'arrête à y ≈ 985 en 9:16 et pend sous le bandeau en 1:1 (forcé par la ligne 13:15 cachée) |
| **2026-10-20** — 16:9, les trois retouches | (1) **Poussée sur le sol** (`camera.formats.16x9.fill`) sur le bas du journal et la fin du formulaire, la fenêtre grandit avec le téléphone : **1,23×** et pas ~1,3–1,5× — la colonne de gauche va jusqu'à x 878 (« Un créneau libre ? ») et x 1024 (« rempli. ») ; à 1,3× la coque passerait sous « libre ? » et dans « rempli. » ; 1,23× garde chaque légende à ≥ 12 px du téléphone (mesuré : 15 px), la ligne 13:15 toujours sous le bandeau, tous les contrôles de confidentialité relancés ; (2) la carte « Arrivé » et les tuiles de la fiche à **pleine largeur de la colonne** (x 96–1040, 944 px, 1,42× la carte du téléphone) ; « Total réalisé » reste à 760 px (à 944 px elle ferait 508 px de haut, il n'y en a que 427 sous la phrase) ; (3) le formulaire 15 s : **coupe franche à f193** au lieu du fondu, et **plus de rideau** — le formulaire rempli est cadré d'emblée par la fenêtre du journal (W 667), rien ne bouge jusqu'à la poussée du snackbar ; le prix, en 16:9 seulement : « Client sans numéro » coché et « Yao K. » tapé ne se voient pas sur le formulaire (le nom se lit 0,8 s plus tard sur la nouvelle carte du journal) |
| **2026-10-20** — crédit de carte (attribution, décision du propriétaire) | Les mots de l'app : « © OpenStreetMap contributors · © CARTO » (`cartoCredits`, `carto_basemap_layer.dart:116`) ; **entier** de sa première image entière jusqu'à ce que la carte se soit éteinte (f767, dernière image du souffle 2), dans chaque format — round 5 le faisait disparaître avec le téléphone |
| **2026-10-20** — carte de fin : « Both stores, post later » | Dans l'ordre : le mark · « Plus de clients, moins de gestion. » (soulignement et coup de zoom gardés) · « Sur l’App Store et Google Play » (remplace « Disponible sur l’App Store ») · « myweli.com », en dernier ; chaque ligne seule sur son repère de la grille (30 s f832 / f848 / f880 ; 15 s f384 / f400 / f432), les deux partitions recalées (`end.site`) ; 74 caractères f827→f960 = **16,7 car./s** (≤ 17). **Règle de publication** : seulement quand les DEUX apps Pro sont en ligne, iOS et Android (Android ne l'est pas : BACKLOG B0.10) |

**Pourquoi y 1424 et pas 1450.** Mesuré sur take1b 10.000 : à 1450, soit le titre
« Ma journée » reste à moitié fondu dans le bandeau (W 111,9), soit le texte de
l'ancienne ligne 13:15 apparaît dans le fondu du sol (W 130). À 1424, avec
W 128 : le bas de la carte de Fatou B. (582 pt) est 11 px au-dessus du sol, le
texte de la ligne 13:15 (612,7 pt) est 20 px sous le fondu du sol, et le bord du
bandeau tombe entre « Ma journée » (encre ≤ 104,3 pt) et « Aujourd’hui »
(136 pt).

## 3. L'architecture du pipeline

```
storyboard.yaml ──► partition (promo/audio, score_30s.yaml / score_15s.yaml)
                        │  synthèse, mixage, −14 LUFS-I
                        ▼
                    track.wav + events.json   (chaque repère : son image ET son échantillon,
                        │                       lus là où le son a vraiment été écrit)
                        ▼
                    rendu (promo/scenes, promo/render.py) — chaque image dessinée avec skia,
                        │  lue sur l'horloge d'events.json, jamais sur des temps tapés
                        ▼
                    écrivain (promo/media/writer.py) — RGBA brut → ffmpeg libx264 + AAC → reel.mp4
                        │
                        ▼
                    verify (promo/verify.py) — (a)–(i) sur le MP4 écrit, puis « une bande-son par coupe »
```

- **L'horloge** (`promo/timebase.py`). Les positions s'écrivent `mesure.temps.pas`
  (pas 0–3 = la double croche) : `image = (mesure − 1)·64 + (temps − 1)·16 + pas·4`,
  `échantillon = image · 1600`. Tout est exact (entiers et `Fraction`) ; une
  image hors de la grille des doubles croches n'a pas de position — une erreur,
  jamais un arrondi.
- **Le storyboard** (`storyboard.yaml`, vérifié par `promo/storyboard.py`). Cinq
  clés : `meta` (le temps du contrat : 30 i/s, 112,5 BPM, 48 kHz — tout autre est
  refusé), `cuts`, `formats`, `music` (les partitions, seule source des
  identifiants de repères), `scenes`. Une scène dit **quoi et quand** (repères,
  plage de la prise, clés de caméra, touchers, cartes levées, légendes mot à
  mot) ; le `layout` du format dit **où** — une scène qui écrit une position en
  pixels est refusée. Une variante se fait par `--set chemin=valeur`, tenue aux
  mêmes règles ; chaque problème est rapporté d'un coup, avec son chemin.
- **La partition** (`promo/audio/`, [README](../../tool/promo_reel/promo/audio/README.md),
  SCORE.md). Tout est synthétisé en NumPy/SciPy : log drum FM à deux opérateurs
  avec chute de hauteur et sub en phase, grosse caisse façon 909, clap, shaker,
  charleston ouvert, congas, Rhodes FM, orgue, sifflet, nappe, montées,
  impacts, souffles, clics d'interface originaux (3,2 kHz, 8 ms, ±3 %),
  crissement de stylo, carillon à deux notes. Aucun échantillon, aucune boucle,
  aucun son système. La partition est écrite **autour** des événements : un log
  ou une grosse caisse tombe d'abord sur chaque image-héros. Sidechain sur les
  temps connus, mono sous 150 Hz, limiteur à −1,5 dBTP pour que l'AAC reste sous
  −1,0 ; intensité BS.1770-4 maison, recoupée par `ebur128` de ffmpeg.
- **Le rendu** (`promo/scenes/` : `carnet.py` pour le crochet et les souffles,
  `phone.py` pour les quatre prises dans la coque 2,5D vue par une fenêtre de
  caméra, `lottie.py` pour la révélation et la carte de fin, `film.py` pour la
  coupe de bout en bout ; les primitives dans `promo/fx/`, le lecteur Lottie dans
  `promo/lottie/`). La bande-son d'abord, puis l'horloge lue dans son
  events.json, puis chaque image dessinée et envoyée à l'écrivain ; `render.json`
  garde ce que montre chaque image (boîtes, fenêtre, cartes, masques, ligne
  cachée), que verify relit.
- **L'écrivain** (`promo/media/writer.py`). libx264 **High@4.1** (VBV 50 Mb/s,
  tampon 62,5 Mb), yuv420p, CRF 16, une image clé par seconde, étiquettes BT.709 ;
  AAC-LC 48 kHz stéréo 256 kb/s ; `+faststart`. Le nombre d'images est exact (une
  de trop ou de moins est refusée), le WAV fait exactement `images × 1600`
  échantillons, chaque image est opaque, et le fichier s'écrit en `*.partial.mp4`
  renommé seulement quand ffmpeg a fini et que le fichier compte ses images.
- **Les prises** (`promo/media/takes.py`). L'enregistreur n'écrit une image que
  quand l'écran change : l'image montrée à `t` est la dernière dont le temps
  est ≤ t. Chaque image est identifiée par son temps ; une image rendue à la
  place d'une autre est une erreur, jamais une voisine.
- **verify** (`promo/verify.py`) — automatique, sur le MP4 écrit partout où c'est
  possible :
  - **(a)** l'image du rendu sur chaque temps (`beats.png`) contre celle du MP4 (PSNR ≥ 30 dB) ;
  - **(b)** chaque coupe, fouetté et fondu déclaré ± 1 image tirés du MP4 (`transitions.png`) — une coupe change l'image (|ΔL| moyen ≥ 2), un passage `continuous` ne la change pas et n'est pas compté comme une jointure ;
  - **(c)** chaque disque de toucher tenu aux journaux de gestes, et sa teinte remesurée ;
  - **(d)** BS.1770-4 sur l'AAC décodé du MP4 (−14 ± 0,5 LUFS, ≤ −1,0 dBTP), chaque souffle ≥ 7 LU sous le groove sur le master WAV **et** sur le MP4, la queue du dernier coup qui s'éteint ;
  - **(e)** ffprobe et ses assertions (H.264 High au niveau ≤ 4.1) ;
  - **(f)** la synchro image/son : l'attaque de chaque clic et de chaque touche dans l'audio du MP4 contre l'image où son disque ou son caractère apparaît dans les **pixels** du MP4 ;
  - **(g)** l'encre sur les images du MP4 et chaque boîte de `render.json` dans la zone sûre du format, les légendes dans leur colonne, rien sur le téléphone, aucune carte levée sur une légende ;
  - **(h)** l'honnêteté (§4) ;
  - **(i)** la lecture : tout ce qui est à l'écran ensemble, par fenêtre d'arrivée, ≤ 17 caractères/s, la carte de fin comme le reste ; jamais deux lignes qui reçoivent un mot sur la même image ; jamais plus de 2 s sans événement visuel.

  Après les films : **une bande-son par coupe** (track.wav et events.json
  identiques octet pour octet dans les trois formats) ou ÉCHEC. `verify` sort 0
  (PASS) ou 1, et `build.sh` aussi.

## 4. Les règles d'honnêteté — et comment le code les tient

| Règle | Comment le code la tient | Ce que verify mesure |
|---|---|---|
| **Seulement de vrais pixels de l'app** pour l'interface | Chaque écran est une image des prises take1b, take2b, take5b (2026-10-14) ou N1 (2026-10-19), lue par son temps (`takes.py`), jouée dans l'ordre de la prise. Les cartes levées et les poussées sont ces pixels agrandis, jamais redessinés (`fx/lift.py`, `fx/stack.py`). Aucun toast, badge, notification ou libellé généré n'imite l'app : le seul snackbar est le vrai « Rendez-vous créé » enregistré. **Aucune image n'est cachée** : take1b 130.985, que le storyboard croyait noire, est le formulaire avec « Créer le rendez-vous » redevenu noir après son chargement — un état réel, joué | (a) le MP4 contre le rendu ; (h) la liste de ce qui est généré |
| **Chaque élément généré cite sa source** | Une clé `cite:` sur chaque élément généré du storyboard : disques et ondes (le style du film App Store, `tool/app_store_preview/frames.py` tone()/draw_touch :212-219), compteur, crédit de carte, panneaux unis (`AppColors.background`, colors.dart:34), carnet, motif, Lottie, légendes (le code ou le texte approuvé qu'elles reprennent). Le rendu refuse un fondu déclaré sans `cite` | (h) `honesty.txt` : **0 élément sans source** dans chaque film (36 / 36 / 34 en 30 s, 20 / 20 / 19 en 15 s) |
| **Les chiffres viennent des données de démonstration** | Le compteur part du chiffre que montre l'app (« 0 FCFA », N1) et atterrit sur le chiffre de l'app (« 77 000 FCFA », N1 #26) **sur l'image même** où l'app le montre ; le rendu refuse un compteur qui lit ce chiffre plus tôt ou une valeur au-dessus. Format de `formatters.dart:83-93` (espace fine insécable U+202F entre les milliers). Les autres chiffres sont dans les pixels : 17 000 FCFA, 2 visites, 13 oct. 2026 (take2b) ; Total 5 000 FCFA (take1b). Aucun chiffre « Revenus prévus », aucun taux, aucun nombre de salons | (h) les vitesses ; le rendu refuse sinon |
| **Les numéros de téléphone floutés avant l'accumulation** | Les flous sont attachés à la prise (`media/masks.py`) et `Take.picture()` ne rend que des images floutées : chaque carte levée, chaque poussée, chaque sous-image du flou de mouvement en est faite. Le numéro d'Awa K. (rectangle + 4 pt, σ 14 px) ; celui du salon suivi au défilement (`phone_rect_per_frame.csv`), coupé à la barre (740 pt). Un flou qui laisse plus de 15 % du détail, ou qui ne couvre rien, est refusé | (h) 30 s : **35 images mesurées, au plus 11 %** du détail des chiffres. 15 s : aucun flou déclaré (take1b ne montre que le gabarit « Téléphone du client », N1 aucun numéro) — dit tel quel, jamais « mesuré » |
| **La ligne 13:15 cachée jamais lisible** (l'ancienne réservation « Yao K. » de take 1) | Par le cadrage seul, aucun pixel de l'UI modifié : sous le sol au cadrage de Fatou B. (W 128), sous le bandeau sur le bas du journal (W 667 : sa dernière ligne, 644 pt, sur y 560), et seulement dans le flou du fouetté vertical, sur la courbe easeInOut de base de l'app | (h) `HiddenRow` sur **chaque** image de sa scène (30 s : 336 ; 15 s : 192), fouetté, poussée et retour du formulaire compris : ses blocs qui l'identifient (« 13:15 / 13:45 » seulement — la nouvelle réservation est le même client) cherchés dans **toute** la fenêtre du MP4, visibles ≤ 5 % ; tous ses blocs à sa place ≤ 25 % ; hors fouetté, sa part visible ≤ 5 % ; dans le fouetté, ≥ 80 px de flou sur chaque image dont l'obturateur montre sa place |
| **Jamais une attente du serveur accélérée** | Le rendu refuse une vitesse dérivée au-dessus de 1× sauf sur le segment d'un glissé (rampes du geste 1,11×, 2,74×, 1,08× ; jamais au-delà de 3×). Le seul saut de séquence est le **fondu déclaré** de la 15 s (32.998 → 130.262, celui du film App Store), cité, en avant dans la prise, sans disque sur ses images — en 16:9 une **coupe franche déclarée** (`curve: cut`, la décision du propriétaire du 2026-10-20), le même saut, la même déclaration | (h) les attentes (0,965× ; 1,000× ; 0,986× ; 0,995×), les rampes, les fondus déclarés |
| **Un disque seulement là où le doigt a touché** | `media/touches.py` : la règle du film App Store (premier changement d'image − 200 ms) ; chaque disque tenu à un toucher observé de la même prise, à une demi-image près, jamais sur une touche tapée, sur la grille des doubles croches ; noir sur fond clair, blanc sur le volet vert et le bouton noir | (c) 0 problème, teintes conformes ; (f) chaque clic sur l'image où son disque apparaît |
| **L'animation d'ouverture telle qu'elle est livrée** | Le lecteur skia de `promo/lottie/` joue `myweli_loader_mixed_pro.json` en #111111 sur #FAFAFA, contenu intact, seulement retimé par segment (0,90–1,50× sur les segments qui bougent, le maintien raccourci) et figé sur comp 74. Recette contre les goldens Flutter : comp 25 à 0,0015/255 d'erreur moyenne (IoU 0,9993), comp 142 à 0,0002/255 (IoU 1,0000). « MyWeli Pro » n'est jamais tapé | (h) l'élément et sa source |
| **Le crédit de la carte** | Les mots de l'app (`cartoCredits`, `carto_basemap_layer.dart:116`) : « © OpenStreetMap contributors · © CARTO » ; il monte avec les premières lignes de tuiles et reste **entier** jusqu'à ce que la carte se soit éteinte (f767), dans chaque format | (h) `credit_problems` : entier de sa première image entière à f767 ; un test relit la constante Dart |
| **Rien de ce qui n'existe pas** | Aucun SMS, rappel WhatsApp, paiement, acompte, KYC, sélecteur de salon, offre ou module V2/V3. La ligne « WhatsApp » de la page publique est le lien wa.me du salon, jamais légendé ni levé. « Réserver (après la mise en ligne) » reste visible comme la réserve de la page elle-même, gardée lisible (verify (g) `app text`) | — |
| **Les noms sont inventés** | Fatou B., Awa K., Mariam T., Koffi A., Yao K. sont des noms de démonstration ; Maison Nala est un salon de démonstration fictif, jamais présenté comme un vrai client | — |

**Les légendes et ce qui les fonde** (chaque `cite:` dans le storyboard) :
« Glissez, appuyez. » — le Slidable de `pro_journal_screen.dart:284-352` (le
glissé révèle « Arrivé », le tap appelle `journal.arrive`) ; « Un créneau libre ? »
— `:260` ; « Réservez-le, même sans numéro. » — `pro_manual_booking_screen.dart:361`
(« Client sans numéro ») ; « Créneau ~~libre~~ rempli. » — `pro_journal_screen.dart:208,
:260` (la ligne « Libre — 14:45 » remplacée, les 15 minutes restantes sous la règle
des 30 minutes) ; « Votre fichier clients. » — le texte promotionnel du magasin
([app-store-forms.md](app-store-forms.md):330) ; « Chaque rendez-vous terminé,
compté. » — `earnings_screen.dart:190/:207` (« encaissé » n'est jamais employé) ;
« Votre page, prête pour vos clients. » et « Ils réservent dès la mise en ligne. »
— la capture approuvée 02 (`tool/app_store_screenshots/screens.json`) ; « Plus de
clients, moins de gestion. » — la signature Pro du livre de marque, pas une
statistique ; « Sur l’App Store et Google Play » et « myweli.com » — la décision
du propriétaire (2026-10-20) : le site est vrai aujourd'hui, la ligne des
magasins le sera quand l'app Android sera en ligne — d'où la règle de
publication (§10).

## 5. Le storyboard, mesure par mesure

Les temps sont ceux du film construit (le storyboard approuvé, avec les écarts
consignés dans le README de l'outil). Noir = la douleur, papier = l'app.

### La coupe 30 s — 15 mesures, f0–f959

| Mesures (images) | À l'écran | Image et mouvement | Son |
|---|---|---|---|
| **1–2.3** (f0–111) crochet | « Votre » f0 « carnet » f8 / « déborde ? » f16 ; puis la pile « Rayé. » f64 / « Raturé. » f76 / « Recopié. » f88 | Le carnet dessiné, incliné (rotX 22°), poussée déjà en cours à f0 (1,10 → 1,16), l'entrée qui s'écrit (30 % à f0, finie à f24) ; coupe franche en macro sur 1.3 (f32, l'entrée coincée, une note en marge qui s'écrit à f48) ; retour au plan large sur 2.1 et trois ratures sur les coups de log f64 / f76 / f88, chacune avec un coup de zoom 1,025 ; poussée et plongée vers le noir f96–111, avec flou de mouvement ; grain | Pas de grosse caisse ; log drum, shaker, Rhodes Cm9 filtré qui s'ouvre, tics sur chaque mot, crissements de stylo ; première montée |
| **2.4** (f112–127) souffle | « Respirez. » | Noir et motif sombre de la marque, le seul temps immobile du crochet | Presque le silence (8,4 LU sous le groove) |
| **3–4** (f128–255) drop 1 : « Ma journée » | « Une » f128 « cliente » f136 « arrive ? » f144 / « Glissez, » f160 « appuyez. » f176 | Coupe noir → papier, le téléphone claque (échelle 1,10 → 1,00, rotX 14° → 0) ; take1b 10.000, caméra W 56 → 128 (Fatou B. sur le sol, la ligne 13:15 dessous) ; le vrai glissé f144 (1,11×), volet « Arrivé » ouvert f160 ; le tap f176, l'attente de l'enregistrement à 0,965× ; badge « Arrivé » f232 ; la carte se lève f232 et se repose f248–253 (en 9:16, elle surgit sur place, sa place vidée par un panneau uni) | IMPACT f128, le groove entre ; clics f144, f176 |
| **5–6** (f256–383) le créneau, le formulaire | « Un » f256 « créneau » f264 « libre ? » f272 ; « Réservez-le, » f320 / « même » f328 « sans » f336 « numéro. » f344 | Fouetté vertical f256–262 (W 128 → 667) jusqu'à « Libre — 14:45 » ; tap f280 (disque parti f285), le formulaire entre à 1× ; le time-lapse par paliers : « Coupe homme » f320, « Client sans numéro » f336, le champ du nom f352, les touches Y a o ␠ K . sur les doubles croches f360–380 (pas de clavier à l'écran) ; la caméra garde la ligne active au milieu de la fenêtre (W 312,73 / 56 / 468,73 / 519,73) | Congas et rimshots ; clics et touches ; whoosh d'accélération |
| **7** (f384–447) « Créer » | « Créneau » f400 « libre » f408 ; « libre » barré f440 | Défilement du formulaire à 2,74× (geste) jusqu'à « Total 5 000 FCFA » ; W 667 ; tap « Créer le rendez-vous » f400 à 0,986× ; « Ma journée » revient, le vrai snackbar « Rendez-vous créé » f436 ; poussée 1,791 → 2,0 px/pt f436–460, le point 667 tenu au bord du bandeau | Le log drum presque seul (Rhodes et clap sortent ; grosse caisse et shaker restent) ; carillon original f436 ; le whoosh du stylo du crochet f440 |
| **8** (f448–511) la fiche | « rempli. » f448 ; « Votre » f464 « fichier » f472 « clients. » f480 | Coupe franche sur le clap f464 : la « Fiche client » d'Awa K. (take2b 6.500, numéro flouté et sous le bandeau, W 216) ; trois vraies tuiles se lèvent une à une, f472 / f480 / f488 — « 2 » Visites, « 17 000 FCFA » Dépensé, « 13 oct. 2026 » Dernière — sur un panneau uni qui grandit avec elles ; « 0 Absences » n'est pas levé | Arrêt de la batterie f496 |
| **9–10** (f512–639) drop 2 : « Revenus » | Le compteur seul : « Aujourd’hui » / « 0 FCFA » → « Mois » / « 77 000 FCFA » ; puis « Chaque » f576 « rendez-vous » f584 / « terminé, » f592 « compté. » f600 | Fouetté horizontal f512–518 ; N1 (W 124) ; tap « Mois » f528 ; l'étiquette roule f536, les chiffres roulent et atterrissent **f548** sur la première image de l'app qui montre le chiffre (l'attente réelle de 0,663 s à 0,995×), coup de zoom 1,08 ; le compteur sort, la phrase arrive, la vraie carte « Total réalisé » se pose f600 | Impact léger f512, sifflet, orgue ; tics sur les doubles croches ; atterrissage f548 |
| **11–12.3** (f640–751) la page publique | « Votre » f640 « page, » f648 « prête » f656 / « pour vos clients. » f664 ; « Ils » f704 « réservent » f712 / « dès la » f720 « mise en ligne. » f728 | Coupe franche sur le haut de la page de Maison Nala (take5b 25.900 : photo de couverture, logo « Maison N », « Nouveau », « 5 services • Voir les tarifs ») ; inclinaison d'entrée, parallaxe ; le vrai défilement f672–736 (1,08×, images choisies par position de défilement) ; le numéro du salon flouté ; la fin de page à W 427,32 : « Aperçu — voici ce que verront vos clients. » / « Réserver (après la mise en ligne) » lisibles ; crédit « © OpenStreetMap contributors · © CARTO » dès que les tuiles de carte arrivent | Breakdown, troisième montée |
| **12.4** (f752–767) souffle 2 | « Ils réservent dès la mise en ligne. » en blanc | Noir, la page recule (1,00 → 0,90, opacité → 0 en 12 images) ; le crédit, blanc sur noir, reste entier jusqu'à f767 (la carte éteinte) | Presque le silence (8,5 LU sous le groove) |
| **13** (f768–823) révélation | — (« MyWeli Pro » est le vecteur de la Lottie) | Coupe franche sur #FAFAFA nu ; l'animation d'ouverture Pro, seule, comp 900 px centrée (540, 680) en 9:16 ; M et W se rejoignent en mark, flou de 8 sous-images sur la transformation | Le grand IMPACT f768, nappe Cm9 et sub, scintillement, glissé FM |
| **14–15** (f824–959) carte de fin et sortie | « Plus de clients, moins de gestion. » (un seul dévoilement f827→f832) ; « Sur l’App Store et Google Play » f848 ; « myweli.com » f880 | Passage continu (pas une coupe) : le mark (comp 74) monte et se pose f832 à l'échelle 1,2 ; soulignement f896 ; coup de zoom 1,06× f928 ; tenue jusqu'à la dernière image | Dernier log f832, groove léger ; mesure 15 : sortie calme, dernier accord et dernier log f928, qui s'éteignent avant la fin |

Jointures : coupes f32, f64, f112, f128, f464, f640, f752, f768 ; fouettés f256
(dans le téléphone) et f512 ; passage continu f824.

### La coupe 15 s — 8 mesures, f0–f511

| Mesures (images) | Contenu |
|---|---|
| **1** (f0–47) crochet, (f48–63) souffle | Le carnet, poussée en cours à f0 (1,10 → 1,13), l'entrée qui s'écrit ; « Votre » f0 « carnet » f8 / « déborde ? » f16, tenu jusqu'à f47 ; trois ratures sans mots (le temps de lecture) sur f24 / f32 / f40 ; pas de macro, pas de plongée. « Respirez. » f48–63 |
| **2–4** (f64–255) le journal | Coupe franche sur W 128 (sans claquement) ; « Une cliente » f64 « arrive ? » f72 / « Glissez, » f80 « appuyez. » f88 ; glissé f64 (1,11×), volet ouvert f80, tenu à 1×, tap f88 ; « Arrivé » f144 (0,965×), la carte levée f144–159 ; fouetté vertical f160 (W 128 → 667) ; « Créneau » f160 « libre » f168 ; tap « Libre » f168, le formulaire entre ; **le fondu déclaré f193–196** (32.998 → 130.262, le formulaire ouvert → le formulaire rempli : il saute le remplissage, W 667 → 521,67 pour que les champs restent en place ; **en 16:9 une coupe franche à f193**, le formulaire rempli cadré d'emblée à W 667) ; tap « Créer » f196 (0,986×) ; retour à W 667 f204–216 (16:9 : déjà là) ; snackbar f232, poussée f232–252 ; en 16:9, la poussée sur le sol f168–184, tenue ; « libre » barré f236, « rempli. » f240 |
| **5** (f256–319) « Revenus » | Fouetté horizontal ; le compteur seul ; « Mois » f272, l'étiquette f280, atterrissage f292 sur « 77 000 FCFA » (0,995×) ; pas de phrase, pas de carte levée |
| **6** (f320–375) révélation | La Lottie, le même retimage sur les repères de la 15 s |
| **7–8** (f376–511) carte de fin et sortie | Passage continu ; le mark se pose f384 ; la signature f379→f384 ; « Sur l’App Store et Google Play » f400 ; « myweli.com » f432 ; soulignement f448 ; coup de zoom f480 ; 74 caractères f379→f512 = 16,7 caractères/s |

Jointures : coupes f48, f64, f320 ; fouettés f160 et f256 ; fondu déclaré f193 (en 16:9 une coupe franche déclarée) ;
passage continu f376. Laissés hors de la 15 s : le time-lapse du formulaire, la
fiche, la phrase et la carte de « Revenus », la page publique.

## 6. Formats et zones sûres

Le petit côté fait toujours 1080 px : les tailles de texte, l'échelle du
téléphone (1,791 px/pt, l'écran recadré à partir du point 56, 720 px de large),
le disque, les cartes levées et la Lottie (900 px) gardent la même taille en
pixels partout. `storyboard.py` refuse toute autre différence au format de
référence, sauf le texte plus grand du 16:9 avec sa raison écrite (jamais la
carte de fin ni le crédit).

| | 9:16 (référence) | 1:1 | 16:9 |
|---|---|---|---|
| Toile · zone sûre | 1080 × 1920 · **x 120–900, y 270–1248** — le rectangle combiné le plus strict de TikTok, Reels et WhatsApp Status ; au-dessus de y 840 (avant la colonne de boutons) les légendes centrées peuvent aller à x 960 | 1080 × 1080 · x/y 54–1026 (EBU R95, graphismes, 5 %) | 1920 × 1080 · x 96–1824, y 54–1026 (EBU R95, 5 %) |
| Légendes | Bandeau opaque y 0–560 (fondu à 600), centrées sur x 540, 72 px | Bandeau y 0–358 (fondu à 388), centrées, 72 px | Pas de bandeau : colonne gauche x 96–1040, alignée sur x 96, centrée sur y 440, **88 px** |
| Fenêtre du téléphone | x 180–900, y 600–**1424** ; sous y 1248, des pixels de l'app seulement | x 180–900, y 388–1002 (le bord du bandeau sur la rangée des puces) | x 1088–1808 (la coque finit sur x 1824), y 84–1026 ; **le téléphone posé sur le sol** : là où W soulèverait le bas de l'écran au-dessus de y 1010, c'est le bord du bandeau qui descend ; sur le bas du journal et la fin du formulaire, **la poussée sur le sol** 1,23× (le bord à y 550 au lieu de 639) |
| Cartes levées | x 120–900 sur le téléphone voilé à 55 %, ≤ y 1248 même en vol | x 150–930, sur le téléphone voilé | à côté du téléphone, sans voile ; elles descendent puis passent sous la phrase : « Arrivé » et les tuiles de la fiche à pleine largeur de colonne, **x 96–1040** ; « Total réalisé » x 284–1044 |
| Compteur | Centré, lignes de base 322 / 496 | Centré, 120 / 284 | Depuis x 96, 144 / 48 px, 354 / 561 |
| Crochet | La page x 40–1040 depuis y 640 | La page x 120–960 depuis y 10 | En deux moitiés (approuvé) : la page x 760–1960, le noir x 0–820 |
| Crédit de carte « © OpenStreetMap contributors · © CARTO » | Pied du bandeau, fini sur x 900, ligne de base 552 | Pied du bandeau, x 900, 346 | Pied de la colonne gauche, fini sur x 1040, 1016 |
| Révélation · carte de fin | Lottie (540, 680) · mark y 400–599, signature à 712, magasins 808, site 872 | (540, 520) · 250–449, 560, 656, 720 | (960, 500) · 230–429, 540, 636, 700 |

**La caméra recadre par règle.** Les clés W sont mesurées dans la fenêtre 9:16
et chacune dit ce qu'elle garde : `top` (un point sur le bord du bandeau — la
ligne 13:15 cachée, le numéro flouté de la fiche, le titre de « Revenus »),
`centre` (la ligne active du formulaire au milieu de la fenêtre), `floor` (la
carte de Fatou B. sur le sol) ou `text_floor` (la ligne la plus basse où l'on
lit le texte de l'app : en 9:16, y 1248). Les autres formats recadrent par
cette règle, jamais en montrant le haut de l'écran là où le 9:16 ne le montrait
pas. En 9:16 : Fatou B. 128 ; le bas du journal et « Créer » 667 ; les lignes
du formulaire 312,73 / 56 / 468,73 / 519,73 ; la fiche 216 ; « Revenus » 124 ;
la fin de page 427,32 (souffle 2 : 449,66, la même place sans la parallaxe de
40 px).

## 7. Livrables

`build.sh` écrit dans `tool/promo_reel/out/` (ignoré par git, comme `.venv/`) ou
dans `--out DIR` ; **aucun film, aucune prise n'est commité**. Par film,
`<coupe>-<format>/` : `reel.mp4`, `track.wav` et `events.json` (identiques dans
les trois formats d'une coupe), `meter.json`, `spectrogram.png`, `waveform.png`,
`render.json` ; et `verify/` : `report.txt` / `report.json`, `probe.json`,
`honesty.txt`, `beats.png`, `transitions.png`, `frames/` (images pleine taille
tirées du MP4), `renderer/` (l'image du rendu sur chaque temps).

Le rendu final du 2026-10-20 (les décisions du propriétaire après R5, §2 ; le
code de ce commit) :

| Film | Images · durée | Octets | Débit vidéo | sha256 (début) |
|---|---|---|---|---|
| 30s-9x16 | 960 · 32,000 s | 28 643 591 | 6,88 Mb/s | `28daccd96d7138dd` |
| 30s-1x1 | 960 · 32,000 s | 16 876 593 | 3,94 Mb/s | `6afd983582cdaa56` |
| 30s-16x9 | 960 · 32,000 s | 27 350 713 | 6,56 Mb/s | `ef69f31f75c89752` |
| 15s-9x16 | 512 · 17,067 s | 11 869 282 | 5,29 Mb/s | `be4119f973e7883f` |
| 15s-1x1 | 512 · 17,067 s | 6 935 499 | 2,98 Mb/s | `5f8b659ce601aa4d` |
| 15s-16x9 | 512 · 17,067 s | 11 172 437 | 4,96 Mb/s | `b1cfe3043251d696` |

Tous : H.264 High niveau 4.1 (lu par ffprobe : `level=41`), yuv420p BT.709,
30 i/s constants, une image clé toutes les 30, CRF 16, VBV 50 000 / 62 500 ; 4
images de référence en 9:16 et 16:9, 5 en 1:1 (1080 × 1080 = 4 624
macroblocs, que le niveau 4.1 autorise) ; AAC 48 kHz stéréo (271 kb/s en 30 s,
268 en 15 s), décalage image/son 0 ms, `faststart`.

## 8. Construire

```
tool/promo_reel/build.sh                    # venv, contrôles, les six films, puis verify --all
tool/promo_reel/build.sh --set k=v …        # la même chose sur une variante du storyboard
tool/promo_reel/build.sh test               # les tests unitaires
python -m promo build  --cut 30s --format 9x16 --out DIR     # un seul film (depuis tool/promo_reel)
python -m promo verify --cut 30s --format 9x16 --out DIR
python -m promo.render --frames 0,144,552 --out DIR          # des images fixes pleine taille, sans MP4
```

1. **Python 3.12** (`/usr/local/bin/python3.12`, sinon `python3.12` sur le PATH,
   ou `PROMO_PYTHON`) et un venv privé, `tool/promo_reel/.venv`, avec exactement
   `requirements.txt` (épinglé : skia-python 144.0.post2, numpy 2.5.4, scipy
   1.18.1, Pillow 13.0.0, PyYAML 6.0.3, imageio-ffmpeg 0.6.0, pybind11 3.1.0),
   reconstruit quand ce fichier change.
2. **ffmpeg et ffprobe** (Homebrew : `brew install ffmpeg`, ou `PROMO_FFMPEG` /
   `PROMO_FFPROBE`) ; la commande s'arrête et dit comment les installer s'ils
   manquent.
3. `python -m promo build --all` puis `python -m promo verify --all` : les films
   un par un, la bande-son de chaque coupe rendue une fois et partagée.

**Le matériau** se lit, ne s'écrit jamais : les prises App Store sous
`build/app-store/pro/preview/v2/` du dépôt principal (l'outil le trouve depuis un
worktree par son fichier `.git`, ou `PROMO_MATERIAL`), N1 sous
`build/marketing/promo/takes/n1/` (ou `PROMO_TAKES`). Les tests sur les vraies
prises sont ignorés quand le matériau n'est pas sur la machine.

**Ne jamais lancer deux rendus complets en même temps** : le Mac sature.
Compter environ 13 minutes de rendu (768 s pour les six films au dernier rendu :
30 s 185 / 123 / 229 s, 15 s 86 / 54 / 91 s) et une dizaine de minutes de
vérification (9 min 01).

## 9. Vérification — le rendu final

**Ce qui a été observé** (le 2026-10-20, les décisions du propriétaire après
R5). Un premier rendu du tour, `build --all` en 814 s, a échoué à `verify` sur
deux vrais constats, corrigés avant le rendu final : **(h)** dans les deux 16:9,
la recherche de l'ancienne ligne 13:15 « trouvait » la ligne dans la carte
« Arrivé » en vol (30 s f233 / f250, 15 s f145 / f156) — c'était la carte de
Fatou B. : agrandie 1,42×, son petit « 13:15 » (son heure de fin) a la taille en
pixels du grand « 13:15 » de l'ancienne ligne ; verify laisse désormais les
cartes levées hors de sa recherche et le rendu refuse une carte dont la source
touche une ligne cachée ; **(g)** le nouveau contrôle « jamais un toucher rogné »
trouvait le tap « Mois » de « Revenus » rogné par le fondu du bandeau (0,58 à
0,69 du disque visible) dans les six films — un cadrage d'avant ce tour (le titre
« Revenus » gardé sous le bandeau est à 16 pt du haut du disque, le fondu en
fait 17 à 22 : aucun cadrage ne montre les deux entiers) ; la règle tient donc
chaque disque entier sur toute image où le téléphone est poussé, et rapporte
les autres. Le rendu final : `build --all` en 768 s, sortie 0 — les six films
**identiques octet pour octet** à ceux du premier rendu (les corrections ne
touchent que des contrôles) ; `verify --all` en 9 min 01, **sortie 0, six PASS**
et une bande-son par coupe. Aucun fichier de code ni le storyboard n'a été
modifié après le début du rendu. Les six rapports `verify/report.txt` sont
relus ici ; le tableau en reprend les chiffres.

| Film | (a) PSNR min | (b) jointures | (c) touchers | (d) MP4 : LUFS-I / dBTP | (d) souffles sous le groove, MP4 / master | (d) queue du dernier coup | (f) synchro | (g) boîtes hors zone | (h) ligne 13:15 | (i) pire fenêtre / carte de fin |
|---|---|---|---|---|---|---|---|---|---|---|
| 30s-9x16 | 40,8 dB | 10 | 10, teintes 10/10 | −14,07 / −1,29 | 8,84 et 9,13 / 8,43 et 8,48 LU | 21,4 dB plus bas 22 images après ; les 100 dernières ms 35,1 dB sous | 14/14 | 0 sur 3 154 | 336 images, flou ≥ 110 px, au plus 1,2 % hors fouetté | 16,9 / 16,7 car./s |
| 30s-1x1 | 40,8 dB | 10 | 10, 10/10 | idem | idem | idem | 14/14 | 0 sur 3 145 | 336, ≥ 86 px, 0,0 % | idem |
| 30s-16x9 | 41,4 dB | 10 | 10, 10/10 | idem | idem | idem | 14/14 | 0 sur 3 167 | 336, ≥ 90 px, 0,0 % | idem |
| 15s-9x16 | 41,4 dB | 6 | 5, 5/5 | −14,05 / −1,70 | 8,82 / 8,29 LU | 21,4 dB ; 35,0 dB | 5/5 | 0 sur 1 317 | 192, ≥ 110 px, 0,0 % | 16,9 / 16,7 car./s |
| 15s-1x1 | 41,1 dB | 6 | 5, 5/5 | idem | idem | idem | 5/5 | 0 sur 1 317 | 192, ≥ 86 px, 0,0 % | idem |
| 15s-16x9 | 41,5 dB | 6 (la coupe déclarée f193 change l'image de 11,9) | 5, 5/5 | idem | idem | idem | 5/5 | 0 sur 1 317 | 192, ≥ 90 px, 0,0 % | idem |

Et, sur les six : **(e)** H.264 High@4.1, le bon nombre d'images, 30 i/s
constants, décalage image/son 0,0 ms ; **(f)** chaque attaque lue dans le MP4 à
au plus 0,83 ms (30 s) et 0,17 ms (15 s) du premier échantillon de son image ;
**(g)** l'encre de 40 (30 s) et 27 (15 s) images du MP4, chaque légende entière
— les trois lignes de la carte de fin comprises —, le compteur sur chaque image
de son roulement, chaque carte, le crédit — 0 hors zone ; aucune carte sur une
légende ; **aucune légende à moins de 12 px du téléphone** tel qu'il est posé,
sur 635 (30 s) et 256 (15 s) images ; le texte de l'app gardé lisible (la
réserve de la page, « Créer le rendez-vous », le snackbar) dans le rectangle et
entier dans la fenêtre sur 91 (30 s) et 47 (15 s) images ; aucun disque rogné
sur une image poussée (le tap « Mois » rapporté, ci-dessus) ; les ratures du
crochet lues sur le MP4 avec un contraste de 144 à 191 (≥ 40) ; en 9:16
l'encre animée du crochet est hors du rectangle de **texte** (rapporté, pas
refusé), en 1:1 et 16:9 toute dans la zone graphique ; **(h)** 0 élément généré
sans source, les attentes et les rampes inchangées (30 s : 0,965 / 1,000 /
0,986 / 0,995× et 1,113 / 2,740 / 1,075 / 1,081× ; 15 s : 0,965 / 1,000 / 0,986 /
0,995× et 1,113×), le fondu déclaré de la 15 s (f193–f196 en 9:16 et 1:1, une
coupe franche déclarée à f193 en 16:9), la ligne 13:15 trouvée nulle part
(0,0 % visible là où on la cherche, hors cartes levées), **le crédit de carte
« © OpenStreetMap contributors · © CARTO » entier de sa première image entière
jusqu'à f767** (les trois films 30 s) ; **(i)** la pire fenêtre est
« Respirez. » (16,9 car./s), **la carte de fin 74 caractères en 4,433 s
(f827→f960, 15 s f379→f512) = 16,7 car./s**, aucune image où deux lignes
reçoivent un mot, le plus long moment sans événement visuel 1,33 s (30 s
f600→f640) et 1,07 s (15 s). **Une bande-son par coupe** : 30 s `track.wav`
93f98379ce7d / `events.json` 23d635c8baab, 15 s f2c8a5fc10f0 / c603003c4954,
dans les trois formats. La crête vraie du 30 s sur le MP4 est à −1,29 dBTP (≤ −1,0 ;
−1,63 en R5 : l'AAC de la nouvelle mesure 14).

**Les tests** : 415, OK (1 ignoré), dans le worktree. Chaque contrôle ajouté
pendant les tours de revue a été vu rouge avant sa correction ; chaque message
de commit en garde la liste (§11).

**Ce que la revue R6 a mesuré à part, sur les pixels des MP4 du rendu de R5**
(ses scripts ne sont pas dans le dépôt ; pas refait sur ce rendu) : la reconnaissance de texte de macOS (Vision) sur une
image sur quatre de chaque scène de l'app, 672 images pleine taille dans les six
films — zéro « 13:45 », zéro « 13:15 » à côté de « Yao », zéro chiffre de
téléphone (le seul « +225 » est le gabarit « Téléphone du client ») ; une
recherche par corrélation (NCC) du bloc « 13:15 / 13:45 » de l'ancienne ligne sur
une image sur deux du journal : meilleur score 0,618, sur le bloc de Fatou B.
elle-même, quand le témoin collé exprès donne 0,993 ; le flou du fouetté ajusté
sur les pixels (9:16 112 / 100 px, 1:1 89 / 83, 16:9 82 / 84 aux images f257 /
f261 — la marge du 16:9 est mince : 82 px pour un seuil de 80) ; 20 mutants du
câblage des verdicts et de l'écrivain, chacun sur sa propre copie, tous tués.

**Regardé** (R5, R6) : les douze planches, et en pleine taille les images clés de
chaque format — les transitions, la carte « Arrivé », le fouetté, le roulement
de l'étiquette, le fondu de la 15 s, la fiche, la fin de page, le souffle 2, la
poussée et le vol des cartes en 16:9. **R7** : les douze planches de ce rendu,
et, tirées du MP4, en pleine taille et à 50 % chaque image changée — la poussée
16:9 (30 s f280, f292, f416, f436, f460 ; 15 s f184, f193, f196, f216, f252), la
carte « Arrivé » à pleine largeur (f240, lisible à 50 %), les tuiles (f495), le
crédit jusqu'à f767 dans les trois formats, la carte de fin des six films (f884,
f959 ; 15 s f436, f511 : les trois lignes lisibles à 50 %).

## 10. Ce qui n'est PAS fait

1. **Le propriétaire n'a pas écouté la bande-son.** L'amapiano à 112,5 BPM est
   approuvé sur le papier ; le mix est mesuré (intensité, crêtes, souffles,
   queue de sortie), pas jugé à l'oreille par lui. La question du storyboard
   reste ouverte : l'amapiano convient-il au public d'Abidjan, ou faut-il la
   variante avec une couche conga/bongo afro-house (même grille, l'image ne
   change pas) ? Aucune source ne couvre Abidjan en particulier.
2. **La prise N1 dépend des données de démonstration du 14 octobre.** N1 a été
   filmée le 2026-10-19 vers 03:45, en lecture seule, contre la production, sur
   le salon de démonstration : « Mois » y vaut 77 000 FCFA, la somme des rendez-vous
   terminés du 4 au 14 octobre (ceux des prises du 14). La remise à zéro
   hebdomadaire de la démonstration (≈ 21–22 octobre, heure non vérifiée) peut
   changer ce chiffre : une prise refaite après montrerait d'autres nombres, et
   le compteur (`start`, `end`, `figure_picture`, l'atterrissage) devrait être
   repointé sur elle. Le film reste cohérent avec lui-même, puisque le compteur
   lit N1. De même, take1b, take2b et take5b correspondent au build 587 : après
   0.0.2 (le champ téléphone de #611, le « Modifier » de #614), revérifier le
   formulaire et la fiche avant de réutiliser le film.
3. **Rien n'est publié — les règles de publication.**
   - **RÈGLE DE PUBLICATION (le propriétaire, 2026-10-20) : seulement quand
     les DEUX apps MyWeli Pro sont en ligne, sur l'App Store ET sur Google
     Play.** La carte de fin dit « Sur l’App Store et Google Play » ; l'app
     Android ne l'est pas aujourd'hui (BACKLOG B0.10 : rien n'est encore saisi
     dans la Play Console ; LAUNCH.md : Android en dernier). Que les deux y
     soient le jour de la publication ne se vérifie pas d'ici (les fiches des
     magasins : le propriétaire). « myweli.com » est vrai aujourd'hui.
   - **La photo de couverture de Maison Nala** (la page publique, mesures 11–12)
     ne repose que sur la déclaration du propriétaire d'une licence libre ; son
     usage dans une publicité et ses liens sources sont à confirmer avant de
     publier.
   - **Les conditions de CARTO / OpenStreetMap pour la vidéo** n'ont pas été
     lues ; le film montre la ligne de crédit de l'app elle-même, « ©
     OpenStreetMap contributors · © CARTO »
     (`mobile/lib/widgets/common/carto_basemap_layer.dart:116`, la décision du
     propriétaire du 2026-10-20), entière jusqu'à ce que la carte soit éteinte.
   - **La coupe 30 s dure 32,0 s**, au-delà de l'ancienne limite de 30 s des
     statuts WhatsApp (le choix du propriétaire, « Add one bar »).
   - **Voir sur un vrai téléphone**, sous l'interface de TikTok, Reels et
     WhatsApp Status ; WhatsApp ré-encode fort, un encodage plus léger peut
     être nécessaire (pas construit).
   - Pas d'image de couverture construite ; les canaux et la date sont la
     décision du propriétaire.
4. **Les petits défauts que la revue R6 a laissés ouverts** (aucun ne montre la
   ligne 13:15 ni un numéro) :
   - 9:16, l'« Arrivé » qui surgit sur place (30 s f232–233 et f250–252, 15 s
     f144–145 et f156–158) : la carte levée apparaît ou s'efface pendant que le
     panneau qui vide sa place n'est qu'à moitié opaque, si bien que la carte de
     Fatou B. se voit deux fois, en transparence, environ 200 px l'une de
     l'autre (Vision lit deux « 13:15 », tous deux de Fatou B., sur 30 s f232 et
     15 s f156). Correctif proposé : le panneau entièrement opaque une image
     avant que la carte ne se montre, retiré seulement quand elle est partie.
   - 9:16, l'ombre portée de la carte posée descend sous y 1248 (ΔL ≈ 14 à
     y 1248, plus rien vers y 1290) ; la boîte enregistrée s'arrête à 1236 et
     laisse l'ombre de côté, donc (g) ne la voit pas. Tout le texte est au-dessus
     de 1248 ; à reprendre seulement si le propriétaire compte l'ombre dans la
     carte.
   - En 16:9, le crédit de carte monte sur f682–683 (≈ 20 % puis ≈ 73 %) pendant
     que les tuiles entrent à peine dans le fondu : il n'est pas « entièrement
     là dès que les tuiles se voient » à cette image près.
5. **Pas faits, par choix** : N2 (refaire « Libre » → « Créer » sous un autre nom,
   pour que l'ancienne réservation 13:15 quitte le matériau — elle écrit dans le
   salon de démonstration et attend le feu vert du propriétaire) ; les emplacements
   photo ; la version TikTok à −12 LUFS.

## 11. Les tours de revue

Chaque tour a relu les films écrits, pas seulement le code ; chaque correction
porte dans son message de commit les contrôles vus rouges avant elle.

| Tour | Ce qui a été revu | Ce qui a changé (commit) |
|---|---|---|
| Construction | — | Quatre constructeurs en parallèle — le temps, le storyboard et les médias ; la bande-son et events.json ; le lecteur Lottie (recette contre les goldens) ; les primitives skia — fusionnés, puis SCENES : la 30 s en 9:16 rendue depuis `storyboard.yaml` et vérifiée sur le MP4 (`3d9436cf`) |
| **R1** | Le premier film 30 s | Le souffle 2 presque silencieux, le compteur jamais en avance (« 76 988 » sur f547, « 77 000 FCFA » sur f548), l'atterrissage à f548 (0,995×, f552 rejeté à 0,829×), le glissé de 6 images, verify sur les pixels du MP4, la carte de fin une arrivée à la fois — elle se lisait à 26,1 car./s : décision du propriétaire en attente (`a761ad29`) |
| **R2** | `a761ad29` | La décision « Add one bar (Recommended) » : 15 et 8 mesures, la sortie calme, la carte de fin à 13,5 car./s, le soulignement et le coup de zoom pour la règle des 2 s ; le panneau de la fiche qui grandit avec les cartes ; (h) cherche dans toute la fenêtre ; les souffles ≥ 7 LU sur le master (`3458abcb`). Puis la 15 s en 9:16 (`27288826`), et le 1:1 et le 16:9 des deux coupes : six films (`3010285a`) |
| **R3** | Les six films | La sortie qui s'éteint, l'encre du crochet vue dans chaque format, les jointures nommées pour ce qu'elles sont (le passage continu), le compteur 1:1 dégagé du téléphone, la poussée 16:9 qui tient le bord de la zone sûre (`17024e33`) |
| **R4** | `17024e33` | Les décisions du propriétaire après la revue des six films (§2 : le plancher 9:16, la remise en page 16:9, les écarts approuvés) et les restes de R4 (« 0 Absences », le bord du bandeau 1:1 sur les puces, le câblage des verdicts testé). Le premier rendu de ce tour a échoué à verify sur trois vrais défauts, corrigés avant le rendu final : en 15s-16:9 « Créer » et son disque sous le sol ((f) ne trouvait pas de disque) ; en 9:16 les boîtes de la carte « Arrivé » sous y 1248 ; une onde de toucher jugée contre les colonnes du téléphone au lieu de la zone sûre. Rendu final 720 s, `verify --all` sortie 0, 373 tests (`730a2bbb`) |
| **R5** | `730a2bbb` | 18 constats hors décisions du propriétaire, tous corrigés : la réserve de la page dans le rectangle (`keep: text_floor`, W 427,32) ; l'« Arrivé » qui surgit sur place et se repose sur f248, sa place vidée ; le fouetté sur la courbe de base, ≥ 80 px de flou exigés ; le crédit avec les tuiles et dans le souffle 2 ; l'étiquette qui roule ; une seule coque dans le fondu 9:16 / 1:1 ; la couture et le libellé du panneau de la fiche ; la poussée 16:9 qui garde la coque sur le sol et dans la zone graphique ; High@4.1 ; chaque verdict de verify câblé et testé (16 mutants tués). 399 tests (`11d0f6e1`) |
| **R6** | `11d0f6e1` | Aucun changement de code : les 18 corrections confirmées sur les pixels des MP4, 20 mutants tués sur des copies, les relevés de confidentialité du §9 ; trois remarques laissées ouvertes (§10.4) |
| **R7** | Les décisions du propriétaire après R5 (2026-10-20) | Le glissé et la suspension 9:16, la suspension 1:1 acceptés ; en 16:9 la poussée sur le sol (1,23×, le plus que la colonne de légendes permet), « Arrivé » et les tuiles à pleine largeur de colonne, la coupe franche du formulaire 15 s sans rideau ; le crédit de carte de l'app, entier jusqu'à f767 ; la carte de fin « Sur l’App Store et Google Play » · « myweli.com » et sa règle de publication (les deux apps en ligne). Le premier rendu échoue à verify (la carte agrandie prise pour la ligne 13:15, un disque rogné d'avant ce tour), corrigé dans les contrôles ; rendu final identique octet pour octet, six PASS ; 415 tests ; chaque nouveau contrôle vu rouge |

## 12. Questions ouvertes (décisions du propriétaire)

- **La bande-son, à l'oreille** (§10.1).
- **Publication** : la date, les canaux, et les conditions du §10.3 (les deux
  apps Pro en ligne, iOS et Android ; la licence de la photo de Maison Nala ;
  les conditions CARTO).
- **Cadrage, encore ouvert** (les autres points listés par R5 sont décidés le
  2026-10-20, §2) :
  - 16:9 : hors du formulaire de la 15 s, le bord du bandeau descend encore
    pendant les glissés de caméra du 30 s (vers « Créer », f384–392 : le
    défilement du formulaire bouge en même temps) ;
  - 9:16 : vers f700, le crédit de carte est loin de la carte (≈ 330 px
    au-dessus) ; il est juste au-dessus à la fin de la page.
- **N2** (§10.5), après la décision d'Apple sur le build en revue et avec son feu
  vert explicite.
