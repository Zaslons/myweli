# Lot 9 : l'hygiène, les outils et les tests — spec

| | |
|---|---|
| **Statut** | **Validé le 2026-10-22** — relu sur main (`d1e886e1`). Q1 (décision 33) : **le type `SalonId`** (« ce qui vaut le mieux à long terme ») ; Q2 (décision 34) : **e-mail et poussée Sentry** ; Q3 (décision 34) : **pas de suivi des performances pour l'instant** ; Q4 (décision 35) : **pas d'interrupteur** ; Q5 : **construire les trois composants et migrer tous les écrans maintenant** ; Q6 : **les pages publiques lèvent** ; Q7 : **supprimer la table avec ce lot** ; Q8 : **le reste tel qu'écrit**. Huit PR (§3). **PR A fusionnée le 2026-10-22** (#688 — B9.1, B9.5 — §9). **PR B fusionnée le 2026-10-22** (#689 — B9.6 — §10). **PR C fusionnée le 2026-10-22** (#690 — B9.7 — §11). **PR D fusionnée le 2026-10-25** (#691 — B9.11, B9.10 — §12 ; déploiement Vercel de production réussi, le plan du site liste 228 adresses). **PR E fusionnée le 2026-10-25** (#697 — B9.2–B9.4 — §13 ; 81 appliqué et relu le même jour, #698). **PR F1 fusionnée le 2026-10-25** (#699) (B9.8 : les trois briques et tous les écrans asynchrones — §14 ; Q9–Q12 en §8). **PR F2 fusionnée le 2026-10-25** (#700) (B9.8 : toutes les cartes sur `AppCard` — §2.7.3, §15 ; Q13–Q15 en §8). **PR F3 fusionnée le 2026-10-25** (#702) (B9.8 : toutes les puces sur `AppChip` — §2.7.4, §16 ; Q16–Q18 en §8). **PR G fusionnée et déployée le 2026-10-25** (#703 — B9.12 — §2.11, §17 ; révision `myweli-api-00047-55v`). |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-25 |
| **PRD ref / phase** | V1 — rien de visible n'est ajouté ; ce lot rend vrais les documents, les doublures de test, les lectures et les outils |
| **Module** | `docs/`, `mobile/` (doublures, formulaires, composants, mot du salon), `web/` (lectures, mot du salon), `backend/` (B9.12), `tool/` et `mobile/ios/tool/` (B9.2–B9.3), `infra/gcp/` (B9.4) |
| **Origine** | [BACKLOG.md](../BACKLOG.md) lot 9 : B9.1–B9.12 (décisions 33–35) |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-backend-guardrails ✓ · myweli-web-guardrails ✓ |

## 1. Le constat — relu sur le vrai chemin de code (main `d1e886e1`)

Onze points sont **réels** ; **B9.5 est déjà fait**. Cinq ont besoin d'une
correction par rapport au BACKLOG :
- **B9.1 est plus large** : quatorze entrées du journal sont encore 🟡, pas
  « plusieurs » ; six specs disent « construite » alors que leur PR est
  fusionnée ; l'index des specs garde cinq « non fusionné ».
