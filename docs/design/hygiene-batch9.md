# Lot 9 : l'hygiène, les outils et les tests — spec

| | |
|---|---|
| **Statut** | **Validé le 2026-10-22** — relu sur main (`d1e886e1`). Q1 (décision 33) : **le type `SalonId`** (« ce qui vaut le mieux à long terme ») ; Q2 (décision 34) : **e-mail et poussée Sentry** ; Q3 (décision 34) : **pas de suivi des performances pour l'instant** ; Q4 (décision 35) : **pas d'interrupteur** ; Q5 : **construire les trois composants et migrer tous les écrans maintenant** ; Q6 : **les pages publiques lèvent** ; Q7 : **supprimer la table avec ce lot** ; Q8 : **le reste tel qu'écrit**. Huit PR (§3). **PR A construite le 2026-10-22** sur `feat/batch9-hygiene` (#688 — B9.1, B9.5 — §9). |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-22 |
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
- **(H) Le type `SalonId`** : B9.9 (app).
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

**Décisions (2026-10-22).** Q2, Q3, Q4, Q6, Q7, Q8 : les recommandations.
Q1 : « ce qui vaut le mieux à long terme » — le type `SalonId` (§2.8, PR H).
Q5 : la recommandation — tout migrer maintenant (§2.7).

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