- **B9.5 est fait** : les cinq PR Dependabot (#632–#636) sont fusionnées le
  2026-10-20, et le groupe `firebase` existe. Reste à **voir** la prochaine
  passe hebdomadaire ouvrir une seule PR Firebase.
- **B9.6 est plus grave** : la limite d'invitations du faux ne se remet
  jamais à zéro et ne connaît ni le salon ni l'adresse ; et le faux fait
  naître chaque salon avec un acompte à **30 %**, le serveur à **0**.
- **B9.7 a vieilli** : ce ne sont plus onze formulaires sans test, mais
  **six** ; `_NotesSection` est déjà sur `FieldErrors` — il lui manque le
  test, pas l'outil.
- **B9.11 est plus large et en partie faux** : « Mes salons » et les
  créneaux font la même chose ; et « seul un changement du contrat peut le
  déclencher » est **faux pour les pages publiques**, qui appellent l'API en
  direct et transforment toute réponse illisible en liste vide.

| # | Ce qui est vrai aujourd'hui | Où |
|---|---|---|
| B9.1 | **LAUNCH.md** dit encore qu'aucun build signé n'existe, que la production est arrêtée, que rien n'est dans TestFlight, que la version est 1.0.0 (build 536) ; son journal §6.2 s'arrête au 2026-10-14. **app-store-forms.md** attend encore la facturation, le salon démo et la voie compagnon (tous passés), montre « aucun build » dans TestFlight et « Soumettre » à faire ; sa §14 garde cinq lignes réglées depuis (#677, #678, #679, #682). **14 entrées** du journal datées du 13 au 16 octobre sont 🟡 alors que leur PR est fusionnée. **6 specs** disent « construite » (#563, #616, #665, #670–#671, #672–#673, #674–#675) ; `pro-rejoin-gate.md` dit « non fusionné » (#600 l'est) ; l'index garde 5 « non fusionné ». **Ce qui dépend d'App Store Connect** (la déclaration DSA « In Review », l'étiquette de confidentialité) ne se lit que là-bas — c'est le lot 10 | `LAUNCH.md:46-50, 119-121, 205-232, 290-294, 781-783, 1179-1237` ; `app-store-forms.md:5, 30, 34, 286-287, 847-857, 1198, 1397-1481, 1515, 1570-1582` ; `roadmap/entries/2026-10-1[3-6]-*.md` |
| B9.2 | `release_build.sh` range l'**IPA** par saveur (`MyWeli-$FLAVOUR.ipa`) mais **pas l'archive** (`Runner.xcarchive`, écrasée au build suivant ; copiée à la main) ni par build ; la commande Sentry imprimée n'envoie que les symboles Dart, **pas les dSYM** ; **aucun contrôle** que HEAD est `origin/main` ni que l'arbre est propre ; **aucune validation** avant l'envoi (sautée pour 587) | `tool/release_build.sh:137-154, 170, 201, 223-228` ; `app-store-forms.md:894, 903-910, 1016, 1191, 1357-1361` |
| B9.3 | `setup_flavours.rb` **supprime puis recrée** la phase de build (nouvel UUID à chaque passage) et **réécrit les schémas** — ce qui retire l'action « Run Prepare Flutter Framework Script » et `customLLDBInitFile` des schémas commis. L'en-tête dit « IDEMPOTENT » : c'est faux, et `mobile-ios-flavours.md` le note déjà | `mobile/ios/tool/setup_flavours.rb:14, 412-450` ; `consumer.xcscheme:8-25, 47, 75` |
| B9.4 | Les vérifications de disponibilité n'ont **pas** `--validate-ssl` ; **aucune** alerte d'expiration de certificat ni de latence ; la version mobile de Sentry est `package@version+build`, **sans** `set-commits` (pas de commits suspects) ; les seuils de taux d'erreur sont **reportés exprès** (pas de trafic) | `infra/gcp/80-uptime-checks.sh:58-68` ; `observability-error-reporting.md:244-252, 339-343, 418-425` ; `error_reporting.dart:61-66` |
| B9.5 | **Fait** : #632–#636 fusionnées le 2026-10-20 (equatable 3.0.0 compris) ; `dependabot.yml` a le groupe `firebase` (`firebase_*`, `_flutterfire_internals`). Aucune PR Firebase groupée n'est encore apparue | `.github/dependabot.yml:19-23` ; `mobile/pubspec.yaml:98` |
| B9.6 | **(a)** la limite d'invitations du faux est un compteur d'instance (`_invitesToday`) **jamais remis à zéro**, commun à tous les salons et adresses ; le serveur tient **deux seaux par jour UTC** (20 par salon, 3 par adresse). Deux tests relèvent la limite à 1 000 pour la contourner. **(b)** le faux répond l'acompte du modèle `Provider`, **0,30 par défaut**, et ses nouveaux salons copient le premier salon : l'étape « Acompte & annulation » paraît choisie ; le serveur crée chaque salon à **0,0**. **(c)** le cas « gérant sans salon » : `getMyProvider` et l'équipe le traitent déjà ; ce sont les faux du **catalogue** et des **employés** qui ne connaissent pas le salon (mise à jour sans salon, recherche dans tous les salons). **(d)** **12 identifiants** construits sur l'horloge dans 6 fichiers entrent en collision sous l'horloge gelée — dont l'invitation, dont l'id sert à l'accepter. **(e)** aucun interrupteur « marquer lu échoue » | `mock_pro_team_service.dart:25, 51, 142-149` ; `backend/lib/src/security/identity_limits.dart:101-104` ; `models/provider.dart:104, 297` ; `backend/lib/src/providers_repository.dart:762-763` ; `mock_pro_service.dart:300, 708, 761, 776-810` ; `mock_pro_artist_service.dart:46, 63-108` ; `mock_auth_service.dart:54-564` ; `mock_messaging_service.dart:56` |
| B9.7 | 17 écrans déclarent `FieldErrors` ; **11 ont un test** « l'erreur sous le champ ». **Sans test** : `_NotesSection` (déjà sur `FieldErrors`), la connexion admin, la connexion Pro, la fiche employé, la fiche prestation ; la connexion et le code par téléphone **client** (non routés). `_TagSheet` est **le seul** `errorText:` de `lib/` qui ne passe pas par `FieldErrors` : son erreur s'efface à chaque frappe au lieu de revérifier la règle, et la limite des 10 tags n'est pas testée | `core/forms/field_errors.dart:43-124` ; `client_detail_screen.dart:836-866, 1107-1206` |
| B9.8 | **Aucun** de `AppCard`, `AppChip`, `AppAsyncView` n'existe. Le thème donne déjà à `Card` et aux puces l'allure voulue (sauf la marge). Écrans : 27 `Card(`, ~83 conteneurs en forme de carte, 19 puces, 49 `LoadingIndicator(`, 47 `EmptyState(`, 46 « Réessayer » écrits à la main | SYSTEM §11.3 (`SYSTEM.md:555-557`) ; `app_theme.dart:395-449` |
| B9.9 | L'épingle R6 voit les lectures `.providerId` et les champs nommés ; **un identifiant de compte passé en position** lui échappe (la mutation M10 survit à l'épingle, un test de comportement l'attrape). **Rien sur main ne le fait.** ~32 signatures prennent un identifiant de salon en position | `test/unit/multi_salon_test.dart:351-453, 524-528` ; `r6-salon-id-pin.md:109-113, 166` |
| B9.10 | Pour un salon sans nom : **cinq** formes et une chaîne vide. App : « Salon » (accueil, carte de rendez-vous, invitation), « le salon » (report, confirmation, détail, export calendrier), « votre salon » (session Pro), « ce salon » (bandeau de révocation). Web : « Salon », « ce salon », « MyWeli » (export calendrier), et une chaîne vide qui affiche « — votre planning » sans rien devant. Aucune règle dans SYSTEM ni WEB-SYSTEM | `home_screen.dart:314` ; `appointment_card.dart:139` ; `reschedule_screen.dart:119` ; `pro_auth_provider.dart:332` ; `web/components/account/AppointmentCard.tsx:20` ; `web/lib/account/calendar.ts:21` ; `web/components/pro/AujourdhuiClient.tsx:127-133` |
| B9.11 | **Notifications** (client et Pro), **invitations**, **équipe**, **avis**, **visites**, **« Mes salons »** et **créneaux** : un 200 lisible sans sa liste devient `[]` ; `listClients` ne vérifie rien (un 200 `{}` ferait **planter** la recherche du rendez-vous manuel). **Pages publiques** : appel direct par `openapi-fetch` ; un 200 vide, un corps coupé ou une erreur donnent `[]` — **voulu** par `client.ts` (« dégrader en vide »), mais une page ISR régénérée vide **remplace** la bonne. Le contrat ne marque pas `items` comme requis pour `/me/notifications` ni `/sitemap/providers`. Deux tests figent le comportement actuel | `web/lib/api/account.ts:182` ; `web/lib/api/pro.ts:123, 183, 356, 794, 869, 914, 996` ; `web/lib/booking/client.ts:125` ; `web/lib/api/providers.ts:31-153` ; `web/lib/api/client.ts:9-11` ; `openapi.yaml:1013-1019, 1784-1802` |
| B9.12 | Plus aucun code ne lit ni n'écrit `provider_otp_codes`. **Mais** la révision précédente (`00045-8hs`, lot 6) l'efface à chaque suppression de compte Pro : tant qu'elle est la cible d'un retour arrière, supprimer la table rendrait ce retour dangereux. Ce serait la **première** migration `DROP` ; le test de réversibilité exige `// rollback-unsafe:` **après** la ligne `id:` | `backend/lib/src/db/migrations.dart:117, 1137` ; `test/db/migration_reversibility_test.dart:71, 124-202` |

## 2. Ce qui change

### 2.1 Les documents disent vrai (B9.1)
- **Maintenant** : les 14 entrées du journal passent à ✅ avec leur PR ;
  les 6 specs « construites » et `pro-rejoin-gate.md` disent « fusionnée » ;
  l'index aussi ; LAUNCH.md et app-store-forms.md racontent l'état réel
  (build 587 en revue, 0.0.1, production rétablie le 2026-10-06, salon démo
  fait, voie compagnon fusionnée et déployée, §14 nettoyée) ; le journal
  §6.2 rattrape jusqu'au 2026-10-22.
- **Ce qui attend le lot 10** : ce qui ne se lit que dans App Store Connect
  (DSA, étiquette de confidentialité, état exact de la revue). Ces lignes
  sont marquées « à relire dans App Store Connect », pas devinées.

### 2.2 Les outils de version iOS (B9.2, B9.3)
- **`release_build.sh`** :
  - **refuse** de construire si HEAD n'est pas `origin/main`, ou si l'arbre
    n'est pas propre ;
  - **range** l'archive par saveur **et** par build
    (`build/ios/archive/Runner-<saveur>-<build>.xcarchive`), comme l'IPA ;
  - **imprime** la commande Sentry avec les dSYM de l'archive ;
  - **valide** l'IPA (`xcrun altool --validate-app`) avant d'imprimer la
    commande d'envoi ; un échec arrête tout.
- **`setup_flavours.rb`** : met à jour la phase et les schémas **sur
  place** (trouve la phase par son nom, garde son UUID ; garde les actions
  et réglages existants), et n'ajoute plus rien à un second passage.
- **Les tests** : un test d'infrastructure pour chaque refus du script
  (branche, arbre sale) et pour la commande imprimée ; un test que deux
  passages de `setup_flavours.rb` sur un projet copié ne changent rien.

### 2.3 L'observabilité (B9.4, décision 34)
- **`--validate-ssl`** sur les deux vérifications de disponibilité.
- **Deux alertes** : certificat qui expire dans moins de 14 jours ; latence
  au-dessus de ~3 s pendant 15 min. Même canal que les autres (e-mail au
  propriétaire, et la poussée de Sentry pour les erreurs).
- **Les commits suspects** : `sentry-cli releases set-commits` pour la
  version mobile, depuis `release_build.sh`.
- **Les seuils de taux d'erreur** restent reportés : sans trafic réel, un
  seuil serait deviné.
- **Lancer les scripts** sur GCP est une modification du cloud : je
  demande avant, comme toujours.

### 2.4 Dependabot (B9.5)
- **Rien à construire.** Une case « à voir » : la prochaine passe ouvre
  une seule PR Firebase. Si elle en ouvre plusieurs, le groupe est à
  corriger.

### 2.5 Les doublures disent vrai (B9.6, décision 35)
- **Les invitations** : deux seaux par jour **`AppClock`**, comme le serveur
  (20 par salon, 3 par adresse) ; les deux tests qui relevaient la limite
  n'en ont plus besoin.
- **L'acompte** : un salon né dans le faux part à **0 %**, acompte désactivé,
  comme sur le serveur ; le modèle `Provider` garde 0,30 pour les salons
  semés de la démo.
- **Le gérant sans salon** : les faux du catalogue et des employés trouvent
  le salon comme le serveur (la session, puis l'adhésion) et refusent ce
  qui n'est pas à ce salon.
- **Les identifiants** : un compteur partagé par les faux
  (`MockIds.next('service')`), qui ne dépend plus de l'horloge ; les 12
  endroits l'utilisent.
- **« Marquer lu échoue »** : non (recommandé) — déjà figé par 32 tests.

### 2.6 Les formulaires prouvés (B9.7)
- **`_TagSheet` passe sur `FieldErrors`** : l'erreur revérifie la règle à
  chaque frappe au lieu de s'effacer ; l'échec d'enregistrement devient une
  erreur du champ.
- **Un test « l'erreur sous le champ »** pour `_NotesSection`, la connexion
  admin, la connexion Pro, la fiche employé, la fiche prestation, et la
  limite des 10 tags. Les deux écrans de téléphone client, non routés,
  restent hors champ (ils attendent le SMS).

### 2.7 Les composants partagés (B9.8)
- **Construire `AppCard`, `AppChip` et `AppAsyncView<T>`** comme SYSTEM
  §11.3 les décrit, avec leurs tests et une photo chacun.
- **Migrer tous les écrans maintenant** (Q5) : chaque `Card(`, chaque
  puce et chaque trio chargement/erreur/vide écrit à la main passent aux
  composants. Une épingle interdit d'en réécrire un.
- **Les photos** changent en nombre : chacune est regardée, une par une,
  avant d'être enregistrée. Une différence qui n'est pas voulue est un
  défaut à corriger, pas une photo à refaire.

#### 2.7.1 Mesuré avant de construire (2026-10-25, `main` à `de4f241a`)

- **55 fichiers** : 27 `Card(` ; **111** boîtes en forme de carte (couleur +
  rayon) dont **30** sont déjà exactement la carte du système (`secondary`,
  `radiusXL`, sans bordure), 5 la même avec bordure, **17** en
  `secondary` + `radiusLarge` (9 avec bordure), et le reste des tuiles
  `surface` posées dans une carte, des poignées et pastilles, des bandeaux
  teintés — **pas des cartes** ; 19 puces (4 `FilterChip`, 9 `ChoiceChip`,
  5 `Chip`, 1 `ActionChip`) dans 12 fichiers ; 49 `LoadingIndicator(`,
  48 `EmptyState(`, 30 « Réessayer ».
- **Le trio écrit à la main** suit partout l'ordre d'`AdminDataTable`
  (la référence de §12) : chargement **sans rien** → l'attente ; erreur
  **sans rien** → l'erreur et « Réessayer » ; vide → `EmptyState` ;
  sinon le contenu — les données restent pendant un rechargement et après
  un rafraîchissement échoué. `AppAsyncView` reprend cet ordre.
- **L'erreur n'a pas de forme commune** : « Chargement impossible » ×11,
  « Une erreur est survenue » ×6, d'autres ; l'icône `wifi_off` ou
  `error_outline` selon l'écran, pas selon la panne.
- **Les photos** : 55 golden ; ceux des écrans touchés changent si une
  forme change (Q10, Q11). Elles se refont par le flux « Goldens —
  regenerate » (Linux), et chacune est regardée avant d'être enregistrée.

**Questions (Q9–Q12)** — posées le 2026-10-25, réponses en §8.

#### 2.7.2 La forme retenue (après Q9–Q12)

**Trois PR** (Q12) : **F1** construit les trois briques — `AppAsyncView<T>`,
`AppCard` (sans encore migrer les cartes) et le jeu de squelettes — et migre
**tous les écrans asynchrones** ; **F2** migre les cartes ; **F3** les puces.

- **`AppAsyncView<T>`** (`widgets/common/app_async_view.dart`) — l'ordre
  d'`AdminDataTable` : chargement **sans rien** → `loading` ; erreur
  **sans rien** → l'erreur commune ; vide → `empty` ; sinon `builder`. Les
  données restent pendant un rechargement et après un rafraîchissement
  échoué. **`loading`, `empty` et `builder` sont obligatoires** : un écran
  ne peut pas en oublier un. `onRetry` est facultatif : nul, l'erreur n'offre
  pas de « Réessayer » (§12 : une sortie qui ne peut pas aboutir n'en est pas
  une).
- **L'erreur commune** (Q9, `AppErrorView`) : « **Chargement impossible** »
  en titre ; en dessous, la phrase de la panne (« Pas de connexion.
  Réessayez. » ou « Une erreur est survenue. Réessayez. », ou celle d'un code
  qui en a une) ; l'icône **`wifi_off` seulement sans connexion**, sinon
  `error_outline` ; « Réessayer » quand l'écran peut réessayer.
- **Les squelettes** (Q11, `widgets/common/app_skeleton.dart`) —
  **immobiles** : une pulsation est une boucle `repeat()`, qui devrait lire
  la réduction des mouvements (§9.1) et demanderait une durée qu'aucun des
  cinq jetons ne nomme ; ajoutée plus tard si voulue, ce sera une décision
  de jeton (doc, Dart, web). Les barres en `surfaceVariant`, `radiusSmall`,
  **toujours sur une carte** (`secondary`) — sur le fond de page,
  `surfaceVariant` est presque invisible. Une étiquette pour les lecteurs
  d'écran (« Chargement… »), le reste exclu, comme le squelette du Profil
  déjà en place. Un jeu de formes : la liste de cartes, la liste de lignes,
  la fiche (détail), le formulaire, la grille de photos ; chaque écran
  prend la forme de son contenu.
- **Le spinner reste** là où la forme n'est pas connue (§12) : la boîte de
  dialogue bloquante, les transitions « on quitte » et les portes de
  session — dit dans le code à chaque fois.
- **`AppCard`** (`widgets/common/app_card.dart`) — `secondary`,
  `radiusXL`, élévation 0, `spacingM` ; `onTap` avec l'ondulation coupée au
  rayon ; une variante `outlined` (`borderStrong`) pour F2.
- **Les épingles** : plus de `LoadingIndicator(` dans `lib/screens` hors
  d'une liste nommée (les cas « forme inconnue »), et plus d'erreur de
  chargement écrite à la main (`actionText: 'Réessayer'` hors des briques).

#### 2.7.3 F2 — les cartes (mesuré le 2026-10-25, sur F1)

**Ce que §2.7.1 a mal compté.** Les « 30 cartes déjà exactement celles du
système » ne l'étaient pas : l'inventaire ne regardait que la couleur, le
rayon et la bordure, et **presque toutes portent une ombre**
(`boxShadow: AppTheme.elevation1`) — que SYSTEM §8 réserve à ce qui flotte
(menus, feuilles, la barre du bas) : « les cartes ont l'élévation 0 ».

**Ce qui est une carte** — relu site par site, hors `screens/provider/features/`
(V2/V3, masqués : on ne les polit pas, §Scope) et hors console (ses cartes à
bordure sont l'idiome du bureau, SYSTEM §11.2) :
- **27 `Card(` Material** dans 11 fichiers (dont 15 sur le Profil Pro),
  presque toutes autour d'un `ListTile` ;
- **31 cartes dessinées à la main** : 23 de contenu (le détail d'un
  rendez-vous, le récapitulatif avant paiement, la tête du salon dans la
  réservation, les quatre sections de l'acompte et les quatre de la
  disponibilité, celle de mes
  données, la fiche du salon, le total des revenus, le résumé des avis, les
  places de l'équipe et de l'offre, un document de vérification, une
  invitation, le calendrier Pro, les chiffres de l'accueil Pro, le
  rendez-vous déplacé, les préférences) et 8 qu'on touche en entier (un
  rendez-vous, sa version compacte, une notification, un salon en liste et
  en grille, un employé, un service, un raccourci de l'accueil Pro) ;
- **2 cartes qui sont des contrôles** : une étape de la réservation
  (ouverte / fermée) et un rôle à choisir dans l'invitation.

**Ce que F2 en fait** (Q10 : les normaliser) :
- **Toutes deviennent `AppCard`** : `secondary`, `radiusXL`, **sans ombre**,
  **sans bordure** (SYSTEM §3.1 : la marche de surface suffit), `spacingM`
  dedans — `spacingL` sur six cartes passe à `spacingM`. Un
  rembourrage autre n'est gardé que s'il a une raison écrite : zéro autour
  d'une liste de lignes ou d'une photo bord à bord, l'arithmétique du
  calendrier (`spacingS`, A14a §2.1), le rembourrage calculé des chiffres
  de l'accueil Pro. La `margin` de 4 que `Card` ajoutait en silence
  disparaît : l'écart entre deux cartes est celui de leur liste.
- **Une carte qu'on touche** l'est en entier (`onTap`) : l'ondulation coupée
  au rayon, **un bouton pour un lecteur d'écran** — sept d'entre elles
  étaient un `GestureDetector` muet. Un contrôle à l'intérieur (le cœur des
  favoris d'un salon) **reste à part** : `AppCard` fait de la carte un nœud
  conteneur, pas une fusion — la fusion de F1 l'aurait avalé.
- **Une carte-contrôle** est `outlined` (le trait `borderStrong`) et, choisie,
  `selected` : le trait passe à `primary`, 2 px, la carte reste blanche (Q13).
  Pas seulement une couleur : la
  carte est annoncée « sélectionnée », et l'icône radio ou l'état ouvert le
  disent aussi (SYSTEM §13).
- **Ce qui reste** : les ombres de ce qui flotte (les repères de la carte, la
  poignée de l'avant/après, le logo sur la couverture, les anneaux des
  stories) ; la console ; les écrans V2/V3 ; et `HighlightStories`, que rien
  n'affiche — supprimé plutôt qu'exempté.
- **Une épingle** sur `lib/` : plus de `Card(` ; plus de boîte `secondary` à
  `radiusXL`/`radiusLarge` dessinée à la main ; plus d'`elevation1`/`2` sur
  une carte — hors liste nommée, avec sa raison.

**Questions (Q13–Q15)** — posées le 2026-10-25, réponses en §8 : le trait
`primary` de 2 px sans fond ; la barre « Total » garde son ombre ;
`spacingM` partout.

#### 2.7.4 F3 — les puces (mesuré le 2026-10-25, sur F2)

**Ce qui est une puce**, relu site par site (hors V2/V3, hors console) :
- **14 puces qu'on choisit** — 13 `FilterChip`/`ChoiceChip` (la journée, les
  clients et leurs tags, l'acompte, la disponibilité, le service, les
  catégories de l'accueil, la longueur, les créneaux) et les filtres de la
  recherche, dessinés à la main **sans rien dire** à un lecteur d'écran de
  celui qui est actif ;
- **des tags** sur la fiche d'un client, et **une action** (« + Tags » /
  « Modifier ») ;
- **les statuts**, dessinés de **trois façons** pour la même chose : une boîte
  teintée au `radiusSmall` (la carte d'un rendez-vous, la journée, « Réservé
  par votre salon »), une pastille teintée (la tuile compacte), et une `Chip`
  Material **pleine** de la couleur du statut, l'étiquette en blanc littéral
  (le calendrier et la liste Pro) — ou sans couleur d'étiquette du tout ;
  plus les badges : « Réservation vérifiée », « Nouveau », ceux d'une ligne
  de client, et le rôle d'un membre (`TeamRoleChip`).

**Un défaut, mesuré** : le statut du détail d'un rendez-vous Pro est une
`Chip` pleine de la couleur du statut **sans couleur d'étiquette** ; le thème
lui donne l'encre `textPrimary`. « Confirmé », le plus courant, est donc
#1A1A1A sur `info` #1A1A2E : **1,02:1** — noir sur noir ; « Annulé » 1,7:1.

**Ce que F3 construit** — `AppChip` (`widgets/common/app_chip.dart`), comme
SYSTEM §11.3 le décrit, `radiusPill` :
- **à choisir** (`AppChip.choice`) : sur la `ChoiceChip` de Material, donc
  « sélectionné » annoncé, le focus et la cible de 48 ; **pleine** (`primary`,
  étiquette blanche) quand elle est choisie, **soulignée** (`borderStrong`)
  sinon — ce que `chipTheme` dessine déjà, sans les surcharges qui s'en
  écartaient ;
- **un tag** (`AppChip.tag`) : soulignée, sans action ; **une action**
  (`AppChip.action`) : soulignée, une icône en tête ;
- **un statut** (`AppChip.status`) : la teinte du ton à 12 %, l'étiquette dans
  la couleur du ton — mesuré : succès 7,1:1, attention 5,3:1, erreur 7,4:1,
  info 12,5:1 sur `background` (le pire des deux fonds) ; un ton « or » garde
  l'étiquette à l'encre (l'or n'est pas un texte, B7.1). Sans action, une
  étiquette pour un lecteur d'écran.
- **Une épingle** : plus de `FilterChip`/`ChoiceChip`/`ActionChip`/`Chip(` en
  dehors d'`app_chip.dart`, plus de pastille de statut dessinée à la main.

**Ce qui reste** : le champ de début/fin du sélecteur d'heures (une case à
deux lignes, pas une puce, A14b) ; les étiquettes posées sur une photo
(« Couverture », « Avant ») ; le sélecteur de commune (`CommunePill`, un
bouton) ; la console (`StatusChip`, idiome du bureau, comme en F2) ; les écrans
V2/V3.

**Questions (Q16–Q18)** — posées le 2026-10-25, réponses en §8 : la coche
partout ; les créneaux pleins ; une seule pastille teintée, rôles compris.

### 2.8 Le type `SalonId` (B9.9, décision 33)
- **Ta décision** : ce qui vaut le mieux à long terme, donc **le type**.
  L'épingle ne voit pas un identifiant de compte passé en position ; le
  compilateur, lui, le refusera.
- **`extension type const SalonId(String value)`** : sans coût à
  l'exécution ; un `String` ne passe plus là où un `SalonId` est attendu.
- **Les ~32 signatures** qui prennent un identifiant de salon prennent un
  `SalonId` (services, fournisseurs, écrans). **Il naît** à peu d'endroits :
  `ProAuthProvider.activeSalonId`, les modèles lus du serveur (le `providerId`
  d'un rendez-vous, l'`id` d'un salon), les routes.
- **Une épingle** limite les endroits qui ont le droit d'écrire `SalonId(` ;
  un `SalonId(account.id)` devient visible en relecture et refusé par le
  test.
- L'épingle R6 actuelle reste : elle couvre les lectures `.providerId`.

**Relu le 2026-10-25, avant de construire (PR H)**, sur main (`4249d87c`).
« ~32 signatures » comptait les interfaces Pro. L'espace réel est plus
grand, et il a deux moitiés :
- **Les déclarations** (`String providerId` / `salonId`, hors V2/V3) :
  36 dans les interfaces (8 fichiers), 57 dans les doublures, 37 dans les
  services API, 57 dans les fournisseurs (19 fichiers), 23 dans les écrans,
  4 dans les widgets, 3 dans `core/` — **217**, sans compter les appels — et
  **13 champs de modèle** : `Provider.id`, `Appointment.providerId`,
  `Review.providerId`, `Service.providerId`, `Artist.providerId`,
  `Availability.providerId`, `TeamMember.providerId`,
  `TeamInvitation.providerId`, `ProviderUser.providerId`, et les `salonId`
  de `SalonMembershipInfo`, `ProMembership`, `SalonMarket`, `SalonFacts`.
  Environ **120 fichiers d'essai** passent un identifiant de salon.
- **La moitié Pro** — le salon *qui agit* (`pro_*` services, le résolveur
  `activeSalonId`, l'équipe, les adhésions) : c'est **là que vit l'angle
  mort R6** (un identifiant de *compte* en position).
- **La moitié client** — un salon *public* (les favoris, la réservation, les
  avis, `getProviderById`). L'angle mort R6 n'y est pas ; un autre l'est :
  **deux `String` côte à côte**, `addFavorite(String userId, String
  providerId)` — deux arguments inversés compilent.

**La forme**, quelle que soit la portée : `extension type const
SalonId(String value)`, sans coût à l'exécution (un `String` à
l'exécution : le JSON, l'égalité d'`Equatable` et les clés de `Map` ne
changent pas). **Où il naît** : le `fromJson` des modèles, le résolveur
(`ProAuthProvider`), les paramètres des routes, les données des doublures ;
les essais librement. Ailleurs, `SalonId(` fait rougir l'épingle.

**Hors portée** : le web (TypeScript, sa propre couche BFF) ; un type
`AccountId` pour l'autre sens (un salon passé là où un compte est attendu :
aucun cas connu).

**Questions (Q19–Q20)** — en §8 : **chaque identifiant de salon, en deux
PR**, et **`implements String`**.

**H1 — la moitié Pro** (le salon qui agit) :
- **Le type** : `core/utils/salon_id.dart`, `extension type const
  SalonId(String value) implements String` — hors de `core/theme/`, que la
  porte du miroir des jetons du web lit (leçon de F3).
- **Le résolveur** : `ProAuthProvider.activeSalonId` rend un `SalonId?`, et
  `resolveActingSalonId` avec lui ; le salon choisi (`_selectedSalonId`,
  `setSelectedProviderSalon`) en est un.
- **Les interfaces** : `ProServiceInterface` (ses 18 places de salon,
  `getMyProvider({salonId})` compris), `ProClientsServiceInterface` (8),
  `ProArtistServiceInterface` (2), `SubscriptionServiceInterface` (1),
  `AuthServiceInterface.setSelectedProviderSalon` — et leurs doublures et
  services API, les fournisseurs Pro et les écrans Pro qui les appellent.
- **Les modèles Pro** : `ProviderUser.providerId` (le salon par défaut : un
  vrai salon, le mauvais après un changement — l'épingle R6 garde ce
  cas-là), `SalonMembershipInfo.salonId`, `ProMembership.salonId`,
  `TeamMember.providerId`, `TeamInvitation.providerId`,
  `SalonMarket.salonId`, `SalonFacts.salonId` — nés dans leur `fromJson`.
- **H2 ensuite** : la réservation et ses créneaux, les avis, les favoris,
  `getProviderById`, et `Provider.id`, `Appointment.providerId`,
  `Review.providerId`, `Service.providerId`, `Artist.providerId`,
  `Availability.providerId`. Entre les deux, un `SalonId` passe dans leurs
  `String` (Q20) : rien ne casse au milieu.

**Les essais de H1, rouges d'abord** (`test/unit/salon_id_type_test.dart`) :
- aucune place de salon n'est un `String` dans les interfaces de H1, ni dans
  les champs de ses modèles ; le résolveur rend un `SalonId?` ;
- **l'épingle de naissance** : sous `lib/`, `SalonId(` n'apparaît que dans
  les fichiers permis (les `fromJson`, le résolveur, les routes, les
  données des doublures) ;
- **la mutation M10 de R6** (`createService(authProvider.provider!.id, …)`,
  en position) : la mutation qui survivait à l'épingle — **le compilateur la
  refuse** (`flutter analyze`, `argument_type_not_assignable`).

### 2.9 Un seul mot pour un salon sans nom (B9.10)
- **La règle** (SYSTEM §17, WEB-SYSTEM) : un salon sans nom s'écrit
  « **Salon** » comme titre ; dans une phrase, « **le salon** » côté client
  et « **votre salon** » côté Pro (le salon de la session). Jamais une
  chaîne vide ; jamais « MyWeli ».
- **Une constante par surface** (`kUnnamedSalon*` dans l'app,
  `UNNAMED_SALON*` sur le web), et une épingle qui interdit ces littéraux
  ailleurs.
- « — votre planning » sans rien devant devient « Votre planning ».

### 2.10 Les lectures web exigent leur liste (B9.11)
- **Comptes et Pro** : notifications, invitations, équipe, avis, visites,
  « Mes salons », créneaux et `listClients` exigent leur tableau ; sinon,
  une lecture échouée (`status: 0`), comme #630 pour les exports. Les deux
  tests qui figeaient `[]` s'inversent.
- **Pages publiques** : une réponse illisible **lève** au lieu de rendre
  `[]` (Q6). Une vraie liste vide reste une liste vide.
  - **À la régénération (ISR)**, Next garde la dernière bonne page au lieu
    de publier une page vide, et réessaie plus tard.
  - **Au build**, une API illisible fait échouer le build : le déploiement
    précédent reste en ligne. Aujourd'hui, le même build passe et publie un
    plan du site sans salons.
- **Le contrat** : `items` devient requis pour `/me/notifications` et
  `/sitemap/providers` (le serveur l'envoie déjà toujours).

### 2.11 La table orpheline (B9.12)
- **La migration `0043`** : `DROP TABLE IF EXISTS provider_otp_codes`, avec
  `// rollback-unsafe:` après son `id:`.
- **Quand** : avec le déploiement de ce lot. Après lui, la cible d'un
  retour arrière est `eca4db6`, qui ne lit plus la table (Q7).

**Relu le 2026-10-25, avant de construire (PR G)** :
- **Sur main** (`dfdc4178`) : la table n'est plus nommée que par sa création
  (`0003`, `migrations.dart:117`) et par l'épingle de B8.5 qui interdit son
  nom aux deux magasins Pro (`batch8_phone_signin_contract_test.dart:38`).
- **En production** (lu, rien changé) : la révision servie est
  `myweli-api-00046-bzg`, 100 % du trafic, étiquette `commit: eca4db6` —
  B8.5. **Dans `eca4db6`, seule la création la nomme** : ni lecture, ni
  écriture, ni effacement. La révision d'avant, `00045-8hs` (lot 6), l'efface
  à chaque suppression de compte Pro.
- **La chaîne** : `staging.state` dit `absent`, donc une fusion **construit**
  l'image et ne déploie rien ; la migration ne tourne qu'au déploiement de
  production, sur ton accord. Elle tourne au démarrage, sous le verrou du
  schéma et **avant** que le port s'ouvre : si elle échoue (le verrou
  attendu plus de 3 s), la révision n'est jamais prête et le trafic reste
  sur `eca4db6`.

**Ce que G construit** :
- **`0043_drop_provider_otp_codes`** : `DROP TABLE IF EXISTS
  provider_otp_codes`. Son `// rollback-unsafe:` dit le seul retour qui
  casse : vers `00045-8hs` ou plus ancien, où supprimer un compte Pro
  rendrait 500. Vers `eca4db6`, la cible d'un retour d'un cran, rien ne
  casse. **Le premier `DROP TABLE`** de la liste.
- **Les essais, rouges d'abord** :
  - contre un vrai Postgres : après les migrations, `to_regclass` ne trouve
    plus la table, et les rejouer ne change rien (`IF EXISTS`) ;
  - sur la source : hors de `migrations.dart`, aucun fichier de `lib/`,
    `routes/` ou `bin/` ne nomme la table, et la dernière migration qui la
    nomme la supprime, déclarée.
- **Le modèle de menace** (BACKEND.md §7) : la ligne T80 dit la table
  « gardée » ; elle dit maintenant qu'elle est partie avec `0043`.

**Le déploiement** — demandé à part, après la fusion : la production, avec
l'image que la fusion aura construite (`image_tag`), comme toujours. **Vu
après** : la révision nouvelle prête, à 100 %, son étiquette `commit` celle
de la fusion — prête veut dire que chaque migration de sa liste est écrite
dans `schema_migrations`, `0043` comprise, puisqu'une migration qui échoue
empêche le démarrage.

## 3. La livraison

**Huit PR**, dans cet ordre ; seule (G) demande un déploiement du serveur
(que tu approuves) :
- **(A) Les documents disent vrai** : B9.1 (docs seulement).
- **(B) Les doublures disent vrai** : B9.6 (app).
- **(C) Les formulaires prouvés** : B9.7 (app).
- **(D) Lire juste, nommer juste** : B9.11 et B9.10 (web, app, contrat).
- **(E) Les outils de version et d'alerte** : B9.2, B9.3, B9.4 (scripts ; leur
  exécution sur GCP est demandée à part).
- **(F) Les composants partagés** : B9.8 (app ; nouvelles photos).
- **(G) La table orpheline** : B9.12 (serveur, **déploiement**).
- **(H) Le type `SalonId`** : B9.9 (app) — **en deux PR** (Q19) : **H1** la
  moitié Pro, **H2** la moitié client.
- **B9.5** : la case « à voir », dans le BACKLOG.

## 4. Le contrat

- **B9.11** : `items` requis pour `/me/notifications` et `/sitemap/providers`.
  Aucun changement du serveur : il les envoie déjà.

## 5. La sécurité

- **B9.2** : refuser un build qui n'est pas `origin/main` ferme la porte à un
  binaire envoyé à Apple depuis une branche non relue.
- **B9.12** : retirer une table qui contenait des codes (hachés) ; elle est
  vide depuis #685.

## 6. Les tests (rouges d'abord)

- Chaque point a son test rouge d'abord, et les mutations sur le travail
  enregistré, comme toujours.
- Les scripts (B9.2–B9.4) ont des tests d'infrastructure, comme les scripts
  `infra/gcp` existants.

## 7. Les mots

- **B9.10** : « Salon » (titre) ; « le salon » (client, dans une phrase) ;
  « votre salon » (Pro) ; « Votre planning » (le titre du collaborateur sans
  nom de salon).
- **B9.7** : la limite des tags garde sa phrase actuelle.

## 8. Questions au propriétaire

- **Q1 (décision 33)** — `SalonId` : **accepter la limite documentée**
  (recommandé), ou un type d'extension sur ~32 signatures ?
- **Q2 (décision 34)** — Les alertes : **e-mail et poussée Sentry**
  (recommandé), ou un relais WhatsApp à construire ?
- **Q3 (décision 34)** — Le suivi des performances de Sentry (payant) :
  **non pour l'instant** (recommandé), ou oui ?
- **Q4 (décision 35)** — Un interrupteur « marquer lu échoue » dans le faux :
  **non** (recommandé), ou oui ?
- **Q5** — Les composants partagés : **les construire, interdire le neuf
  écrit à la main, adopter en touchant** (recommandé), ou migrer tous les
  écrans maintenant ?
- **Q6** — Les pages publiques devant une réponse illisible : **lever, pour
  que l'ISR garde la dernière bonne page** (recommandé), ou garder « dégrader
  en vide » ?
- **Q7** — La table orpheline : **la supprimer avec le déploiement de ce
  lot** (recommandé), ou attendre plus longtemps ?
- **Q8** — Le reste, tel qu'écrit : les sept PR, la règle du salon sans nom,
  B9.1 sans ce qui dépend d'App Store Connect ?
- **Q9** (2026-10-25) — L'erreur d'`AppAsyncView` : **une seule forme**
  (recommandé), ou le titre et l'icône de chaque écran ?
- **Q10** — Les cartes qui s'écartent du système : **les normaliser**
  (recommandé), ou ne migrer que ce qui y est déjà ?
- **Q11** — Le chargement : garder celui de chaque écran (recommandé), ou
  **ajouter les squelettes maintenant** là où la forme est connue ?
- **Q12** — La livraison : **trois PR** (recommandé), ou une ?

**Décisions (2026-10-22).** Q2, Q3, Q4, Q6, Q7, Q8 : les recommandations.
Q1 : « ce qui vaut le mieux à long terme » — le type `SalonId` (§2.8, PR H).
Q5 : la recommandation — tout migrer maintenant (§2.7).

**Décisions (2026-10-25).** Q9 : **une seule erreur** ; Q10 : **normaliser
les vraies cartes** ; Q11 : **les squelettes maintenant** (pas la
recommandation) ; Q12 : **trois PR**. La forme retenue : §2.7.2.
- **Q13** (2026-10-25, F2) — Une carte-contrôle choisie : **un trait
  `primary` de 2 px sur la carte blanche** (recommandé), ou le trait et un
  fond gris (`surfaceVariant`), comme la carte de rôle aujourd'hui ?
- **Q14** — La barre « Total » épinglée de la réservation : **une barre
  ancrée, qui garde son ombre** (recommandé), ou une carte, aplatie ?
- **Q15** — Les six cartes à `spacingL` : **`spacingM`, comme §11.3**
  (recommandé), ou les garder à `spacingL` ?

**Décisions (2026-10-25, F2).** Q13, Q14, Q15 : les recommandations. La
forme retenue : §2.7.3.
- **Q16** (2026-10-25, F3) — Une puce choisie : **la coche partout**
  (recommandé — elle prend la place de l'icône ; la sélection ne tient pas
  qu'à la couleur), ou le seul fond ?
- **Q17** — Les créneaux, seule puce choisie dessinée en teinte claire :
  **pleins comme les autres** (recommandé), ou garder la teinte ?
- **Q18** — Les statuts et badges : **une seule pastille teintée partout**
  (recommandé — les puces pleines du calendrier et de la liste Pro, les
  badges à coins carrés et les rôles d'équipe compris), ou garder les puces
  pleines de la liste Pro ?

**Décisions (2026-10-25, F3).** Q16, Q17, Q18 : les recommandations. La
forme retenue : §2.7.4.
- **Q19** (2026-10-25, H) — Jusqu'où va `SalonId` (~217 déclarations,
  13 champs de modèle, ~120 fichiers d'essai) : **chaque identifiant de
  salon, en deux PR** (recommandé — H1 la moitié Pro, qui ferme l'angle mort
  R6 ; H2 la moitié client, qui attrape aussi deux arguments inversés ; à la
  fin, aucun identifiant de salon n'est un `String` nu), tout en une PR, ou
  la moitié Pro seule ?
- **Q20** — Un `SalonId` passe-t-il encore là où un `String` est attendu :
  **oui, `implements String`** (recommandé — les adresses, le JSON, les clés
  de `Map` ne changent pas ; seul un `String` nu ne remplit plus une place de
  salon, le sens de R6), ou opaque (`.value` partout, pour un sens sans
  défaut connu) ?

**Décisions (2026-10-25, H).** Q19, Q20 : les recommandations. Deux PR,
**H1** puis **H2** ; `extension type const SalonId(String value) implements
String`.

## 9. PR A construite (B9.1, B9.5) — ce qui a été vu

**Comme écrit**, avec ces écarts, chacun vu en route :
- **Le journal** : **33** entrées 🟡, pas quatorze. Chacune est lue depuis
  git : la PR qui l'a ajoutée, si sa fusion est dans le build 587 (`main`
  à `e105aabd`), si sa part serveur est dans une image déployée.
  - **20 passent à 🟢** : fusionnées, et en ligne ou dans le 587.
  - **13 restent 🟡**, avec la vraie raison : leur part app part avec 0.0.2.
  - Les vérifications sur appareil renvoient à B0.2 ; la clé de carte du
    web reste hors de Vercel, exprès (map-basemap-key.md §7) — l'entrée ne
    le dit plus « à faire ».
  - **Vu au passage** : l'entrée du déploiement du lot 8 portait ✅ ; la
    règle du dossier est 🟢.
- **Les specs** : huit lignes de statut et cinq lignes de l'index disent
  « fusionnée », chaque PR vérifiée fusionnée — et sur quelles surfaces,
  pour dire juste « le web en ligne, l'app avec 0.0.2 ».
- **LAUNCH.md et app-store-forms.md** : des notes datées du 2026-10-22 plutôt
  qu'une histoire réécrite.
  - **Le déploiement de la voie compagnon avant la soumission** est lu dans
    l'historique des déploiements : celui de production du 2026-10-07 part
    d'un `main` qui contient #551.
  - **Ce qu'App Store Connect seul peut dire** (l'issue de la DSA, ce que dit
    l'étiquette de confidentialité, les essais du jour de la soumission)
    reste marqué « à relire au lot 10 », pas deviné.
- **B9.5** : rien à construire ; la case « à voir » est dans le BACKLOG.

**Vérifié** : le test du document de lancement et les tests
d'infrastructure du serveur passent ; `tool/roadmap-log.sh` rend le journal
entier.


## 10. PR B construite (B9.6) — ce qui a été vu

**Comme écrit**, et plus large que le constat, chaque écart lu sur le vrai
chemin du serveur :
- **Les invitations** : les deux seaux du serveur, par jour UTC sur
  `AppClock` (`MockData.inviteBuckets`, vidés avec l'équipe) — 20 par salon,
  puis 3 par salon **et** adresse. Comme le serveur : le seau du salon
  d'abord (une invitation que l'adresse refuse compte déjà dans celui du
  salon), chaque tentative comptée, et **les alias d'une personne partagent
  un seau** (`+étiquette`, les points de Gmail, `googlemail.com` —
  `canonicalInviteAddress`). Le réglage `maxInvitesPerDay` disparaît : les
  trois tests qui s'en servaient (dont les deux à 1 000) n'en ont plus
  besoin.
- **Le salon neuf** : pas seulement l'acompte. Un salon né dans le faux
  (inscription, « Ajouter un salon ») **copiait Salon Excellence entier** :
  ses prestations, ses photos, sa note de 4,5, ses horaires, son acompte de
  30 %. `MockData.newSalon` le fait comme le serveur
  (`draftSalonDocument`) : vide, 0 %, acompte désactivé, la catégorie
  du serveur (`categoryFor`). **Vu au passage** : les graines donnaient à
  tout salon inconnu le barbier de provider4 et les prestations de
  provider3 ; elles n'en donnent plus.
- **Le catalogue** : les écritures répondaient « succès » sans rien garder,
  et la lecture rendait la graine. Il vit maintenant dans `MockData.providers`
  — **un seul magasin**, que l'écran Pro relit et où le client réserve, comme
  sur le serveur — et `resetTeam` le remet à la graine
  (`resetCatalogue`). La mise à jour est le `PATCH` du serveur : les clés
  modifiables que porte la requête changent, le reste demeure (le faux
  plantait sans `providerId` dans la requête).
- **Le salon où l'on agit** : un seul résolveur (`mock_session.dart`) pour
  l'équipe, le catalogue et les employés — la sélection, le salon du
  compte, l'adhésion en cache, puis **la première adhésion active**, comme
  `GET /me/provider` (le faux de l'équipe tombait sur `provider1`). Une
  écriture par identifiant cherche **dans ce salon seulement** et répond
  `not_found` ailleurs ; sans la capacité `catalogue.manage` là, `forbidden`
  — les mots que l'app donne au serveur (« Introuvable. », « Action non
  autorisée pour ce salon. » ; la phrase générique pour les employés).
- **Corrigé au constat** : le §1 disait que l'équipe traitait déjà le gérant
  sans salon. **Pas les écritures de membres** : changer le rôle, retirer,
  renvoyer cherchaient dans toutes les équipes ; elles agissent maintenant
  dans le salon courant, comme `_guardMember`.
- **Les employés** : un employé supprimé restait réservable côté client
  (la suppression ne recopiait pas la liste dans le salon) ; c'est corrigé.
- **Les identifiants** : `MockIds.next` — un compteur, plus l'horloge — aux
  12 endroits (dont le jeton de session et les trois comptes clients).
- **Pas fait, exprès** : les lectures du catalogue et des employés ne sont
  toujours pas gardées par la capacité (le serveur répond `forbidden` à qui
  n'a pas `catalogue.manage`) ; le décompte des places reste celui du faux,
  déjà écrit (`backend-team-reinvite.md` §11).

**Vérifié** :
- Les 20 tests de `mock_fidelity_test.dart` et celui de `pro_team_test`
  d'abord : sur le commit des tests seuls, 20 des 21 sont rouges. Le seul vert est
  « la 21e invitation du salon » : l'ancien compteur le faisait déjà. Le
  garde « aucun faux ne bâtit un id sur l'horloge » s'ajoute ensuite.
- **22 mutations, toutes vues rouges** (les 21 du faux, et l'id d'horloge
  remis pour le garde) : le seau d'adresse sans le salon, pas d'adresse
  canonique, pas de seau de salon, l'adresse avant le salon, pas de jour
  nouveau, des compteurs gardés au `resetTeam` ; le salon neuf à 30 %, la
  copie du premier salon (« Ajouter un salon » et l'inscription), le barbier
  de provider4 rendu aux salons inconnus ; le salon courant sans
  l'adhésion, sans la sélection ; aucune capacité ; une écriture qui
  cherche partout (prestation, employé, membre), une mise à jour qui
  remplace, une écriture qui ne garde rien, un employé supprimé encore
  dans le salon, le catalogue gardé au `resetTeam` ; des ids sans
  compteur.
- `flutter analyze` à zéro ; les suites entières passent : l'app 2 682 (55 golden Linux sautés), le
  serveur sur Postgres 2 162 (2 sautés), le web 2 180, les 269 de bout en bout sur deux workers.
- **SYSTEM §21, ligne 43** fermée (douze endroits, pas six).

## 11. PR C construite (B9.7) — ce qui a été vu

**Comme écrit**, avec un écart et trois trouvailles :
- **`_TagSheet` sur `FieldErrors`** : la faute du champ est redemandée à
  chaque frappe (« VIP␣ » reste « déjà ajouté »), au lieu de s'effacer.
  La règle lit les tags déjà choisis : déjà là, puis la limite — à dix,
  c'est elle qu'il faut corriger, quoi qu'on tape —, puis vide.
- **La limite des 10 tags**, avec sa phrase (Q de §8) : dite sous le champ
  à « + » — c'était déjà vrai, sans test —, et **pour une puce aussi** : la
  onzième puce ne faisait rien du tout, en silence (§14 règle 5). Retirer un
  tag l'efface.
- **L'écart** : le §2.6 disait que l'échec d'enregistrement deviendrait
  « une erreur du champ ». SYSTEM §14 dit le contraire pour une feuille : un
  échec d'enregistrement est l'issue de la feuille, pas la faute d'un champ,
  et sa place est `InlineFeedback` — c'est ce que fait déjà la feuille du
  numéro, dans le même fichier. C'est là qu'il est dit : « Enregistrement
  impossible. Réessayez. », la feuille reste ouverte, rien n'est perdu. Il
  laissait la feuille ouverte sans un mot.
- **Trouvé par les tests : la feuille débordait à dix tags.** Elle n'était
  pas `isScrollControlled` : plafonnée à 9/16 de l'écran, le clavier
  compté dedans. Elle défile et grandit maintenant, comme celle du numéro.
- **Trouvé en écrivant la connexion Pro : les trois connexions par e-mail
  disaient un code refusé sous le formulaire**, là où le web le dit sous le
  code depuis la décision Q1 (web-client-polish.md §2.1) et où SYSTEM §14
  règle 1 le veut. Une table, `core/forms/sign_in_refusal.dart`, copie de
  `otp-failure.ts` : les refus du code (`otp_invalid`, `invalid_input`,
  `otp_expired`, `otp_none`, `otp_locked`) sous le code, `invalid_email`
  sous l'e-mail — quand ce champ est à l'écran —, le reste au formulaire.
  Pour la connexion client, la connexion Pro et l'inscription Pro.
  - `invalid_input` disait « Numéro ou code invalide. » sur une étape sans
    numéro ; c'est « Code incorrect. », comme sur le web. `invalid_email`
    dit la phrase du contrôle local.
  - Un nouveau code envoyé efface la faute de l'ancien.
  - L'inscription Pro disait ses refus dans un `Text` rouge : c'est
    `InlineFeedback`, une région annoncée, comme ailleurs.
  - `AuthProvider` oubliait le code du dernier refus au début d'un nouvel
    essai seulement en cas de succès ou d'échec propre ; il l'oublie au
    départ, comme `ProAuthProvider`.
- **Les tests « sous le champ »** : `_NotesSection` (vide, refusée), la
  connexion admin, la connexion Pro (règles locales et refus du serveur),
  la fiche employé, la fiche prestation (dont le plafond redemandé quand le
  prix de départ change). **15 des 17 écrans** sur `FieldErrors` ont le leur ;
  les deux qui restent attendent le SMS (non routés). SYSTEM §21 ligne 32
  fermée, §14 et §20 à jour.

**Vérifié** :
- **Rouges d'abord** : sur le commit des tests seuls, 19 des 32 nouveaux
  tests sont rouges. Les 13 verts épinglent ce qui était déjà juste (les
  notes, l'admin, les fiches employé et prestation, les règles locales de la
  connexion) ; leur rouge vient des mutations.
- **36 mutations, toutes vues rouges** : la feuille des tags (une frappe qui
  efface, la limite à « + », la onzième puce muette, retirer qui garde la
  limite, l'échec muet, la feuille plafonnée à 9/16) ; les notes (pas de
  règle, l'échec avalé) ; les trois connexions (la faute du code ni placée,
  ni reprise par le focus, répétée sous le formulaire, gardée après un
  nouveau code ; la faute de l'e-mail non placée ; le `Text` rouge) ; la
  table (`invalid_input`, la phrase de `otp_expired`) ; `AuthProvider` (le
  code gardé, à l'envoi et à la connexion) ; la connexion Pro (pas de règle
  d'e-mail, pas de règle de code) ; l'admin (pas de règle, pas de focus,
  le refus tu) ; la fiche employé enregistrée sans nom ; la fiche
  prestation (le plafond non redemandé, pas de focus). **Une a d'abord
  survécu** : le focus après un code refusé — le champ le gardait de la
  frappe. Les tests ferment maintenant le clavier avant d'appuyer, comme
  un utilisateur, et le focus est vérifié sur les trois connexions.
- `flutter analyze` à zéro, le format propre ; les suites entières passent :
  l'app 2 717 (55 golden Linux sautés), le serveur sur Postgres 2 162
  (2 sautés), le web 2 180, les 269 de bout en bout sur deux workers.
- Aucun golden ne change : ceux des connexions montrent la première étape,
  sans refus, où `InlineFeedback(null)` ne rend rien, comme avant.

## 12. PR D construite (B9.11, B9.10) — ce qui a été vu

**B9.11 — comme écrit**, avec une précision et deux de plus :
- **Les huit lectures authentifiées** (notifications client et Pro, « Mes
  salons », avis, équipe, invitations, visites, clients) et les créneaux
  exigent leur liste : un 200 sans elle est une lecture échouée (statut 0,
  l'état d'erreur de la page et son « Réessayer »). `listClients` ne
  vérifiait rien. Les deux tests qui figeaient `[]` disent l'inverse.
- **La précision — les pages publiques lèvent là où le build échoue fermé.**
  `lib/build-posture.ts` laisse exprès un **aperçu Vercel** se construire
  dégradé (le serveur de staging dort) : lever partout aurait remis au rouge
  le contrôle Vercel de chaque PR, ce que ce fichier a été écrit pour
  éviter. Donc `lib/api/public-read.ts` : en production, en local et en CI,
  une réponse inutilisable **lève** — à la régénération ISR, Next garde la
  dernière bonne page ; au build, le build échoue et le déploiement
  précédent reste en ligne — et sur un aperçu, elle reste vide.
- **En plus 1 — `getProviderBySlug`** : un 5xx ou une coupure donnait `null`,
  donc un 404 pour un salon vivant pendant toute la fenêtre ISR (la page le
  notait depuis PR1d sans le corriger). Seul un vrai 404 est `null`
  maintenant ; un 200 sans salon (`id`) lève aussi.
- **En plus 2 — l'arbre des localités** (`localities.ts`) avait le même
  repli vide ; il passe par la même règle, et un échec ne reste plus en
  cache (un 200 sans `countries` plantait sur `undefined.length`).
- **Le contrat** : `items` requis pour `/me/notifications` et
  `/sitemap/providers` ; les types régénérés.
- Les commentaires qui décrivaient l'ancien repli (`client.ts`,
  `api-base.ts`, `taxonomyParams.ts`, la page salon) et WEB.md §3 disent le
  nouveau.

**B9.10 — la règle, appliquée au-delà des sites cités** :
- **Les mots** : `kUnnamedSalon*` (app) et `UNNAMED_SALON*` (web), avec
  `salonNameOr`, qui attrape aussi le vide — `?? 'Salon'` laissait passer
  `''` comme un titre vide. SYSTEM §17.2 les écrit ; une épingle par surface.
- **Trouvé en plus, côté app** :
  - le titre du report de rendez-vous disait « le salon » (une forme de
    phrase en titre) → « Salon » ;
  - l'événement d'agenda « Rendez-vous — le salon » → « Rendez-vous — Salon »,
    comme le web, qui disait « Rendez-vous — MyWeli » ;
  - « Wave · le salon » sur la feuille d'acompte → « Wave · Salon » ;
  - la session Pro donnait « votre salon » même comme **titre** (la carte du
    Profil, « Mes salons », le fait « Nom du salon ») : elle a maintenant
    `knownSalonName` (le nom, ou rien), et `salonName` garde la forme de
    phrase ;
  - l'accueil Pro disait « Bienvenue, votre salon » → « Bienvenue » seul ;
    la ligne du nom dans le journal du collaborateur se tait sans nom ;
  - une invitation sans nom disait « Salon vous invite comme … » et « Vous
    avez rejoint Salon » → « Le salon vous invite … », « Vous avez rejoint
    le salon » (le modèle garde le nom tel qu'envoyé) ;
  - « Mes salons » : une ligne sans titre sous un « ? » → « Salon ».
- **Côté web** : la carte et le détail de rendez-vous, l'agenda, Équipe
  (« ce salon » → « votre salon », comme l'app), « Votre planning » seul,
  les lignes de « Mes salons », les deux phrases d'invitation, et les
  messages « Vous avez rejoint » et « accès retiré » (« Votre accès à  a été
  retiré. » avec un nom vide).
- **« ce salon » reste dans une phrase**, celle de l'accès retiré
  (`not_a_member`) : le bandeau d'un salon sans nom dit cette phrase-là, la
  même que l'erreur, plutôt qu'une sixième.

**Vérifié** :
- **Rouges d'abord** : les lectures authentifiées (19 rouges) et publiques
  (22 rouges) avant le code ; les tests du mot échouent au chargement tant
  que les constantes n'existent pas — leur rouge par comportement vient des
  mutations.
- **31 mutations, toutes vues rouges** : chacune des neuf lectures redevenue
  indulgente ; la règle publique qui dégrade toujours, ou à l'envers ; un
  200 sans `items` rendu `[]` ; un vrai 404 qui lève ; tout 200 pris pour un
  salon ; un arbre en échec gardé en cache ; un arbre 200 non vérifié ; le
  vide pris pour un nom (web, app) ; « — votre planning » ; l'agenda à
  « MyWeli » ; « Vous avez rejoint » et « accès retiré » sur un nom vide ;
  les deux épingles (une carte qui retombe à la main, « ce salon » sur
  Équipe) ; l'agenda de l'app sur le nom brut ; le modèle d'invitation à
  « Salon » ; la carte d'invitation brute ; le bandeau qui rate le mot ;
  « Bienvenue, votre salon » ; la session qui nomme un salon sans nom ; la
  ligne brute de « Mes salons ». Deux mutations du web vérifiées à la main :
  ce sont de vraies assertions, pas un filtre vide.
- `flutter analyze`, `dart analyze --fatal-infos --fatal-warnings`, le
  typecheck et le lint du web à zéro ; les suites entières passent : l'app
  2 726 (55 golden Linux sautés), le serveur sur Postgres 2 162 (2 sautés),
  le web 2 255, les 269 de bout en bout sur deux workers — **leur build
  tourne en posture fermée contre le bouchon**, donc les lectures publiques
  strictes construisent le site.

## 13. PR E construite (B9.2, B9.3, B9.4) — ce qui a été vu

**B9.2 — `release_build.sh`, comme écrit**, avec l'ordre et les essais :
- **Les refus d'abord**, avant de lire le moindre secret : un arbre qui n'est
  pas propre (un fichier non suivi aussi), puis un HEAD qui n'est pas
  `origin/main` — **récupéré d'abord** (`git fetch`) : un `main` avancé
  depuis la dernière récupération n'est pas celui de ce HEAD. Pour iOS, la
  clé d'API App Store Connect (`ASC_KEY_ID`, `ASC_ISSUER_ID`) est demandée
  là aussi, plutôt qu'après dix minutes de build.
- **L'archive** est rangée en `Runner-<saveur>-<build>.xcarchive` ; un build
  qui n'en laisse pas est refusé par le script, pas par `mv`.
- **La validation** (`xcrun altool --validate-app`) passe avant toute
  commande d'envoi ; un refus arrête tout — ni envoi, ni symboles.
- **Ce qui reste à faire est imprimé pour CE build** : les symboles Dart
  **et les dSYM de l'archive** (un plantage natif restait illisible), la
  version de l'app (`com.myweli.<app>@<version>+<build>`) et ses commits
  (`set-commits --commit "Zaslons/myweli@<sha>"`), puis l'envoi. Imprimés,
  pas lancés : il faut le jeton Sentry, que le script ne tient jamais.
- **Les essais tournent le vrai script** dans un dépôt jetable, à son
  `origin/main`, avec `gcloud`, `node`, `flutter` et `xcrun` simulés ; les
  essais existants de la clé CARTO y passent aussi (le nouveau refus les
  aurait arrêtés dans une branche).
- Le guide App Store (§11.2, §11.5) dit le nouveau chemin : la copie de
  l'archive et la validation à la main disparaissent.

**B9.3 — `setup_flavours.rb`, comme écrit** : la phase est trouvée par son
nom et mise à jour sur place (même UUID, même place ; des doublons d'anciens
passages seraient retirés) ; un schéma existant est chargé et seules ses
configurations sont corrigées, et il n'est réécrit que si l'une était
fausse. **Mesuré avant** : un passage sur le projet commis donnait une
nouvelle UUID et retirait aux deux schémas le pre-action de Flutter et
`customLLDBInitFile` ; **après** : aucun changement. L'essai copie `ios/`
et lance le vrai script (locale non UTF-8 comprise) ; il lui faut la gemme
`xcodeproj`, que seul macOS porte (CocoaPods) — sur Linux il saute, et le
flux iOS (macOS) le lance avec `REQUIRE_XCODEPROJ=1`, pour qu'une gemme
absente échoue au lieu de sauter.

**B9.4 — l'observabilité** :
- **`81-uptime-tls-latency.sh`** : `--validate-ssl=true` sur les deux
  vérifications, **sur place** (leurs ids relus) ; une alerte quand le
  certificat a moins de 14 jours (le minimum sur les deux vérifications et
  les régions) ; une alerte quand la latence moyenne des sondes, par
  vérification, dépasse 3 s pendant 15 min (la moyenne : une région lente
  n'appelle personne). Même canal (l'e-mail du propriétaire). Les deux
  runbooks passent les règles des autres (Markdown, JSON valide).
- `80-uptime-checks.sh` crée les vérifications avec la validation.
- **`policy-bodies.sh`** ne liste le nouveau script **qu'une fois appliqué**
  (le même garde que pour 91) : `93-sync-runbooks.sh` refuse une politique
  rendue sans jumelle vivante, et une ligne fixe aurait fait échouer l'étape
  d'après chaque déploiement jusque-là. Les mises à jour des vérifications
  sont dans une fonction, pas une boucle : le rendu des politiques rejoue
  une boucle `for` qui précède un corps, et ne doit jamais les rejouer.
- **Appliqué le 2026-10-25** (accord du propriétaire, après la fusion de
  #697), et relu, pas cru sur parole :
  - les deux vérifications : `validateSsl` vrai, chemin, période (300 s),
    délai (10 s) et hôte inchangés ;
  - les deux politiques (`2907874960028876058`, `9493498265212627759`) :
    activées, le canal « Owner email », les filtres, seuils et durées
    écrits ici, leurs runbooks (923 et 1 048 caractères) ;
  - **les sondes passent toujours** avec la validation : 53/0 et 60/0 sur
    les huit premières minutes ; le certificat a **89,4 jours** (Google Trust
    Services, via Cloudflare, jusqu'au 2027-01-23) ; la latence va de 104 à
    696 ms ;
  - `DRY=1 bash infra/gcp/93-sync-runbooks.sh` : les deux nouvelles
    politiques et toutes les autres sont `same` — l'étape d'après le
    prochain déploiement les accepte.
- **Corrigé en relisant** : les en-têtes de 80 et 81, le test et la note
  d'observabilité disaient que la mesure des jours restants « n'était jamais
  écrite » sans `--validate-ssl`. **Faux** : 990 points dans l'heure
  d'avant. Ce qui manquait, c'est que la vérification échoue sur un mauvais
  certificat, et une alerte sur la date. Les quatre endroits disent vrai.
- **À vérifier dans Sentry** (lot 10) : l'intégration GitHub doit connaître
  `Zaslons/myweli`, sinon `set-commits` est refusé.
- **Les seuils de taux d'erreur** restent reportés (pas de trafic).

**Vérifié** :
- **Rouges d'abord** : les 9 essais de B9.2, les 4 de B9.3 et ceux de
  B9.4 étaient rouges avant le code.
- **21 mutations, toutes vues rouges** : un arbre sale qui construit, pas
  de récupération avant de comparer, n'importe quel HEAD, pas de clé App
  Store Connect, pas de contrôle de l'archive, l'archive sans son build, ou
  copiée et laissée, pas de validation, la version Pro nommée comme celle du
  client, la version sans son build, pas de dSYM, `set-commits` sans le
  commit ; la phase recréée, un schéma existant refait à neuf, une
  configuration fausse laissée ; une vérification créée sans validation TLS,
  la mise à jour sans elle, le certificat à 30 jours, une région lente qui
  appelle, cinq minutes lentes qui appellent, le nouveau script hors du
  registre. **Deux essais renforcés** pour y arriver : `main` avancé depuis
  la dernière récupération, et le refus d'une archive absente par le script
  plutôt que par `mv`.
- **Trouvé en route — une bombe à retardement** : trois essais du web
  (`pro-agenda-url-pages.test.tsx`) prenaient une date fixe pour « un autre
  jour » : `2026-10-25`, aujourd'hui. Corrigé (dix jours plus tard, et le
  libellé calculé) ; il aurait mis au rouge chaque PR d'aujourd'hui, `main`
  compris.
- Les analyses à zéro et le format propre (app et serveur) ; les suites
  entières passent : l'app 2 741 (55 golden Linux sautés), le serveur sur
  Postgres 2 177 (2 sautés), le web 2 255, les 269 de bout en bout sur deux
  workers (le premier passage affichait « 268 passed », son autre ligne non
  relue ; le second, 269).

## 14. PR F1 construite (B9.8, première des trois) — ce qui a été vu

**Les trois briques**, comme §2.7.2 les décrit :
- **`AppAsyncView<T>`** (`widgets/common/app_async_view.dart`) — l'ordre
  d'`AdminDataTable`, plus deux choses que la migration a demandées :
  **`onRefresh`** met l'erreur et le vide dans le tirer-pour-actualiser (le
  tableau de bord l'avait déjà fait à la main ; une liste vide ou échouée
  était le seul endroit où tirer ne faisait rien) ; **`sliver`** en fait une
  section d'une `CustomScrollView` (« Près de vous », sur l'Accueil, est une
  liste paresseuse).
- **`AppErrorView`** — « Chargement impossible », la phrase de la panne,
  `wifi_off` seulement pour « Pas de connexion. Réessayez. ». Elle remplace
  `AdminDetailError` (supprimé), l'erreur nue d'`AdminDataTable` et le bras
  « réessayer » de `SalonUnavailableView`, qui disait « Vérifiez votre
  connexion » pour un 500 aussi (`kSalonLoadError`, retiré). Le salon
  disparu (`not_found`) garde ses mots : c'est un état, pas une panne.
- **Les squelettes** (`app_skeleton.dart`) — immobiles, sur carte, une
  étiquette : la liste de cartes (en tête : rien, un avatar, une vignette ;
  ou une photo au-dessus), la liste de lignes, la fiche, la grille de photos,
  et **les pastilles** (créneaux, opérateurs) — posées sur la page, elles
  sont la silhouette de la puce (`secondary` + `border`), pas une barre que le
  fond avalerait. Le squelette de la carte « Profil » est passé aux barres
  communes — les mêmes hauteur, couleur, rayon et largeurs, par le code ;
  aucune photo ne montre cet état.
- **`AppCard`** est construite (avec `outlined` et `onTap`) ; les squelettes
  l'utilisent ; les cartes des écrans passent à F2.

**Tous les écrans asynchrones y sont passés** — 44 des 48
`LoadingIndicator(` hors de son propre fichier, dans 39 fichiers : l'app cliente
(rendez-vous et leur détail, Accueil, recherche, réservation, confirmation,
fiche du salon, notifications, préférences, mes données, créneaux), l'app
Pro (rendez-vous, détail, réservation manuelle, employés, disponibilité,
clients et fiche, accueil, revenus, journée, vérification, configuration,
photos, avant/après, mes données, profil du salon, avis, services, acompte,
abonnement, invitations, équipe, aperçu) et la console (vue d'ensemble, les
quatre fiches, le tableau).

**Ce que la migration a trouvé** — une vue ne dit que ce que son fournisseur
tient, et ce qu'il tenait n'était pas toujours vrai. Chaque défaut a été lu
sur le vrai chemin de code avant d'être corrigé :
1. **Le détail d'un rendez-vous montrait le précédent.** La sélection est à
   toute l'app et survit à l'écran : en allant de A à B, l'écran de B
   montrait A — ses détails, et « Envoyer l'acompte » et « Reporter » sur
   l'id de A, quand « Annuler » agissait sur celui de B — jusqu'à la réponse
   de B ; une
   réponse tardive de A s'écrivait sous B. Le fournisseur oublie A dès qu'on
   demande B et jette une réponse qui n'est plus la sienne (la garde de
   `loadProviderById`) ; l'écran compare l'id pour sa première image.
2. **La console avait le même défaut, en plus grave** : la fiche du salon B
   montrait le nom et le statut de A, et « Suspendre » agissait sur B ; si la
   lecture de B échouait, A restait, sans erreur. Corrigé dans les trois
   fournisseurs de fiche et dans celui de la vérification ; la fiche de
   vérification n'avait pas de « Réessayer ».
3. **Mes rendez-vous n'avait pas d'état d'erreur** : un chargement échoué
   disait « Aucun rendez-vous ». Et `error` était aussi celui d'une
   annulation ou d'un acompte : la liste a maintenant le sien (`listError`).
4. **L'Accueil disait « Aucun salon trouvé » pendant que la liste
   arrivait** : le carrousel et la liste partageaient `isLoading`, et le
   premier arrivé l'éteignait. Chacun a le sien (`listLoading`,
   `featuredLoading`), la liste a son erreur (`listError`) — qu'elle
   n'avait pas ; la recherche prenait l'erreur d'une fiche de salon pour la
   sienne.
5. **Les préférences montraient les valeurs par défaut** une image avant la
   réponse du serveur (`loadedPrefs`).
6. **La configuration ne pouvait pas échouer** : chaque service répond une
   panne au lieu de lever, et chaque lecture la comptait pour « à faire » —
   hors ligne, un salon voyait toute sa liste à faire. La première panne est
   celle du chargement, dans ses mots.
7. **Les listes Pro sans erreur** disaient leur vide pour une lecture
   échouée : « Aucun avis », « Aucun service pour le moment », « Aucun
   employé », « Aucune invitation en attente », « Ajoutez des services… »
   (réservation manuelle), et le calendrier « Aucun rendez-vous pour
   <jour> » — un jour jamais lu. Revenus et disponibilité montraient une
   phrase grise nue (et l'erreur de la disponibilité était aussi celle d'un
   enregistrement). Chaque fournisseur a l'erreur de sa lecture
   (`loadError`).
8. **Les clients** : un « Ajouter » refusé remplaçait toute la liste par une
   page d'erreur ; chaque recherche vidait la liste derrière un spinner ; la
   fiche montrait le client précédent à sa première image.
9. **Les formulaires et les listes gérées** (acompte, vérification,
   configuration, photos, avant/après) n'apparaissent que sur une lecture
   **terminée** : gardé à l'écran pendant un rechargement, un formulaire
   reprendrait au propriétaire ce qu'il vient de changer ; et ils ne
   montrent plus leurs valeurs par défaut à la première image (`loaded`,
   remis à zéro au changement de salon).
10. **Le tableau de la console** : ses lignes de chargement ne disaient rien
    à un lecteur d'écran ; son erreur était une phrase et un bouton.

**Ce que F1 laisse, et pourquoi** :
- **Les erreurs en ligne d'une section** (les créneaux, la feuille des
  communes, les opérateurs, la carte « Profil », une image) gardent leur
  forme : une `Column` dessinée pour tenir à 200 %, et des sorties propres à
  chacune (un autre salon, un autre jour). Ce n'est pas la page qui a échoué.
- **La porte de session Pro** garde ses mots (« Impossible de charger votre
  salon » — pourquoi chaque page attend, pro-app-salon-not-loaded.md §4) ;
  avec la boîte de dialogue bloquante et les deux transitions de sortie, elle
  est l'un des quatre spinners nommés.
- **La première image d'une liste** dont le fournisseur ne sait pas s'il a
  déjà demandé (les avis, les services…) montre le vide une image avant la
  demande, comme avant ; les écrans dont la donnée est nulle avant la réponse
  (les fiches, le tableau de bord, l'abonnement, les invitations, les
  formulaires) montrent le squelette.
- **Les fournisseurs de l'app cliente ne sont pas vidés à la
  déconnexion** (rendez-vous, notifications, favoris) : un autre compte sur
  le même téléphone voit ceux du précédent jusqu'à sa propre réponse. Hors
  de B9.8 ; proposé à part. F1 garde donc la liste vidée sur un échec, pour
  ne pas l'aggraver.
- **Deux essais** comptaient sur le spinner pour faire avancer le temps
  simulé jusqu'à la fin d'une lecture fictive ; le squelette, immobile, ne le
  fait pas : ils vident cette lecture eux-mêmes, comme leurs voisins.

**Les épingles** (`async_states_pin_test.dart`, sur tout `lib/`) : le
spinner aux quatre endroits nommés et nulle part ailleurs ; pas
d'`actionText: 'Réessayer'` écrit à la main (la porte de session à part) ;
ni « Une erreur est survenue » ni « Connexion impossible » en titre, ni
« Vérifiez votre connexion et réessayez. » en description.

**Vérifié** :
- **La suite de l'app** : 2 781 essais verts, 58 sautés (les photos, Linux
  seulement) ; `flutter analyze` à 0, le format propre.
- **28 mutations, toutes vues rouges**, sur le travail commis : les données
  qui ne restent pas pendant un rechargement, le vide pour « pas encore
  demandé », pas de tirer sur l'erreur, le Wi-Fi pour toute panne,
  « Réessayer » sans `onRetry`, la carte qui n'est pas un bouton, les formes
  entendues, l'écran qui croit la sélection, la sélection gardée vers B, la
  réponse tardive de A, chaque `listError`/`loadError` lu sur l'erreur
  partagée (rendez-vous, salons, clients, catalogue), le carrousel qui
  éteint la liste, les préférences par défaut, les invitations muettes, la
  configuration qui compte une panne pour « à faire », la console qui garde
  A et qui écrit A sous B, le 500 mis sur la connexion, « Réessayer » pour un
  salon disparu, les trois listes Pro sans erreur, et les trois épingles (un
  spinner, un « Réessayer » à la main, un titre retiré). **Une a survécu
  d'abord** : retirer `ExcludeSemantics` du squelette — les formes n'ont pas
  d'étiquette, et l'essai ne regardait que les étiquettes. Ce que la balise
  cache, c'est un nœud : la liste du squelette est un défilement à elle.
  L'essai demande maintenant que « Chargement… » soit une feuille, et la
  mutation est rouge.
- **Les photos**, refaites sur Linux (« Goldens — regenerate ») et
  regardées une à une : **cinq** bougent, rien d'autre. Deux changent —
  l'erreur du tableau de la console (l'icône, le titre, la phrase et
  « Réessayer » en bouton principal, là où il y avait une phrase et un
  contour pleine largeur ; sa toile passe à 480 de haut : l'erreur commune
  débordait 420 de 5 px, le tableau étant dans un défilement sur la console)
  et l'accueil Pro hors ligne (le titre seul : « Chargement impossible ») ;
  trois naissent — l'erreur (avec et sans « Réessayer »), la carte (simple,
  choisie, à toucher) et les squelettes. Le premier passage avait échoué sur
  le débordement : c'est lui qui l'a trouvé.
- **Le serveur** (non touché) : 2 177 essais verts sur PostgreSQL 16. **Le
  web** (non touché) : 2 255 essais unitaires verts ; **les e2e non lancés
  ici** — le port 3000 est tenu par le serveur de développement d'un autre
  projet sur cette machine, laissé tel quel ; le CI les passe.
- **Les rouges d'abord** : chaque correction de fournisseur a été retirée
  une à une par ces mutations, et son essai était rouge sans elle.

## 15. PR F2 construite (B9.8, deuxième des trois) — ce qui a été vu

**`AppCard`, tel que les cartes l'ont demandé** :
- **Un nœud conteneur pour un lecteur d'écran, toujours**, comme la `Card`
  de Material (`semanticContainer`) : ce que dit la carte se lit ensemble.
  **Pas une fusion** — celle de F1 aurait avalé le cœur des favoris d'un
  salon, et un lecteur d'écran n'aurait plus pu l'atteindre. Un essai le
  tient : la carte et le contrôle qu'elle porte sont deux nœuds, et chaque
  toucher va au sien.
- **`onTap`** en fait un bouton ; **`outlined`** le trait `borderStrong` ;
  **`selected`** le trait `primary` de 2 px sur la carte blanche (Q13),
  annoncé « sélectionné » quand la carte est la cible — l'étape ouverte de la
  réservation, dont la cible est son en-tête, le dit par lui (« développé »).

**Les cartes migrées** : 27 `Card` (dont 15 sur le Profil Pro) et 31
dessinées à la main — les 23 de contenu, les 8 qu'on touche (dont le salon,
en liste et en grille), et les deux cartes-contrôles (l'étape de la
réservation, le rôle à choisir). Les ombres disparaissent (19 cartes
portaient `elevation1`), les bordures aussi, `spacingL` passe à `spacingM`
sur six cartes (Q15), et la `margin` de 4 que `Card` ajoutait : les cartes
du Profil Pro s'alignent sur la gouttière de la page, comme toutes les
autres ; leurs écarts restent ceux de la liste.

**Ce que la migration a trouvé** :
- **Six cartes qu'on touche étaient muettes** pour un lecteur d'écran (un
  `GestureDetector` : rien à annoncer — un rendez-vous, un salon en liste et
  en grille, un employé, un service, un raccourci de l'accueil Pro) ; deux
  autres étaient un `InkWell` touchable mais pas annoncé comme bouton. Les
  huit sont des boutons.
- **Les contrôles d'une carte restent à eux** : le cœur des favoris,
  « Voir sur la carte » et « Itinéraire » sont des `Semantics(button: true)`
  sans `container`, dans une carte devenue un nœud et un bouton. Deux
  touchers sur un nœud se séparent d'eux-mêmes (la règle de Flutter) : le
  cœur reste à lui, et l'essai du salon le tient. Un `container: true` ajouté
  sur eux d'abord n'y changeait rien — la mutation qui le retirait survivait —
  et il est retiré.
- **Le rôle choisi ne se disait pas** : une icône radio, et rien
  d'annoncé ; la carte est maintenant « sélectionnée ».
- **`HighlightStories`**, que rien n'affichait, est supprimé.
- **La `Material` transparente** sous deux cartes à `ListTile` (les
  préférences, l'acompte) n'existait que pour porter l'encre ; `AppCard` est
  cette `Material`.
- **Six pages portaient leurs cartes sur `surface`** (#FAFAFA), pas sur
  `background`, le fond de page (SYSTEM §3.1) : le détail d'un rendez-vous,
  la confirmation, les préférences, l'abonnement, les invitations, l'équipe.
  Elles tenaient par l'ombre et la bordure que F2 retire — une carte blanche
  sur #FAFAFA, c'est la moitié de la marche. Elles sont sur `background` ;
  une épingle le tient (sauf les deux écrans de lancement, la connexion de
  la console et l'ajout d'un salon, qui n'ont pas de carte).
- **Le champ de date du sélecteur de créneaux** a la forme d'un champ, pas
  d'une carte : il reste, nommé dans l'épingle, avec la barre « Total »
  ancrée (Q14).

**Ce que F2 laisse** : la console (ses cartes à bordure, idiome du bureau,
SYSTEM §11.2) ; les écrans V2/V3 ; les ombres de ce qui flotte ; les
bandeaux teintés et les tuiles `surface` posées dans une carte, qui ne sont
pas des cartes ; les écarts du Profil Pro, mêlés de 8 et de 16 — un
regroupement à repenser, pas une carte.

**L'épingle** (`cards_pin_test.dart`, sur `lib/` hors V2/V3) : pas de
`Card(` ; pas de boîte `secondary` au rayon des cartes dessinée à la main
(la barre « Total » et le champ de date à part) ; une ombre seulement sur la
liste de ce qui flotte.

**Vérifié** :
- **La suite de l'app** : 2 791 essais verts, 58 sautés (les photos) ;
  `flutter analyze` à 0, le format propre. Deux essais cherchaient une carte
  par son type (`Container`, `Card`) : ils cherchent `AppCard`.
- **Les mutations, en deux passages.** Le premier a laissé survivre trois
  choses, et chacune a appris quelque chose : retirer le `container` de la
  carte ne changeait rien à aucun essai — **un essai dit maintenant qu'une
  carte se lit d'un bloc et deux cartes en deux** ; retirer le `container`
  ajouté au cœur des favoris ne changeait rien non plus — Flutter sépare déjà
  deux touchers, l'ajout était inutile et il est retiré. **Second passage :
  12 mutations, toutes rouges** — la fusion, le conteneur, le bouton,
  « sélectionné » non dit, le trait de 1 px, le trait d'une autre couleur, le
  contour passif, l'ombre, une `Card`, une carte dessinée à la main, une ombre
  sur une carte, une page de cartes rendue à `surface`.
- **Les photos**, refaites deux fois sur Linux (avant et après les fonds de
  page) et **regardées une à une** : 17 bougent — l'ombre partie (l'accueil,
  le salon, mes rendez-vous, la réservation, l'accueil Pro, le calendrier,
  les revenus, les avis), la bordure partie (l'acompte, l'équipe), l'étape
  ouverte de la réservation à 2 px, les cartes du Profil et de l'accueil Pro
  à la gouttière, et l'équipe et les invitations sur `background` — le
  premier passage montrait la carte d'invitation presque effacée sur
  `surface`, et c'est lui qui a trouvé les six pages.
- **Le serveur et le web** ne sont pas touchés depuis #699 (2 177 et 2 255
  essais verts sur ce même code).

## 16. PR F3 construite (B9.8, la dernière des trois) — ce qui a été vu

**`AppChip`** (`widgets/common/app_chip.dart`), quatre façons, `radiusPill` :
- **`.choice`** — la `ChoiceChip` de Material sous `chipTheme`, sans rien
  surcharger : pleine (`primary`, étiquette blanche) quand elle est choisie,
  soulignée (`borderStrong`) sinon ; « sélectionné » dit ; une cible de 48 ;
  **la coche** sur une puce choisie (Q16), qui prend la place de l'icône ;
- **`.tag`** et **`.action`** — soulignées, la seconde touchable ;
- **`.status`** — la teinte du ton à 12 % et l'étiquette dans la couleur du
  ton. **Mesuré** sur `background`, le pire des deux fonds : succès 7,1:1,
  attention 5,3:1, erreur 7,4:1, info 12,5:1, neutre 6,8:1 ; « fort » et
  « or » à l'encre — l'or n'est pas un texte (B7.1) — et chacun avec son
  trait (plus bas).
  Les tons vivent dans `core/utils/chip_tone.dart`, et
  `appointmentStatusTone` à côté d'`appointmentStatusColor`, pour qu'un
  statut ait une seule couleur et un seul ton — **ceux de la décision B7 du
  propriétaire** (« des statuts teintés par genre, partout » :
  web-b7-desktop.md) : confirmé = ok (vert), en attente = attente, annulé et
  absent = danger, terminé = neutre, comme `AdminChipKind` et le
  `statusChipKind` du web. La table de l'app disait confirmé = info, terminé
  = succès, absent = attention ; la carte d'un rendez-vous côté client,
  confirmé = vert ; la tuile compacte, une troisième chose. **La journée
  garde sa langue à elle** (une arrivée est la verte, confirmé est info),
  dans l'app comme sur le web (`STATUS_STYLE`).

**Les puces migrées** : 12 `FilterChip`/`ChoiceChip` (la journée, les tags
d'un client et le filtre de la liste, l'acompte, la disponibilité, la durée
d'un service, la longueur, **les créneaux** — pleins maintenant, Q17), les
catégories de l'accueil, et les deux filtres de la recherche ; les tags et
l'action d'une fiche client ; **tous les statuts et badges** — le calendrier,
la liste et le détail Pro, la carte d'un rendez-vous et « Réservé par votre
salon », la tuile compacte, la journée, les absences (le détail, la journée,
la liste des clients), « MyWeli » et les tags d'une ligne de client,
« Réservation vérifiée », « Nouveau », les créneaux de la disponibilité, et
les rôles d'équipe (Q18).

**Ce que la migration a trouvé** :
- **Le statut du détail d'un rendez-vous Pro était illisible.** Une `Chip`
  pleine de la couleur du statut, sans couleur d'étiquette : le thème lui
  donnait l'encre. **Mesuré sur le rendu** (l'étiquette peinte, pas la
  couleur supposée) : « Confirmé » **1,02:1**, « Annulé » 1,74:1,
  « Terminé » 1,88:1, « En attente » 2,59:1 — aucun statut ne passait.
- **La tuile compacte** de l'accueil (« Derniers rendez-vous ») avait sa
  propre table de statuts, en teintes « claires » : « En attente » en
  `warningLight` sur sa teinte, **1,6:1** (jaune sur jaune pâle, la photo de
  l'accueil le montrait), « Confirmé » 4,17:1, « Annulé » 3,95:1 ; et elle
  disait un rendez-vous confirmé en vert et un rendez-vous terminé en bleu,
  l'inverse de la table commune.
- **La coche ne se voyait pas sous une icône** : Material la peint *par-dessus*
  l'avatar, et l'icône restait visible — la puce choisie montrait « ∞ Tous »
  sans coche. Choisie, elle n'a plus d'icône : la coche prend sa place, comme
  Q16 le disait. Et l'icône d'une puce est `iconXS` (16, « chips » dans le
  jeton même) : à `iconS` (20), le glyphe était coupé dans sa boîte de 16 —
  l'essai de mise en page l'a vu, pas l'œil.
- **Un Manager se lisait comme un Collaborateur.** Le ton « fort » était le
  noir à 12 % : à **1,09:1** du gris neutre, le même gris — la photo de
  l'équipe le montrait, la hiérarchie que l'app et le web dessinaient
  (Propriétaire or, Manager plein, les autres soulignés) avait disparu. Le
  ton fort porte maintenant **le trait noir de la marque**, comme l'or porte
  le sien — pas `borderStrong`, le trait d'un contrôle. Trois marches
  restent trois, et chaque rôle est épinglé à son ton
  (`team_role_chip_test.dart`). Le créneau libre de la disponibilité, l'autre
  ton fort, retrouve le trait qu'il avait.
- **Les filtres de la recherche** (« Trier », « Disponible aujourd'hui »),
  dessinés à la main, ne disaient pas lequel était actif ; ils sont des
  puces « sélectionnées ».
- **Les statuts avaient trois dessins** — une boîte au `radiusSmall`, une
  pastille, une puce pleine à l'étiquette `Colors.white` littérale — et les
  rôles d'équipe un quatrième. Ils n'en ont plus qu'un.

**Ce que F3 laisse** : le champ de début/fin du sélecteur d'heures (une case
à deux lignes, A14b) ; les étiquettes posées sur une photo ; le sélecteur de
commune (un bouton) ; les bandeaux (vérification, abonnement) ; la console
(`StatusChip`) ; les écrans V2/V3.

**Les épingles** (`chips_pin_test.dart`, sur `lib/` hors V2/V3) : aucune puce
Material hors d'`app_chip.dart` ; aucun badge teinté dessiné à la main (une
teinte au rayon d'une pastille ou d'un badge).

**Vérifié** :
- **La suite de l'app** : 2 808 essais verts, 58 sautés (les photos), sur
  `405a6955` ; puis le trait du ton fort et ses cinq essais (le trait, et
  chaque rôle à son ton) — les 39 fichiers qui touchent une puce, la
  disponibilité ou l'équipe, 469 essais verts. `flutter analyze` à 0, le
  format propre. Deux essais cherchaient une puce par son type (la
  `FilterChip` des tags, le `Container` de « Nouveau ») : ils cherchent la
  `ChoiceChip` et `AppChip`.
- **Les mutations : 15, toutes rouges**, sur le travail commis — pas de
  coche, le fond surchargé, l'icône gardée sous la coche, l'icône trop
  grande pour sa boîte (vue par l'essai de mise en page), la teinte à 30 %,
  une étiquette à l'encre, l'or en texte, une pastille carrée, une pastille
  qu'on touche, un tag qui agit, le ton fort sans son trait, un Manager au
  ton neutre, confirmé hors du genre « ok », une puce Material revenue, une
  pastille dessinée à la main revenue.
- **Les photos**, refaites deux fois sur Linux et **regardées une à une** :
  10 bougent — la coche sur la puce choisie (l'accueil, l'acompte), les
  catégories à la taille du thème, les statuts en pastille (mes rendez-vous,
  le salon, la liste et la journée Pro — « Terminé » neutre et « Confirmé »
  vert, sur B7), la tuile de l'accueil lisible, les créneaux de la
  disponibilité en pastilles (deux par ligne, plus la cible de 48 d'une puce
  qu'on ne touche pas), l'équipe sur trois marches, et la planche des
  composants avec les quatre façons et les tons. Le premier passage a
  montré le Manager gris parmi les gris.
- **Le web a vu ce que l'app ne voyait pas.** Les tons étaient d'abord
  dans `core/theme/`, et la porte du miroir des jetons du web
  (`tokens.mirror.test.ts`) tient la liste des fichiers de ce dossier : un
  fichier de plus est une source de jetons qu'elle ne lit pas. Un ton est
  un nom, pas une valeur : il est passé à côté de `status_colors.dart`, et
  la porte reste ce qu'elle était. La suite du web : 2 255 essais verts.
  Le serveur n'est pas touché depuis #699.

## 17. PR G construite (B9.12) — ce qui a été vu

**Comme écrit en §2.11**, relu sur le code et sur la production le jour même
(lu, rien changé) : la révision servie est `myweli-api-00046-bzg`
(`commit: eca4db6`), qui ne nomme la table que par sa création ; celle
d'avant, `00045-8hs`, l'efface à chaque suppression de compte Pro.

**`0043_drop_provider_otp_codes`** : `DROP TABLE IF EXISTS
provider_otp_codes`, **le premier `DROP TABLE` de la liste**, et son
`// rollback-unsafe:` dit le seul retour qui casse — deux crans, vers
`00045-8hs` ou plus ancien. Un cran, vers `00046-bzg`, reste sûr.

**Ce que la construction a trouvé** :
- **La porte de réversibilité n'avait jamais vu un `DROP TABLE`.** Elle
  le cherchait depuis le début ; la mutation qui retire la déclaration le
  montre : elle seule la fait rougir.
- **Les textes comptaient « cinq »** migrations dangereuses
  (`infra-rollback.md` §5.2, l'en-tête de l'essai) — cinq contraintes dans
  quatre migrations, qui toutes *rétrécissent* ce que la base accepte. La
  sixième *retire* quelque chose : les textes disent maintenant « les
  quelques-unes qui ne le sont pas le disent », et §5.2 nomme celle-ci et
  son retour sûr.

**Vérifié** :
- **La suite du serveur**, contre un vrai Postgres (une base jetable, à
  côté de la base locale) : 2 183 essais verts, 2 sautés (les jetons R2) ;
  `dart format` propre, `dart analyze --fatal-infos --fatal-warnings` à 0.
- **Les mutations : 7, toutes rouges**, chacune sur une base neuve — la
  déclaration retirée (la porte existante seule la voit), la suppression
  rendue sans effet (seule la moitié Postgres la voit), sans `IF EXISTS`,
  la déclaration au-dessus de l'`id:`, le retour qui casse non nommé, un
  fichier du serveur qui nomme la table de nouveau.
- **L'app et le web** ne sont pas touchés.

**Déployé le 2026-10-25**, sur ton accord : la production, avec l'image que
la fusion a construite (`image_tag=a0ee1cd`, run 40241432887). **Relu** :
- la révision `myweli-api-00047-55v` est prête, à 100 % du trafic, son
  étiquette `commit: a0ee1cd`, son empreinte (`sha256:000de335…`) celle de
  l'image `api:a0ee1cd` — **prête veut dire `0043` écrite**, puisqu'une
  migration qui échoue empêche le démarrage ;
- la révision d'avant est `00046-bzg` (`eca4db6`) : la cible d'un retour
  d'un cran, sûr ;
- `api.myweli.com/health` répond 200, et la révision nouvelle n'a écrit
  aucune erreur.
