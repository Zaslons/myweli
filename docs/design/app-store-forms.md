# MyWeli Pro — App Store Connect, formulaire par formulaire

| | |
|---|---|
| **Status** | **Prêt à remplir, en attente de** : la facturation GCP (production arrêtée), l'état du salon démo en production, et **la voie compagnon** ([pro-companion-path.md](pro-companion-path.md), construite le 2026-10-05) — sa fusion, et son backend déployé en production **avant** la soumission. Rédigé 2026-09-24 ; **mis à jour 2026-10-05** : fiche App Store Connect vérifiée (Apple ID 6805272779, §0 #3, §3), décision 3.1.1 prise — voie (a), sur les deux apps (§2), Xcode 27 prêt (§0 #2), deux avis App Store Connect à traiter (§0 #6). **Mis à jour le 2026-10-22** (BACKLOG B9.1) : la facturation est rouverte (2026-10-06) et la production rétablie ; le salon démo vit en production (2026-10-11) ; la voie compagnon est fusionnée (#551) et en production ; le **build 587 (0.0.1) est soumis et en revue**, publication manuelle (BACKLOG B0.1). Ce qu'App Store Connect seul peut confirmer — l'issue de la déclaration DSA, ce que dit l'étiquette de confidentialité, l'avancement de la revue — se relit au lot 10. |
| **Portée** | L'app **MyWeli Pro** seule — `com.myweli.pro`, nom affiché « MyWeli Pro », iPhone uniquement. Le consommateur (`com.myweli.app`) aura son propre dossier. |
| **Source** | L'audit App Store du 2026-09-24 (cinq lentilles, chaque constat bloquant/majeur revu par un vérificateur indépendant) et le commit `68fc33c` qui en corrige la partie code. |
| **Pendant Android** | [play-store-forms.md](play-store-forms.md) — même règle, même ton. |
| **Règle** | Chaque réponse est dérivée du code, du binaire ou de la politique publiée, jamais inventée. En cas de doute en saisissant : STOP, on vérifie. Aucun secret ici : le code démo se lit au moment de remplir (§8). |

Ordre conseillé dans App Store Connect : **fiche de l'app (§3) → Informations
sur l'app : catégorie, droits, classification (§5, §6, §9) → Tarifs et
disponibilité (§9) → Confidentialité de l'app (§7) → page de la version 0.0.1 :
captures, textes, build, informations pour la revue (§4, §8, §10)**. Les notes
de revue sont en anglais pour le relecteur, avec les libellés français de l'app
recopiés à l'identique.

---

## 0 · Où on en est — ce qui bloque la soumission aujourd'hui

Le binaire signé du 2026-08-29 (IPA 536) **n'est pas soumissible** : l'audit y a
trouvé deux SDK sans manifeste de confidentialité, une demande de position qui
décrit une fonction consommateur, une déclaration iPad jamais testée, des
sessions Sentry que la politique nie et des appels à payer sur myweli.com. Le
code est corrigé (§1) ; **il faut reconstruire** (§11). Ce qui reste bloquant :

| # | Bloquant | Nature | Ce qui le lève |
|---|---|---|---|
| 1 | ~~**Production arrêtée.** Compte de facturation fermé (facturation coupée au plus tard le 2026-09-16 10:30 UTC — le dernier contrôle vert date du 15) ; les deux bases Cloud SQL suspendues le 2026-09-23 06:23 UTC, motif `BILLING_ISSUE` — Google supprime une instance suspendue au bout de **90 jours** ; le workflow « Production checks » est rouge chaque jour du 2026-09-16 au 2026-09-24 ; `api.myweli.com/health` injoignable le 2026-09-24. Le binaire ne parle qu'à `https://api.myweli.com` (c'est voulu), donc le relecteur ne passe pas l'écran de connexion — rejet 2.1 assuré (« turn on your back-end service! »). Secret Manager refuse aussi (`BILLING_DISABLED`) : pas de nouveau build (`tool/release_build.sh` lit `MOBILE_SENTRY_DSN`) et pas de code démo lisible.~~ **Levé le 2026-10-06** : facturation rouverte, production rétablie ([LAUNCH.md](../LAUNCH.md) §6.2). | owner | Rétablir la facturation ; `/health` 200 ; « Production checks » vert. L'envoi à TestFlight **interne** peut précéder (il ne contacte pas l'API), la soumission non. |
| 2 | ~~**Machine de build.**~~ **Levé le 2026-10-05** : licence Xcode 27 acceptée, premier lancement fait (`xcodebuild -checkFirstLaunchStatus` → 0), build iOS non signé de Pro réussi sous Xcode 27 depuis le correctif du Podfile (§11.1). Une liste de comptes existe dans les réglages d'Xcode ; que ce soit l'équipe **5VWKJD956A** ne se voit que dans Xcode. | owner | Vérifier l'équipe dans Xcode → Réglages → Comptes avant le §11.2. |
| 3 | ~~**Fiche App Store Connect non vérifiée.** Le profil « iOS Team Store Provisioning Profile: com.myweli.pro » prouve que l'App ID existe dans le portail développeur, pas que la fiche App Store Connect existe. Rien dans le dépôt ne l'atteste ; sans fiche, l'envoi est refusé.~~ **Levé le 2026-10-05** : la fiche « MyWeli Pro » existe, relue en lecture seule dans App Store Connect (navigateur du propriétaire) — Apple ID **6805272779**, SKU `myweli-pro`, bundle `com.myweli.pro`, langue principale français, version iOS 1.0 « Prepare for Submission », aucun build dans TestFlight. Encore vides : catégorie, sous-titre, droits sur le contenu (§3). | owner | Fait. Reste à remplir les champs (§3, §4, §5, §9). |
| 4 | ~~**Salon démo en production non vérifié.** Le propriétaire a curé « Salon Démo MyWeli » vers le 2026-08-26/27, sans que l'environnement (staging ou prod) ni la capture du snapshot en prod soient consignés ; le logo réel doit encore être téléversé **puis le snapshot recapturé** (sinon la remise à zéro de 7 jours l'annule). | owner | Une fois la prod revenue, **avant que quoi que ce soit ne touche la base staging** : se connecter en démo, vérifier, logo, `POST /admin/demo/snapshot`, consigner date + environnement dans [backend-demo-review-account.md](backend-demo-review-account.md) §9.~~ **Levé le 2026-10-11** : le salon démo vit en **production** ; renommé **« Maison Nala »**, logo réel téléversé et snapshot recapturé par le propriétaire (journal prod : connexion démo depuis l'iPhone 10:29 UTC, téléversement + deux `PATCH /providers/provider_1787778426683705` 10:29–10:30, `POST /admin/demo/snapshot` **200** à 10:37) ; la connexion démo marche sur le build TestFlight 555. Détail : [backend-demo-review-account.md](backend-demo-review-account.md) §9. |
| 5 | ~~**Décision 3.1.1 ouverte** : le sélecteur d'offre et les incitations à choisir une offre sont encore dans l'app iOS (§2).~~ **Décidé le 2026-10-05** : voie (a) — app compagnon gratuite (3.1.3(f)) — sur **les deux** apps, iOS et Android, sans branche de plateforme (§2.4). Construite selon [pro-companion-path.md](pro-companion-path.md) le 2026-10-05 sur `feat/pro-companion-path` (backend, mobile, docs). La ligne SUBSCRIPTION des notes est en place (§8). **Fusionnée** (#551) **et en production** ; le build 587 la porte. | code + déploiement | La PR fusionnée ; le backend qui démarre l'essai à la première mise en ligne **déployé en production avant la soumission** : depuis « Accueil », le relecteur peut ouvrir « Configurer mon profil » et mettre son compte neuf en ligne. Sans ce backend, il lirait « …l’offre de votre salon n’est plus active. » pour une offre qui n'a jamais existé (spec §9.4). Feu vert du propriétaire pour la production. |
| 6 | **Deux avis dans App Store Connect** (relevés le 2026-10-05). **Classification : faite le 2026-10-06** (4+, nouvelles questions répondues, §6). **Statut de professionnel UE : déclaré le 2026-10-06** (option 1, coordonnées vérifiées par code, certificat de résidence téléversé — « In Review » chez Apple, §9.1). Prix (gratuit), disponibilité (Côte d'Ivoire seule) et exclusion Mac / Vision Pro faits le même jour (§9). | Apple | Attendre la décision d'Apple sur la déclaration DSA (Business → Compliance) ; répondre à toute demande de pièce. *(2026-10-22 : l'issue ne se lit que dans App Store Connect — relue au lot 10.)* |

**Décision du propriétaire, 2026-09-24** : l'app Pro part **d'abord sur l'App
Store d'Apple** — TestFlight et la revue maintenant ; la **publication
publique** attend toujours que la production soit rétablie et stable
([LAUNCH.md](../LAUNCH.md) §3).

---

## 1 · Ce que l'audit a changé dans le binaire (commit `68fc33c`)

Tout ceci est dans le code et **n'existe dans aucun IPA** tant que le build du
§11 n'a pas été fait. Chaque point dit pourquoi, et comment il est vérifié —
en test, puis sur l'IPA (la seule chose qui voit un `$(SETTING)` résolu).

1. **`file_picker` 11.0.2 → 13.1.0 — la chaîne DK retirée (ITMS-91061).**
   *Pourquoi* : `file_picker` 11 liait DKImagePickerController et
   DKPhotoGallery, tous deux sur la liste Apple des SDK à manifeste
   obligatoire ; dans l'IPA 536 aucun des deux bundles ne portait de
   `PrivacyInfo.xcprivacy` (le `Package.swift` amont ne déclare pas la
   ressource, SwiftPM la laisse tomber ; DKPhotoGallery n'en a pas). Pour une
   **nouvelle** app, c'est un refus ITMS-91061. La 12.0.0 a retiré la chaîne
   DK ; `file_picker_darwin` déclare son manifeste comme ressource SwiftPM.
   L'appel KYC passe à `pickFile()` (la 12 a supprimé `FilePickerResult`),
   `compressionQuality: 30` gardé explicitement (la 10 avait mis le défaut à
   0). `package_info_plus` 9 → 10 (exigé par `file_picker` ≥ 12 via win32 6).
   *Vérifié* : `ios_store_readiness_test` « file_picker is past the DK chain
   (>= 12) » lit `pubspec.lock`. *À vérifier sur l'IPA* :
   `unzip -l … | grep -cE 'DKImagePickerController|DKPhotoGallery'` = **0**
   (§11). *À vérifier sur appareil* : choisir une image **et** un PDF dans
   Profil → « Vérification » — l'API a changé.
2. **Pro en iPhone uniquement** (`TARGETED_DEVICE_FAMILY = 1` au niveau
   *cible* des trois configurations Pro ; le consommateur reste `"1,2"`,
   écrit explicitement). *Pourquoi* : `"1,2"` hérité du gabarit Flutter
   rendait obligatoires les captures iPad 13 pouces et faisait relire sur iPad
   une mise en page jamais testée ; une famille d'appareils livrée ne se
   retire pas, elle s'ajoute (rapports de développeurs, pas un texte Apple —
   UNVERIFIED comme règle). *Conséquence* : **aucune capture iPad**, seulement
   le jeu iPhone 6,9 pouces (§10). App Review peut encore lancer l'app sur iPad
   en mode compatibilité (INFERRED) : une colonne iPhone, rien à faire.
   *Vérifié* : deux tests de `ios_store_readiness_test` (le script écrit la
   famille depuis la table des saveurs ; chaque configuration Pro vaut 1, le
   consommateur `"1,2"`). *IPA* : `UIDeviceFamily => [1]`.
3. **Textes de permission par saveur.** Un seul `Info.plist` servait les deux
   apps avec des chaînes littérales : Pro demandait la position « pour
   afficher les salons autour de vous sur la carte », une fonction qu'il n'a
   pas — le rejet 5.1.1(ii) type. Désormais `$(LOCATION_USAGE_DESCRIPTION)`,
   `$(CAMERA_USAGE_DESCRIPTION)`, `$(PHOTO_LIBRARY_USAGE_DESCRIPTION)`, écrits
   par `mobile/ios/tool/setup_flavours.rb` ; textes consommateur inchangés mot
   pour mot. Textes Pro :
   - position : « MyWeli Pro utilise votre position pour placer votre salon
     sur la carte et trouver votre commune. »
   - appareil photo : « MyWeli Pro utilise l’appareil photo pour la galerie de
     votre salon, vos photos avant/après, le logo du salon et les photos de
     votre équipe. »
   - photos : « MyWeli Pro accède à vos photos pour la galerie de votre salon,
     vos photos avant/après, le logo du salon et les photos de votre équipe. »

   *Vérifié* : sept tests de `ios_store_readiness_test` (les trois clés lisent
   leur `$(…)`, le script les assigne dans la boucle, chaque configuration Pro
   décrit l'usage Pro de la position, chaque configuration définit les trois
   non vides — une chaîne vide est un plantage à la demande de permission, pas
   un rejet —, et les deux apps disent des choses différentes). *IPA* : les
   trois chaînes Pro dans `plutil -p`. Les chaînes calendrier restent
   partagées ; Pro ne demande jamais le calendrier (sans effet).
4. **`CFBundleLocalizations = [fr]`, et `CFBundleName` suit le nom affiché**
   (« MyWeli Pro » au lieu de « MyWeli »). *Pourquoi* : sans la
   localisation, l'interface système dans l'app (boutons des alertes de
   permission, sélecteur de documents) retombe en anglais à côté de textes
   français. *Vérifié* : « the app declares French ». `CFBundleDevelopmentRegion`
   reste `en` (non traité — §14). *2026-10-13 : traité — c'est ce `en` que
   lisait l'App Store ; la langue de développement du projet devient le
   français et le paquet reçoit un `fr.lproj`
   ([ios-language-and-orientation.md](ios-language-and-orientation.md)).*
5. **Sentry : sessions de santé de version OFF, suivi des blocages (app hangs)
   ON, les deux épinglés.** *Pourquoi* : le SDK envoyait une session à
   **chaque lancement** (défaut `enableAutoSessionTracking = true`) alors que
   la politique publiée dit que « les fonctions de Sentry qui compteraient les
   visites ou les sessions sont désactivées ». Un blocage est une défaillance,
   envoyé seulement quand il survient — dans la promesse « rien n'est envoyé
   quand rien n'a échoué ». *Conséquence pour l'étiquette* : **Diagnostics →
   Crash Data + Performance Data, non liés** ; **pas** Other Diagnostic Data
   (§7). *Coût* : le taux de sessions sans plantage disparaît (l'alerte prévue
   par [observability-error-reporting.md](observability-error-reporting.md)
   §8.3). *Vérifié* : `error_reporting_test` « no session is sent when nothing
   has failed — the policy says so » (deux assertions : sessions `false`,
   blocages `true`).
6. **Écran d'abonnement iOS : l'état de l'offre, jamais où ni comment payer.**
   `mobile/lib/core/config/store_policy.dart` (`hidesExternalPurchaseCopy`,
   vrai sur iOS) retire sur iOS toutes les phrases « … sur myweli.com »
   (« Votre offre se gère… », « Gérez votre offre… », « Réactivez votre
   offre… », « Activez votre offre… »), la ligne de ROI « Un seul rendez-vous
   manqué évité paie le mois. » et « Tarif personnalisé ». Les bannières d'état
   (essai, expirée, salon dépublié, « Vos données sont intactes. ») restent.
   Android et le web gardent tout le texte. *Vérifié* : cinq tests du groupe
   « iOS — the offer state, never where to pay (App Store 3.1.1) » de
   `pro_subscription_screen_test` (setup, grâce, expirée + dépubliée, expirée
   encore publiée, et un témoin Android qui garde le texte), plateforme forcée
   en iOS et remise dans un `finally`. **Le sélecteur d'offre et les autres
   incitations restent** : décision ouverte, §2.

   *2026-10-05 — dépassé par la voie compagnon (§2.4)* : le sélecteur, les
   phrases Android « … sur myweli.com » et `store_policy.dart` quittent l'app
   sur **les deux** plateformes — supprimés, pas conditionnés
   ([pro-companion-path.md](pro-companion-path.md) §5). Le compte ci-dessus
   était d'ailleurs faux : le groupe a **six** tests — cinq forcés en iOS et
   le témoin Android, qui ne l'est pas (relevé par l'audit du 2026-10-05) ;
   ils sont réécrits par cette voie, pas supprimés (spec §8).

**L'IPA 536 est donc périmé.** Le prochain numéro de build est le nombre de
commits de `main` au moment du build (> 536, monotone) — construire depuis
`main`, jamais depuis une branche (§14).

---

## 2 · Règle 3.1.1 — notre position, et la décision (prise le 2026-10-05)

### 2.1 Pourquoi c'est le point le plus risqué

MyWeli facture **le salon** pour le logiciel (offres Pro, Business, Réseau ;
essai de 3 mois, puis facturation manuelle confirmée par un admin). Une offre
**débloque des fonctions** — `hasLiveOffer()` conditionne la publication, la
réception de réservations et les invitations d'équipe ; les places dépendent
du palier. C'est exactement le cas de 3.1.1 (« If you want to unlock features
or functionality within your app… you must use in-app purchase »). Les
exceptions, vérifiées une à une par l'audit :

| Exception | Tient ? |
|---|---|
| 3.1.3(e) biens et services physiques | Non pour l'offre MyWeli (logiciel). **Oui pour les acomptes** des clients, payés au salon pour une prestation physique. |
| **3.1.3(f) app compagnon gratuite d'un outil web payant** | **Oui, à condition** qu'il n'y ait « no purchasing inside the app, or calls to action for purchase outside of the app ». |
| 3.1.3(b) multiplateforme | Non : exige que les mêmes offres soient aussi vendues en achat intégré. |
| 3.1.3(c) entreprise | Non : les salons s'inscrivent eux-mêmes, rien n'est vendu à une organisation pour ses employés. |

> **2026-10-26 — ce que la revue a tranché en plus.** Apple a refusé la
> 0.0.1 sous **3.1.1** : l'inscription d'une entreprise **dans l'app** est un
> accès à un mécanisme d'achat externe (« Remove the account registration
> features for business and organizations »). 3.1.3(f) tient pour les achats,
> pas pour l'inscription : l'app Pro ne fait plus que connecter les salons
> (iOS et Android), l'inscription et l'ajout de salons restent sur le web
> ([pro-app-login-only.md](pro-app-login-only.md), BACKLOG B0.11).
| Exception de lien du storefront US | Non : ne couvre pas la Côte d'Ivoire, et un binaire est relu pour tous les storefronts. |

La question métier était ouverte depuis le début ([PRD.md](../PRD.md) OQ-3) ;
**tranchée le 2026-10-05** par le propriétaire : voie (a), sur les deux apps
(§2.4).

### 2.2 Ce qui est fait (commit `68fc33c`)

Sur iOS, l'écran « Mon abonnement » ne dit plus **où ni comment payer** (§1.6).
Les prix avaient déjà disparu le 2026-08-23.

### 2.3 Ce qui restait dans l'app iOS — l'objet de la décision

*2026-10-05 : l'inventaire qui fait foi est désormais
[pro-companion-path.md](pro-companion-path.md) §2.2 — chaque surface, état par
état, avec le texte exact **avant → après**, relevé par un audit en quatre
passes (un sceptique par passe, puis un critique d'exhaustivité) et relu dans
le code. Le tableau ci-dessous, relevé du 2026-09-24, est gardé pour
l'historique : il était incomplet — il ne nommait ni « Le changement d’offre
conserve votre période d’essai. », ni la carte « Ajouter un salon » (« Chaque
salon a sa propre offre et son propre essai. »), ni la phrase « … offre et
période d’essai. » de l'écran d'ajout de salon, ni les boutons « Aide &
Support » sous les états d'offre.*

| Où | Quoi |
|---|---|
| `pro_subscription_screen.dart` | le sélecteur de palier : « Choisir » / « Changer d’offre » sur les cartes Pro, Business, Réseau |
| `pro_onboarding_screen.dart` | l'étape « Choisissez votre offre » / « 3 mois offerts », et le snackbar « Choisissez votre offre avant la mise en ligne. » avec son action « Choisir » |
| `invite_member_sheet.dart` | « Choisir mon offre » / « Changer d’offre » sur `offer_required` / `seat_limit` |
| `add_salon_screen.dart`, `salon_picker_sheet.dart` | « Réservé à l’offre Réseau… », « Offre Réseau — un salon de plus dans votre compte » |

**L'enjeu monte avec nos propres notes** : elles demandent au relecteur de
tester la suppression sur un **compte Apple neuf** (§8), qui passe par
l'onboarding — donc par « Choisissez votre offre ».
*(Corrigé le 2026-10-05 : l'inscription ouvre « Accueil », pas l'onboarding
(§8). L'onboarding est facultatif et s'ouvre par la carte « Configurer mon
profil » ; c'est là que l'étape d'offre attendait le relecteur.)*

### 2.4 Les deux voies — **choisie le 2026-10-05 : (a), sur les deux apps**

**(a) App compagnon, sans choix d'offre sur iOS (recommandé).** Sur iOS
(même mécanisme `store_policy.dart`) : l'écran d'abonnement devient un état en
lecture seule (offre, statut, dates, places) ; l'étape d'offre de l'onboarding
et l'action « Choisir » du snackbar disparaissent ; sur `offer_required` /
`seat_limit`, un fait neutre sans bouton ni lien. Choisir une offre se fait sur
le web, **et l'app ne le dit jamais**. Coût : une PR mobile, ses tests iOS
forcés comme au §1.6. **Conséquence produit à trancher avec** : un salon qui
ne passe que par l'iPhone ne peut plus démarrer son essai depuis l'app, et
l'app ne peut pas lui dire où le faire — soit l'essai démarre automatiquement
côté serveur à la création du salon, soit l'activation passe par
l'accompagnement (support, web). Android et le web gardent le flux actuel.

**Décision du propriétaire, 2026-10-05** — (a), chaque option recommandée de
[pro-companion-path.md](pro-companion-path.md) §11, qui la spécifie :

- **Les deux apps, pas iOS seul.** L'app Pro cesse de proposer un choix
  d'offre sur iPhone **et** sur Android, sans branche de plateforme : la
  politique de paiements de Google Play a la même règle d'incitation pour les
  abonnements numériques (raison retenue par la spec, §11 Q3 ; le texte actuel de la politique Play n'a pas été relu — UNVERIFIED, comme le note [play-store-forms.md](play-store-forms.md) §3). Le sélecteur,
  les phrases Android « … sur myweli.com » et `store_policy.dart` sont
  **supprimés**, pas conditionnés — le paragraphe ci-dessus (« même mécanisme
  `store_policy.dart` », « Android … gardent le flux actuel ») est dépassé.
- **La conséquence produit est résolue côté serveur** : quand le salon n'a
  encore aucune offre, **l'essai de 3 mois démarre à sa première mise en ligne
  réussie** — ni à la création du salon (des jours d'essai brûlés pendant la
  configuration), ni par le support. Palier par défaut : Réseau si le
  propriétaire possède déjà un salon à offre Réseau en cours, sinon Pro. Un
  salon dont l'offre a expiré n'obtient jamais un second essai (spec §3.1).
- **Les invitations d'équipe** restent liées à une offre en cours ; l'app le
  dit par une phrase neutre (« Vous pourrez inviter votre équipe une fois
  votre salon en ligne. »), sans bouton.
- **Le web** reste le seul endroit où une offre se choisit — divergence
  assumée avec « le web suit le parcours de l'app » (spec §5).

Phrase à mettre dans les notes (§8, rubrique SUBSCRIPTION) **une fois (a)
livré** — *en place au §8 depuis le 2026-10-05, suivie d'une phrase sur
l'essai qui démarre à la mise en ligne* :

```text
MyWeli Pro is a free companion app to the MyWeli service for salons (guideline 3.1.3(f)). There is no purchasing in the app and no link to, or instruction about, purchasing elsewhere: Profil > « Mon abonnement » only shows the salon's current plan and its status.
```

**(b) Achat intégré (IAP).** Vendre Pro / Business / Réseau en abonnements
auto-renouvelables : produits App Store Connect, accord « Paid Apps » avec
coordonnées bancaires et fiscales, validation serveur des reçus et des
notifications Apple, commission Apple, parité de prix avec le web. Des
semaines de travail et un modèle de facturation à refaire ; **pas pour la
v1**. Phrase correspondante, si (b) est choisi un jour :

```text
The Pro, Business and Réseau plans are auto-renewable subscriptions sold with In-App Purchase (Profil > « Mon abonnement »). The demo salon already has an active plan, so no purchase is needed to review the app.
```

**Ne jamais soumettre avec la ligne réservée** `[TO REPLACE BEFORE
SUBMITTING…]` du §8 : elle est là pour que l'oubli se voie. *2026-10-05 : elle
est remplacée par la phrase (a) (§8).*

---

## 3 · La fiche de l'app (Apps → « + » → Nouvelle app)

Rôle requis : Account Holder, Admin ou App Manager. **Créer la fiche tôt**
réserve le nom (sa disponibilité ne se connaît qu'à la création).

**La fiche existe — relue le 2026-10-05**, en lecture seule, dans App Store
Connect (navigateur du propriétaire). Ce qu'elle contient, face à ce que ce
dossier proposait :

| Champ | Dans App Store Connect (2026-10-05) | Proposé ici | Suite |
|---|---|---|---|
| **Apple ID** (adamId) | **6805272779** | — | sert au §11.5 et au §12.1 |
| Nom | « MyWeli Pro » | `MyWeli Pro — Gestion de salon` (§4) | le nom proposé reste **le choix du propriétaire**, à appliquer s'il le retient |
| Bundle ID | `com.myweli.pro` | `com.myweli.pro` | conforme |
| SKU | `myweli-pro` | `MYWELI-PRO-IOS` | **définitif** tel quel ; jamais affiché, sans conséquence |
| Langue principale | français | Français (fr-FR) | conforme |
| Catégorie | non renseignée | Business + Productivity (§5) | à remplir |
| Sous-titre | vide | `Agenda, clients, réservations` (§4) | à remplir |
| Droits sur le contenu | non renseignés | « Oui … et j'ai les droits nécessaires » (§9) | à remplir |
| Version | iOS **0.0.1**, « Prepare for Submission » (renommée de « 1.0 » le 2026-10-13, relue par l'API) | **0.0.1** (le binaire, §11.3 — la version de l'app passe de 1.0.0 à 0.0.1, décision du propriétaire le 2026-10-13, à partir du build 569) | la page s'appelait « 1.0 » : App Store Connect ne propose pour une version que les builds de même numéro, et 0.0.1 ≠ 1.0 quelle que soit sa normalisation. **Renommée « 0.0.1 » le 2026-10-13** avec l'accord du propriétaire ; reste à y choisir le build 569 (§13). Les builds 1.0.0 (≤ 565) restent dans TestFlight sous leur version. *2026-10-22 : le build **587** y est rattaché (2026-10-14, soir) et la version est **soumise, en revue**, publication manuelle (BACKLOG B0.1).* |
| TestFlight | aucun build | — | §11.5 — *2026-10-14, soir : build **587** (0.0.1) envoyé, traité `VALID`, lu comme français ; le groupe interne ne reçoit que le **587** ; ajouté à « Testeurs externes » ; **rattaché à la version 0.0.1 à la place du 581***. *2026-10-14, nuit : build **581** (0.0.1) envoyé, traité `VALID`, lu comme français ; le groupe interne ne reçoit que le **581** ; ajouté à « Testeurs externes » (disponible aussitôt ; les 569, 577 et 579 y restent) ; **rattaché à la version 0.0.1 à la place du 579***. *2026-10-13, soir : build **579** (0.0.1) envoyé, traité `VALID`, lu comme **français** par App Store Connect ; le groupe interne ne reçoit que le **579** ; ajouté à « Testeurs externes » (disponible aussitôt ; le 569 et le 577 y restent) ; **rattaché à la version 0.0.1***. *2026-10-13, après-midi : build **577** (0.0.1) envoyé, traité `VALID` ; le groupe interne ne reçoit que le **577** (il remplace le 569) ; ajouté à « Testeurs externes », où il est disponible aussitôt (la revue bêta de la 0.0.1 avait approuvé le 569 dans la journée ; le 569 y reste)*. *2026-10-13 : build **569** (**0.0.1**) envoyé, traité `VALID` ; le groupe interne ne reçoit que le **569** (il remplace le 565) ; ajouté au groupe externe « Testeurs externes » et **soumis à la revue bêta** (`WAITING_FOR_REVIEW`) — le 565, encore en attente de revue, y reste*. *2026-10-12, soir : build **565** envoyé, traité `VALID` ; le groupe interne ne reçoit que le **565** (il remplace le 560)*. *2026-10-12 : builds 551, 555 et **560** envoyés, traités `VALID` ; le groupe interne ne reçoit que le **560** (il remplace le 555)*. *2026-10-10 : builds 551 et 555 envoyés, traités `VALID` ; le groupe interne ne reçoit que le 555 (§11.6)* |

L'app consommateur « MyWeli » a aussi sa fiche (iOS 1.0, « Prepare for
Submission ») ; elle aura son propre dossier.

Le tableau qui suit est la saisie telle qu'elle était prévue avant la création
de la fiche, gardé pour l'historique :

| Champ | Valeur |
|---|---|
| Plateformes | **iOS** |
| Nom | `MyWeli Pro — Gestion de salon` (§4) |
| Langue principale | **Français** (fr-FR) — l'app ne parle que français (`supportedLocales: fr_FR`) |
| Identifiant de lot (Bundle ID) | **`com.myweli.pro`** — dans la liste (l'App ID existe, un profil App Store a été émis pour lui le 2026-08-29) |
| SKU | `MYWELI-PRO-IOS` (texte libre, jamais affiché, **définitif**) |
| Accès utilisateurs | Accès complet |

Ensuite, dans **Informations sur l'app** : **Copyright** « 2026 Sadr Eddine
Daher » — l'équipe de distribution est une personne physique (5VWKJD956A) ;
le vendeur affiché sera ce nom jusqu'à l'immatriculation de la société, et la
ligne se change avec une version ultérieure. Contrat de licence : **contrat
Apple standard**.

Après création, noter ici l'**Apple ID** de l'app (l'adamId, 10 chiffres) :
il sert à `altool --build-status` (§11) et à l'`updateUrl` iOS (§12).
*Apple ID : **6805272779** (relu dans App Store Connect le 2026-10-05).*

---

## 4 · Textes de la fiche — comptés au caractère et à l'octet

Recomptés le 2026-09-24 avec `python3` (`len(s)` et `len(s.encode())`).
Apple compte les **mots-clés en octets** (é = 2 octets) et le reste en
caractères.

| Champ | Limite | Texte | Caractères | Octets UTF-8 |
|---|---|---|---|---|
| **Nom** | 30 car. | `MyWeli Pro — Gestion de salon` | 29 | 31 |
| ↳ repli si le tiret cadratin est refusé | 30 car. | `MyWeli Pro : gestion de salon` | 29 | 29 |
| **Sous-titre** | 30 car. | `Agenda, clients, réservations` | 29 | 30 |
| ↳ variante | 30 car. | `Agenda et clientèle du salon` | 28 | 29 |
| **Mots-clés** | **100 octets** | `coiffure,coiffeur,tresses,barbier,onglerie,spa,institut,beauté,planning,rendez-vous,acompte,abidjan` | 99 | **100** (pile la limite) |
| ↳ repli si le champ refuse | 100 octets | la même liste **sans** `,abidjan` | 91 | 92 |
| **Texte promotionnel** | 170 car. | `Recevez des réservations en ligne et tenez agenda, équipe et fichier clients au même endroit — pensé pour les salons de beauté de Côte d'Ivoire.` | 144 | 152 |
| **Description** | 4000 car. | ci-dessous | 996 | 1 031 |

Règles suivies pour les mots-clés : virgules sans espace ; aucun mot déjà
dans le nom ou le sous-titre (vérifié : intersection vide) ; aucune marque ni
nom de concurrent (2.3.7). Le texte promotionnel se modifie à tout moment sans
nouvelle revue. « Nouveautés » n'existe pas pour la première version.

**Description** — texte brut (l'App Store n'interprète pas le Markdown :
intertitres en capitales, une ligne vide entre les blocs). Reprise de la
description Play Pro. Elle ne dit **rien** des offres, abonnements ou prix
(3.1.1) :

```text
L'outil de gestion des salons de beauté de Côte d'Ivoire : recevez des réservations en ligne et pilotez votre activité au quotidien.

VOTRE AGENDA, TENU TOUT SEUL
Les clients réservent sur vos créneaux réels ; vous ajoutez les rendez-vous pris au téléphone ou au comptoir en quelques gestes. Vue journée, semaine, et par membre d'équipe.

VOTRE VITRINE EN LIGNE
Photos, avant/après, logo, prestations et tarifs, horaires avec modèles prêts à l'emploi : votre page publique sur myweli.com se remplit depuis l'app.

VOTRE CLIENTÈLE, ENREGISTRÉE D'ELLE-MÊME
Chaque réservation crée ou retrouve la fiche client — historique de visites, notes, étiquettes.

VOS ACOMPTES, SANS INTERMÉDIAIRE
Le client paie l'acompte sur VOTRE Mobile Money et joint sa preuve ; vous confirmez. MyWeli ne touche jamais vos fonds.

VOTRE ÉQUIPE
Invitez manager, réception et collaborateurs, chacun avec les accès de son rôle.

Conçu pour les réalités d'ici : FCFA, communes, à domicile, réseaux lents et petits téléphones.
```

(996 caractères / 1 031 octets, 18 lignes, sans la ligne vide finale.)

---

## 5 · Adresses et catégorie

| Champ | Valeur | Vérifié |
|---|---|---|
| **URL d'assistance** (obligatoire) | `https://myweli.com/support` — affiche support@myweli.com ; ouverte dans l'app par Profil → « Aide & Support » | HTTP 200 le 2026-09-24 (le web est servi par Vercel, indépendamment de l'API) |
| **Politique de confidentialité** (obligatoire) | `https://myweli.com/politique-confidentialite` — liée dans l'app par Profil → « À propos » et sur l'écran d'inscription | HTTP 200 le 2026-09-24 |
| URL marketing (facultative) | `https://myweli.com` | — |
| **Catégorie principale** | **Business** — « Économie et entreprise » (comme « Entreprise » sur Play) | — |
| Catégorie secondaire | **Productivity** — « Productivité » (facultative) | — |

Que la boîte support@myweli.com soit réellement lue : UNVERIFIED (case §4 de
[LAUNCH.md](../LAUNCH.md) encore ouverte).

---

## 6 · Classification par âge — le questionnaire actuel

Le questionnaire Apple en vigueur (développé en 2025 : contrôles, capacités,
thèmes, médical, sexualité, violence, hasard). Répondre selon le libellé exact
à l'écran, dans l'esprit ci-dessous ; si une question n'est pas couverte :
STOP.

| Rubrique | Question | Réponse | Pourquoi |
|---|---|---|---|
| Contrôles in-app | Parental Controls | **No** | — |
| | Age Assurance | **No** | — |
| Capacités | Unrestricted Web Access | **No** | pas de WebView ; les liens s'ouvrent dans Safari (`external_link.dart`, `LaunchMode.externalApplication`) |
| | **User-Generated Content** | **Yes** | les salons publient photos et descriptions ; l'app montre les avis clients (texte, photos) — la « diffusion large de contenu créé par des utilisateurs » |
| | Social Media | **No** | — |
| | Messaging and Chat | **No** | aucune messagerie entre utilisateurs |
| | Advertising | **No** | aucune publicité |
| Thèmes matures | Profanity or Crude Humor · Horror/Fear · Alcohol, Tobacco, or Drug Use | **None** partout | — |
| Médical ou bien-être | Medical or Treatment Information | **None** | — |
| | Health or Wellness Topics | **No** | l'app gère un agenda et un catalogue ; elle ne donne aucun conseil de soin |
| Sexualité ou nudité | les trois | **None** | — |
| Violence | les quatre | **None** | — |
| Hasard | Gambling · Loot Boxes | **No** | — |
| | Simulated Gambling · Contests | **None** | — |
| — | Made for Kids | **No** | — |

Résultat attendu : **4+** (INFERRED — Apple le calcule ; s'il sort plus haut à
cause du contenu généré par les utilisateurs, l'accepter, ce n'est pas un
défaut).

**Saisi et enregistré le 2026-10-06** (questionnaire en 7 étapes, réponses
du tableau ci-dessus, propriétaire d'accord). Les deux nouvelles questions
« réseaux sociaux », lues à l'écran :

| Question (libellé Apple) | Réponse | Pourquoi |
|---|---|---|
| Social Media — « Redistribution, amplification, or interaction with user-generated content through a social feed or similar discovery method that visibly spreads content to many users. » | **No** | aucun fil social : l'app gère un salon |
| Social Media Disabled for Users Under 13 — « Users under 13 don't have access to social media capabilities… » | **No** | l'aide d'Apple : répondre **Yes** exige Social Media, User-Generated Content **et** Age Assurance à Yes ; sans fil social, la question ne s'applique pas |

Étape 7 : « Age Categories and Override » = **Not Applicable** (les CGU et la
politique de confidentialité ne fixent aucun âge minimum — vérifié dans
`web/app/cgu/page.tsx` et `web/app/politique-confidentialite/page.tsx`, ce
qu'Apple impose de refléter sinon) ; « Age Suitability URL » vide.
**Résultat : 4+** dans 172 pays ou régions, avec les équivalents locaux
Brésil « A6 », Corée « ALL », Vietnam « 00+ ».

---

## 7 · Confidentialité de l'app (App Privacy) — l'étiquette Pro

Principes :

- **« Collecter »** au sens d'Apple = transmis hors de l'appareil et conservé
  au-delà de la requête. Les sous-traitants comptent (« you or your
  third-party partners ») : Sentry et Firebase sont couverts ci-dessous.
- **Suivi (tracking) : aucun, pour toute ligne.** Aucun SDK de publicité,
  d'analytics ou d'attribution ; `NSPrivacyTracking = false` dans
  `PrivacyInfo.xcprivacy`. Pas d'invite ATT.
- **Finalité : « App Functionality » partout** — authentifier, faire
  fonctionner, prévenir la fraude (le KYC), limiter les plantages (Sentry).
  Le tableau de bord admin compte des lignes opérationnelles
  (`backend/lib/src/admin/analytics_service.dart`) sans événement de
  comportement : **pas** la finalité « Analytics » — décision prise ici, même
  réponse que Play.
- **Les données des clients des salons** que le pro saisit (nom, téléphone,
  notes) sont déclarées sous **Contact Info** et **User Content** : c'est
  l'app qui les collecte, même si elles ne concernent pas l'utilisateur.

« Do you or your third-party partners collect data from this app? » → **Yes**.

### 7.1 Données liées à l'utilisateur

| Catégorie Apple | Type | Collecté | Lié | Suivi | Finalité | Dans l'app Pro |
|---|---|---|---|---|---|---|
| Contact Info | **Name** | Oui | Oui | Non | App Functionality | nom du pro (Apple, Google, « Profil du salon » — l'inscription est sur le web depuis le 2026-10-26) ; noms des clients saisis par le salon (fiche client, réservation manuelle) |
| Contact Info | **Email Address** | Oui | Oui | Non | App Functionality | e-mail de connexion ; e-mail des membres invités |
| Contact Info | **Phone Number** | Oui | Oui | Non | App Functionality | « Téléphone du salon », WhatsApp, téléphones des clients saisis par le salon |
| Contact Info | **Physical Address** | Oui | Oui | Non | App Functionality | adresse du salon, saisie dans « Profil du salon » (publiée sur sa page) |
| Location | **Precise Location** | Oui | Oui | Non | App Functionality | le point du salon (« Utiliser ma position ») — latitude/longitude envoyées et **publiques** |
| Financial Info | **Other Financial Info** | Oui | Oui | Non | App Functionality | le numéro **Mobile Money de réception** des acomptes (« Numéro Mobile Money », paramètres d'acompte) — publié sur la page du salon |
| User Content | **Photos or Videos** | Oui | Oui | Non | App Functionality | galerie, logo, avant/après, photos d'équipe (publiques) ; images KYC (privées) |
| User Content | **Other User Content** | Oui | Oui | Non | App Functionality | prestations et tarifs, descriptions, horaires, notes clients, notes de réservation |
| Identifiers | **User ID** | Oui | Oui | Non | App Functionality | identifiant du compte (le `sub` du jeton) |
| Identifiers | **Device ID** | Oui | Oui | Non | App Functionality | le jeton push FCM (`device_tokens`) |
| Other Data | **Other Data Types** | Oui | Oui | Non | App Functionality | pièces KYC — pièce d'identité, photo du visage, RCCM, justificatif d'adresse : stockage privé, jamais publiées, lues par un admin seulement |

### 7.2 Données non liées à l'utilisateur

| Catégorie Apple | Type | Collecté | Lié | Suivi | Finalité | Dans l'app Pro |
|---|---|---|---|---|---|---|
| Diagnostics | **Crash Data** | Oui | **Non** | Non | App Functionality | Sentry ; `beforeSend` retire utilisateur, fil d'Ariane, requête et extras ; `sendDefaultPii = false` ; aucun `setUser` |
| Diagnostics | **Performance Data** | Oui | **Non** | Non | App Functionality | les événements de blocage (app hangs) de Sentry, envoyés seulement quand un blocage survient |

**« Non lié » tient à `beforeSend`** (`mobile/lib/core/observability/error_reporting.dart`) :
affaiblir le nettoyage oblige à changer ces deux lignes. Le modèle et la
version d'OS voyagent **à l'intérieur** des événements de plantage/blocage,
déjà déclarés.

### 7.3 Non déclaré — et pourquoi

- **Other Diagnostic Data** : non — les sessions de santé de version sont
  coupées depuis `68fc33c` (§1.5) ; rien d'autre ne part hors défaillance.
- **Purchase History** : **non**. L'utilisateur Pro n'achète rien dans l'app ;
  l'appel de réservation manuelle envoie des identifiants de prestations, le
  nom et le téléphone du client, et **le serveur calcule le prix**. Ce sont les
  données des clients du salon, déjà déclarées en Contact Info et User Content.
  (Le vérificateur de l'audit a rejeté la ligne « Purchase History,
  prudente » proposée par la première lentille, pour ces raisons.)
- **Payment Info** : non — aucune carte, aucun compte bancaire ; le numéro
  Mobile Money est celui où le salon *reçoit*, d'où Other Financial Info.
- **Sensitive Info** : non — la liste Apple (origine, religion, biométrie…)
  ne contient pas les pièces d'identité ; elles sont en Other Data Types (+
  Photos). La photo du visage n'est traitée par aucun procédé biométrique.
- **Coarse Location** : non — « Près de moi » choisit la commune la plus
  proche **sur l'appareil** ; seule la commune part, dans l'adresse.
- Health, Fitness, Credit Info, Contacts (aucun accès au carnet), Emails or
  Text Messages, Audio, Gameplay, Customer Support (le support se fait hors
  app), Browsing History, Search History (le serveur ne journalise que le
  chemin, jamais la requête), Product Interaction, Advertising Data, Other
  Usage Data, Environment Scanning, Hands, Head : **non**.

L'étiquette **consommateur** sera différente (sa position ne quitte pas
l'appareil) — ne pas la dériver de ce tableau.

---

## 8 · Informations pour la revue (App Review Information)

| Champ | Valeur |
|---|---|
| **Connexion requise** (Sign-in required) | **coché** |
| **Nom d'utilisateur** | `revue@myweli.test` |
| **Mot de passe** | le code à 6 chiffres `DEMO_PROVIDER_CODE` — **jamais dans ce repo ni dans le chat**, lu sur ton poste au moment de remplir (voir ci-dessous) |
| Prénom / Nom | ceux du propriétaire |
| Téléphone | au format international avec l'indicatif (`+225 …` ou `+33 …`) — le champ refuse les chiffres seuls |
| E-mail | celui du propriétaire |
| Pièce jointe | aucune |

```bash
gcloud secrets versions access latest --secret=DEMO_PROVIDER_CODE --project myweli
```

Avant de coller : **se connecter avec ce code** sur le build TestFlight contre
la production (§11.6). Apple exige un compte démo qui « must not expire » :
**ne jamais faire tourner le code** tant qu'une version est en revue ou que des
mises à jour sont attendues. Si Secret Manager ne répond pas (facturation), il
n'y a pas d'autre source connue du code — UNVERIFIED qu'une copie existe
ailleurs ; si le secret a été perdu avec le projet, il faut en frapper un
nouveau et redéployer.

**Verrou de suppression du compte démo — vérifié en production : le 2026-10-14.**

*Le contrôle, tel qu'il a été fait.* Déploiement en production avec l'accord
explicite du propriétaire, le 2026-10-14 à 01:06 UTC (run `38493842296`,
image `3d88d0e` construite par la fusion de #585) ; la révision qui sert
100 % du trafic, `myweli-api-00037-zzq`, porte l'empreinte
`sha256:8f185f6b…` de cette image — la veille c'était `df5a1213…` ;
`api.myweli.com/health` répond 200. Puis, à 01:09 UTC, **l'essai dans l'app**,
sur le compte démo, dans le simulateur (build de débogage contre la
production) : cinq rendez-vous confirmés à venir étaient en place — avec
eux, même l'ancien code aurait refusé sans rien supprimer —, « Supprimer mon
compte » → `SUPPRIMER` → « Supprimer définitivement », une fois. **L'app a
répondu « Compte de démonstration — cette action est désactivée. »** ; le
compte est resté connecté, « Accueil » et les cinq rendez-vous du jour sont
inchangés. *Non vérifié en production* : qu'un compte ordinaire se supprime
toujours (seuls les tests le montrent ; l'essai demande un compte neuf, donc
le propriétaire — §10.1, point 6, de la spec).

**2026-10-26 — un seul bloc : celui du build renvoyé.** Apple a refusé la
0.0.1 (587) sous 3.1.1 : « Remove the account registration features for
business and organizations » (BACKLOG B0.11,
[pro-app-login-only.md](pro-app-login-only.md)). Les notes changent avec
l'app, et partent des notes amendées — le verrou du compte démo est vérifié
en production depuis le 2026-10-14 (la ligne ci-dessus), elles étaient donc
déjà les bonnes. Deux passages diffèrent d'elles : ACCOUNT DELETION ne
demande plus de créer un compte **dans l'app** (le compte de test se crée
sur myweli.com, puis se supprime dans l'app) ; et la dernière rubrique,
SALON ACCOUNTS, remplace le paragraphe « Créer un compte » → « Inscription
Pro » : l'app connecte seulement, « S’inscrire sur myweli.com » ouvre
l'inscription web dans le navigateur, une identité sans compte lit la
phrase de l'app, les invités rejoignent leur salon. Le lien vers le site
est dit franchement : le propriétaire le garde en connaissance de cause
(décision 42). App Store Connect reçoit ce bloc quand le propriétaire remplit
ses coordonnées et le code démo (§13.1) — l'API refuse de remplacer les
notes sans eux (409). La Play Console ne parlait pas d'inscription : son
texte ne change pas ([play-store-forms.md](play-store-forms.md) §2).

La ligne datée ci-dessus reste : `mobile/test/infra/app_review_notes_test.dart`
la lit, et n'autorise un bloc « coller tel quel » qui promet le verrou que
si elle est datée. *Le test ne voit pas la production : il lit la ligne.*

**Notes** (coller tel quel — le build renvoyé, 2026-10-26). Poids : **3 853 octets**
(3 793 caractères) — sous la limite de 4 000. Compté par script sur le
texte exact du bloc, sans le saut de ligne final ; le test le recompte à
chaque CI et échoue si ce paragraphe ment.
*Historique : 3 476 octets (notes en vigueur, 2026-10-11) ; 3 648 (notes
amendées, 2026-10-13, le verrou) ; 3 853 le 2026-10-26 — les notes amendées,
ACCOUNT DELETION et SALON ACCOUNTS réécrites pour 3.1.1. Les deux anciens
blocs sont retirés : celui-ci les remplace.*

```text
MyWeli Pro is the business app for beauty salons in Côte d'Ivoire (French UI). Salon owners and their staff manage their agenda, clients, services, photos and opening hours; their customers book through the separate MyWeli app and myweli.com.

HOW TO SIGN IN (demo account)
The app signs in with an e-mail address and a 6-digit code, not a password. The demo account uses a FIXED code that does not expire, so the Password field above contains that 6-digit code.
1. On the « Espace Pro » screen, type revue@myweli.test in the « Votre e-mail » field.
2. Tap « Continuer avec e-mail ». No e-mail is sent: the .test domain cannot receive mail, and the fixed code replaces the one normally e-mailed.
3. Type the code from the Password field in « Code à 6 chiffres », then tap « Se connecter ».
You land on « Maison Nala », a complete demo salon: agenda with bookings, manual bookings, clients, services, photos, availability, journal and data export all work. The « Profil » icon at the top right of the « Accueil » screen opens the account menu.

Three actions are deliberately disabled for this shared demo account and say so on screen (« Compte de démonstration — cette action est désactivée. »): publishing the salon publicly, inviting team members by e-mail (it would send e-mail to third parties), and deleting the account (later reviews use it).

PAYMENTS
No payment of any kind happens in the app. A salon may ask its customers for a booking deposit; the customer pays it directly to the salon's own Mobile Money account, outside the app, for an in-person beauty service, and the salon confirms it in the app. MyWeli never holds or moves money.

SUBSCRIPTION
MyWeli Pro is a free companion app to the MyWeli service for salons (guideline 3.1.3(f)). There is no purchasing in the app and no link to, or instruction about, purchasing elsewhere: Profil > « Mon abonnement » only shows the salon's current plan and its status. A new salon's free trial starts automatically when the salon goes live; nothing is chosen or bought in the app.

IDENTITY DOCUMENTS (Profil > « Vérification »)
Uploading identity documents is optional. It is needed only to switch on customer deposits, so that deposits go only to verified salons. The documents are stored privately, never published, and read only by a MyWeli administrator.

USER CONTENT
Customer reviews shown under « Avis » are moderated by MyWeli: customers report reviews from the MyWeli app, administrators can hide a review or suspend a salon, and a salon reaches support from Profil > « Aide & Support ».

LOCATION
Location is requested only when the owner taps « Utiliser ma position » (Profil > « Profil du salon ») or « Près de moi » in the commune list, to place the salon's pin on the map or find its commune. The pin is the salon's public business address.

ACCOUNT DELETION
Profil > « Supprimer mon compte », then type SUPPRIMER to confirm. The shared demo account cannot be deleted: after the SUPPRIMER confirmation, the app answers « Compte de démonstration — cette action est désactivée. » and you stay signed in. To test deletion end to end, create a salon account on myweli.com (see SALON ACCOUNTS), sign in to the app with it, then delete it here. If that account has upcoming appointments, the app first asks to finish or cancel them.

SALON ACCOUNTS
The app only signs in to existing salon accounts, with an e-mail code, Apple or Google. It no longer creates accounts or salons: salons sign up on the MyWeli website, and the sign-in screen's « S’inscrire sur myweli.com » opens that page in the browser. An identity with no account is told « Aucun compte MyWeli Pro n’est associé à cette adresse. » Team members invited by their salon join it from the sign-in screen. Please use the demo account above to see a populated salon.
```

Libellés relus dans le code le 2026-09-24 : `pro_login_screen.dart`
(« Espace Pro », « Votre e-mail », « Continuer avec e-mail », « Code à 6
chiffres », « Se connecter » ; *2026-10-26* : « S’inscrire sur myweli.com », et la
phrase sans compte, la constante `kNoProAccountMessage`), `dashboard_screen.dart` (« Accueil », icône
« Profil »), `pro_profile_screen.dart` (« Profil du salon », « Vérification »,
« Mon abonnement », « Aide & Support », « Supprimer mon compte », mot
`SUPPRIMER`), `pro_salon_profile_screen.dart` (« Utiliser ma position »),
`commune_picker_sheet.dart` (« Près de moi »), `reviews_screen.dart` (« Avis »).
**Si un libellé change, ces notes changent dans la même PR.** *2026-10-13 :
la phrase « Compte de démonstration — cette action est désactivée. » est la
constante `demoAccountLockedMessage` (`team_error_messages.dart`) ; le test
cité plus haut tient les deux blocs à cette constante.*

**Corrigé le 2026-10-05** (critique d'exhaustivité de l'audit de la voie
compagnon, puis relu dans le code) :

- *Apple et Google* : la note disait qu'ils « create a new, empty salon
  account (onboarding) ». Faux : les deux routes sont **de connexion
  seulement** (`backend/routes/auth/provider/apple.dart`, `google.dart` —
  « LOGIN-ONLY ») ; une identité inconnue revient en `provider_not_found`, et
  l'écran de connexion propose alors « Créer un compte » → `/pro/register`
  (`pro_login_screen.dart`), le formulaire « Inscription Pro »
  (`pro_register_screen.dart` : nom, type, téléphone et adresse de
  l'entreprise exigés avant « S’inscrire avec Apple » / « S’inscrire avec
  Google »), qui ouvre ensuite « Accueil », pas l'onboarding. *2026-10-26 :
  ce formulaire a quitté l'app — Apple a refusé la 0.0.1 sous 3.1.1 pour
  lui ([pro-app-login-only.md](pro-app-login-only.md)).*
- *Refus démo* : la phrase « Compte de démonstration — cette action est
  désactivée. » que la note promet **n'existait dans aucune surface de
  l'app** — un refus démo affichait « Une erreur est survenue. » (publication)
  ou « Une erreur est survenue. Réessayez. » (invitation). Elle est
  **implémentée sur cette branche** ([pro-companion-path.md](pro-companion-path.md)
  §2.2) ; la voir à l'écran sur le build TestFlight avant de soumettre
  (§11.6).

Pourquoi la rubrique ACCOUNT DELETION est écrite ainsi (2026-10-13) — celle
des **notes amendées**, vraie une fois le verrou en production : **le
serveur refuse la suppression à l'identité démo** — 403 `demo_account_locked`
sur `DELETE /me/provider`, évalué avant le contrôle des rendez-vous à venir,
donc la même réponse sept jours sur sept
([demo-account-deletion-lock.md](demo-account-deletion-lock.md)). L'entrée
« Supprimer mon compte » reste visible pour le compte démo : le relecteur
doit voir que la suppression existe (5.1.1(v)). Le refus arrive après la
confirmation `SUPPRIMER`, avec la phrase que la note cite, et le relecteur
reste connecté. La suppression de bout en bout se teste sur un compte neuf —
*depuis le 2026-10-26 créé sur myweli.com, l'app ne créant plus de compte
(3.1.1)* — et la dernière phrase vaut
pour ce compte-là : un compte ordinaire qui a des rendez-vous à venir doit
d'abord les terminer ou les annuler.

*Avant ce verrou, et tant qu'il n'est pas en production* : la suppression
n'est pas verrouillée pour l'identité démo, et la remise à zéro hebdomadaire
ne crée des rendez-vous à venir qu'à J+1 et J+2
(`backend/lib/src/demo/demo_reset_service.dart`) — environ cinq jours sur
sept rien n'arrête une suppression du compte démo, et les autres jours le
compte peut annuler ces deux rendez-vous lui-même. C'est pourquoi les notes
en vigueur se bornent à demander de ne pas le supprimer.

Pourquoi la rubrique IDENTITY DOCUMENTS : 5.1.1(ix) veut que les apps qui
demandent des données sensibles soient soumises par une personne morale ;
l'équipe est une personne physique et la société n'est pas encore
immatriculée. Le KYC est facultatif et ne sert qu'aux acomptes — c'est ce que
la note dit au relecteur (risque assumé, §14).

---

## 9 · Conformité, tarif, disponibilité

| Formulaire | Réponse | Pourquoi |
|---|---|---|
| **Conformité export** | **déjà répondue par le binaire** : `ITSAppUsesNonExemptEncryption = false` (`Info.plist`, présent dans l'IPA) | HTTPS/TLS du système uniquement, plus un SHA-256 pour le nonce Apple ; App Store Connect ne pose pas la question à l'envoi ; aucune déclaration de chiffrement française à fournir |
| **Droits sur le contenu** | « **Oui**, l'app contient, affiche ou accède à du contenu tiers, **et j'ai les droits nécessaires** » | contenu publié par les salons et les clients sous les CGU (`/cgu`) ; tuiles de carte OSM/CARTO avec attribution |
| **Prix** | **Gratuit** — **fait le 2026-10-06** (pays de base États-Unis, 0,00 $, 175 pays) | aucun achat intégré (aucune dépendance StoreKit) |
| **Disponibilité** | **Côte d'Ivoire uniquement** — **fait le 2026-10-06** (« Available on App Release », tous les autres pays « Not Available ») | le périmètre réel : l'arbre des localités et le catalogue Mobile Money ne contiennent que la Côte d'Ivoire, donc un salon d'un autre pays ne peut pas choisir sa localité ni être publié ; le storefront CIV a le français par défaut, donc une fiche en français seul convient. **Ajouter un pays = un réglage ici, sans build ni revue**, une fois ses données saisies (vague 1 de [modules/multi-pays.md](../modules/multi-pays.md) : Sénégal, Mali, Burkina Faso, Togo) ; en retirer un après la sortie prive ses salons de l'app — d'où l'ordre « d'abord la CI » (décision du propriétaire, 2026-10-06). Les testeurs TestFlight ne sont pas concernés. |
| **Apps iPhone et iPad sur Mac (Apple silicon)** | **décoché le 2026-10-06** | jamais testé ; le profil rend l'app éligible par défaut |
| **Apple Vision Pro** | **décoché le 2026-10-06** | idem (le profil liste iOS, xrOS, visionOS) |
| **Publication de la version** | **« Publier manuellement cette version »** | l'approbation ne doit pas publier : la sortie publique attend la production rétablie et stable (§0) |
| Publication progressive | sans objet pour la première version (0.0.1) | elle s'applique aux **mises à jour** (utilisateurs en mise à jour automatique) ; à activer dès la version suivante ([LAUNCH.md](../LAUNCH.md) §6.2) |

### 9.1 Statut de professionnel UE (DSA) — décision du propriétaire

Le 2026-10-05, App Store Connect affiche : le statut de professionnel
(*trader status*, Digital Services Act) doit être fourni pour soumettre de
nouvelles apps **distribuées dans l'UE**. Deux options :

1. **Déclarer le statut de professionnel.** Apple publie alors une adresse, un
   téléphone et un e-mail sur la fiche de l'app dans les storefronts UE.
   L'équipe de distribution étant une personne physique (5VWKJD956A, §3), ce
   seraient les coordonnées du propriétaire (INFERRED).
2. **Ne pas distribuer dans l'UE** : garder les storefronts UE exclus dans
   *Tarifs et disponibilité* — ce que la ligne « Disponibilité » ci-dessus
   prévoit déjà (Côte d'Ivoire uniquement).

**Décision du propriétaire, 2026-10-06 : l'option 1, professionnel.** La
réponse vaut pour **tout le compte développeur** (les deux apps). Saisi le
2026-10-06 dans Business → « Complete Compliance Requirements » : l'adresse
est celle du compte Apple, l'e-mail et le téléphone sont ceux du propriétaire
(choisis par lui, en sachant qu'ils s'affichent sur les fiches UE). L'e-mail
puis le téléphone ont été **vérifiés par code**. L'étape « Identification
Documents » — des pièces d'identité, qu'aucun agent ne manipule — a été faite
par le propriétaire le 2026-10-06 (un certificat de résidence). **Constaté le
même jour dans Business → Compliance : « Digital Services Act », 27 pays ou
régions, « In Review »**, et le bandeau rouge a disparu. Reste la décision
d'Apple ; une demande de pièce complémentaire arriverait par e-mail.

---

## 10 · Captures d'écran

> **Remplacé le 2026-10-13 par [pro-app-store-screenshots.md](pro-app-store-screenshots.md).**
> Apple exige désormais le jeu **« iPhone with Dynamic Island (medium
> display) » — 1206 × 2622** (page de spécifications relue le 2026-10-12) ; un
> jeu 6,9 pouces seul ne remplit plus la case obligatoire. Les 8 captures
> légendées sont faites, dans les deux tailles (1206 × 2622 et 1320 × 2868),
> par `tool/app_store_screenshots/compose.py`. Le texte ci-dessous est
> l'ancien plan, gardé pour l'historique.
>
> **2026-10-13, soir : validées par le propriétaire et téléversées** (§13.1).
> Et la dernière phrase de cet ancien plan — « aperçus vidéo : facultatifs,
> non prévus » — ne tient plus : le propriétaire en veut un, placé avant les
> captures. Le film recommandé est **validé par le propriétaire le
> 2026-10-13** : [pro-app-preview.md](pro-app-preview.md).

~~L'app est iPhone uniquement (§1.2) : **aucun jeu iPad**. Un seul jeu, **6,9
pouces**, portrait, **1320 × 2868** (ou 1290 × 2796 ; 1260 × 2736 est aussi
accepté) ; Apple en dérive les tailles plus petites.~~ **1 à 10** images, JPEG ou
PNG, **sans canal alpha ni transparence**.

**Sur le salon démo « Maison Nala »** (logo réel et snapshot recapturé le 2026-10-11, §0 #4),
un jour où l'agenda est rempli. Ordre proposé :

1. « Accueil » — le tableau de bord du jour.
2. L'agenda, vue journée, avec des rendez-vous.
3. Nouvelle réservation manuelle (prestations choisies, client).
4. Une fiche client (historique, notes).
5. Les prestations (catalogue, tarifs en FCFA).
6. Les disponibilités (horaires, modèles).
7. Photos / avant-après.
8. L'aperçu de la page publique.

**À ne pas montrer** : « Mon abonnement » et tout écran d'offre (§2), l'écran
KYC, un message « Compte de démonstration — … », une alerte système.

**Capture depuis le simulateur** (après la licence Xcode, §11) — la
production doit répondre :

```bash
open -a Simulator
xcrun simctl list devices available | grep "Pro Max"     # classe iPhone 17 Pro Max (16 Pro Max convient aussi) : 1320 × 2868
SIM="iPhone 17 Pro Max"                                   # le nom exact tel que listé ci-dessus
xcrun simctl boot "$SIM"
cd "/Users/sadreddinedaher/beauty app/mobile"
flutter run --flavor pro -t lib/main_pro.dart -d "$SIM" \
  --dart-define=USE_API_BACKEND=true --dart-define=API_BASE_URL=https://api.myweli.com
# connecté en revue@myweli.test, sur chaque écran :
xcrun simctl status_bar booted override --time 9:41 --dataNetwork wifi --wifiBars 3 \
  --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl io booted screenshot ~/Desktop/pro-01-accueil.png
sips -g pixelWidth -g pixelHeight -g hasAlpha ~/Desktop/pro-01-accueil.png   # 1320 × 2868, hasAlpha: no
# si hasAlpha: yes → un JPEG n'a pas de canal alpha :
sips -s format jpeg -s formatOptions 90 ~/Desktop/pro-01-accueil.png --out ~/Desktop/pro-01-accueil.jpg
```

Le build de débogage n'affiche pas de bandeau DEBUG
(`debugShowCheckedModeBanner: false` dans `main_pro.dart`). Mettre le
simulateur en français (Réglages → Général → Langue) pour que rien d'anglais
n'apparaisse. Aperçus vidéo : facultatifs, non prévus.

---

## 11 · Build et envoi — les commandes, dans l'ordre

Pré-requis : facturation GCP rétablie (le script lit `MOBILE_SENTRY_DSN` dans
Secret Manager et s'arrête sinon — ne **pas** contourner en construisant sans
DSN), la PR de ce dossier fusionnée, `main` à jour et arbre propre.
*2026-10-05 : la PR de ce dossier (#550) est fusionnée — squash `f6ffb585`.
S'y ajoutent la PR de la voie compagnon ([pro-companion-path.md](pro-companion-path.md),
construite le 2026-10-05) fusionnée, et son backend **déployé en production avant l'envoi en
revue** (feu vert du propriétaire). Depuis « Accueil », le relecteur peut
ouvrir « Configurer mon profil » et mettre son compte neuf en ligne. Sans ce
backend, la publication serait refusée (409 `missing: ['offer']`) et il
lirait « …l’offre de votre salon n’est plus active. » pour une offre qui n'a
jamais existé (spec §9.4).*
*2026-10-22 : ces pré-requis sont remplis — facturation rouverte le
2026-10-06, voie compagnon fusionnée (#551) et en production. Le build 587
a été construit puis soumis (§11.5).*

### 11.1 La machine

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version            # attendu : Xcode 27.0, Build version 27A266a
flutter doctor -v
```

**Constaté le 2026-10-05** : Flutter 3.44.9 construit avec Xcode 27, à une
condition. Xcode 27 traite une cible de déploiement inférieure à iOS 15 comme
une **erreur** (Xcode 26, celui de la CI, n'en fait qu'un avertissement), et le
`Flutter.podspec` généré dit 13.0 — une cible que `podhelper` ne corrige pas,
puisqu'elle est Flutter lui-même. Le `post_install` du Podfile supprime ce
réglage, qui hérite alors du 15.0 du projet Pods ; épinglé par
`mobile/test/infra/ios_store_readiness_test.dart`, car la CI ne voit pas
l'échec. Le binaire non signé de ce jour (`flutter build ios --release
--flavor pro --target lib/main_pro.dart --no-codesign`) a été lu :
`UIDeviceFamily` `[1]`, les trois phrases d'autorisation Pro résolues, aucune
`$(…)` restante, `CFBundleLocalizations` `[fr]`, `MinimumOSVersion` 15.0,
aucun DKImagePickerController / DKPhotoGallery / SwiftyGif /
TOCropViewController, et un `PrivacyInfo.xcprivacy` dans chacun des 32
bundles de ressources ainsi que dans Flutter et Sentry. Ce binaire n'est
**pas** envoyable (ni DSN, ni numéro de build, ni signature) : seul le
§11.2 produit l'IPA.

**Pas de repli sur l'IPA 536** : il est périmé (§1). Dans Xcode → Réglages → Comptes, l'équipe **SADR EDDINE DAHER
(5VWKJD956A)** doit être connectée : la signature « Cloud Managed Apple
Distribution » passe par ce compte (seule une identité de développement est
dans le trousseau).

### 11.2 Le build

```bash
cd "/Users/sadreddinedaher/beauty app"
git checkout main && git pull --ff-only
export ASC_KEY_ID=<KEY_ID> ASC_ISSUER_ID=<ISSUER_ID>    # la clé d'API du §11.4
./tool/release_build.sh ios pro
# → mobile/build/ios/ipa/MyWeli-pro.ipa (et DistributionSummary-pro.plist)
# → mobile/build/ios/archive/Runner-pro-<N>.xcarchive
```

*Depuis B9.2 (2026-10-25) :* le script **refuse** un arbre qui n'est pas
propre ou un HEAD qui n'est pas `origin/main` (il le récupère d'abord), et,
pour iOS, l'absence d'`ASC_KEY_ID` / `ASC_ISSUER_ID` — avant de lire le moindre
secret. Après le build, il **range l'archive** par saveur et par build,
**valide l'IPA** auprès d'App Store Connect (`altool --validate-app`) — un
refus arrête tout — puis imprime l'envoi des symboles (Dart **et** dSYM de
l'archive), l'association des commits de la version (`set-commits`) et la
commande d'envoi.

Le script choisit `lib/main_pro.dart` (`--target`), injecte le DSN sans
l'afficher, numérote le build au nombre de commits, obfusque et écrit les
symboles Dart dans `mobile/build/symbols/pro/`.

~~**Tout de suite après** — copier l'archive sous `Runner-pro-$N.xcarchive`~~ :
le script le fait depuis B9.2.

**Jamais** Produit → Archiver dans Xcode sur le schéma `pro` :
`Flutter/Generated.xcconfig` contient les entrées du **dernier** `flutter
build` (aujourd'hui `FLUTTER_TARGET=lib/main.dart`, `FLAVOR=consumer`), donc
Xcode compilerait l'app **consommateur** sous l'identité Pro.

**La signature passe par le compte Apple ouvert dans Xcode** (constaté le
2026-10-10). L'export de l'IPA a échoué deux fois en « No Accounts » / « No
signing certificate » : la session du compte dans Xcode avait expiré. La clé
d'API du §11.4 ne remplace pas ce compte : avec son rôle **App Manager**,
Apple refuse la signature gérée dans le cloud (« Cloud signing permission
error ») — il faudrait le rôle Admin, et on ne l'élargit pas pour ça. Le
remède : Xcode → Réglages → Comptes → le compte → « Download Manual
Profiles », puis relancer le script.

### 11.3 Vérifier l'IPA — avant tout envoi

```bash
cd "/Users/sadreddinedaher/beauty app/mobile"
IPA=build/ios/ipa/MyWeli-pro.ipa
unzip -p "$IPA" Payload/Runner.app/Info.plist | plutil -p - | grep -E -A3 \
  'CFBundleIdentifier|CFBundleName|CFBundleShortVersionString|CFBundleVersion|CFBundleLocalizations|CFBundleDevelopmentRegion|UISupportedInterfaceOrientations"|UIDeviceFamily|NSLocationWhenInUse|NSCameraUsage|NSPhotoLibraryUsage|ITSAppUsesNonExempt'
unzip -l "$IPA" | grep -oE 'Payload/Runner\.app/[^/]+\.lproj/' | sort -u               # Base.lproj et fr.lproj, rien d'autre
unzip -l "$IPA" | grep -c PrivacyInfo.xcprivacy
unzip -l "$IPA" | grep -cE 'DKImagePickerController|DKPhotoGallery'     # doit afficher 0
unzip -l "$IPA" | grep -i 'file_picker' | grep PrivacyInfo               # le manifeste de file_picker est là
unzip -p "$IPA" Payload/Runner.app/Frameworks/App.framework/App | LC_ALL=C grep -a -c '/pro/dashboard'   # > 0 : c'est l'app Pro
D=$(mktemp -d) && unzip -q "$IPA" -d "$D" && codesign -d --entitlements - "$D/Payload/Runner.app"
```

*Ajouté le 2026-10-05 — la voie compagnon, vérifiée dans le binaire*
([pro-companion-path.md](pro-companion-path.md) §8, qui explique la liste, les
trois encodages et ce qui n'y figure pas exprès). Aucune phrase retirée ne doit
y être, et chaque nouvelle phrase doit y être : ces témoins prouvent que le
fichier contient bien le texte de l'app.

```bash
unzip -p "$IPA" Payload/Runner.app/Frameworks/App.framework/App | python3 -c '
import sys
b = sys.stdin.buffer.read()
def n(p):
    found = set()
    for e in ("utf-8", "utf-16-le", "latin-1"):
        try: found.add(p.encode(e))
        except UnicodeEncodeError: pass
    return sum(b.count(x) for x in found)
gone = ["Choisir mon offre", "Changer d’offre", "Choisissez votre offre", "mois offerts", "Tarif personnalisé", "Réactivez votre offre", "Activez votre offre", "Passez à l’offre", "activer votre offre", "se gère depuis votre espace", "Le changement d’offre", "Votre salon reste gratuit", "Chaque salon a sa propre offre", "Contactez-nous", "Paiement à jour", "Choix impossible", "/mois", "Sur devis", "Nous contacter", "FCFA par mois", "Abonnement Mensuel", "3,500"]
new = ["Pas encore d’offre active", "Votre offre démarre à la mise en ligne", "Période de grâce jusqu’au", "La mise en ligne est indisponible", "Compte de démonstration — cette action est désactivée.", "Vous pourrez inviter votre équipe", "Les invitations sont indisponibles", "L’ajout de salons", "Nombre maximal de salons atteint."]
bad = [p for p in gone if n(p)] + [p for p in new if not n(p)]
print("ÉCHEC :", bad) if bad else print("OK :", len(gone), "phrases à 0,", len(new), "témoins présents")
'
```

Le script a été vérifié le 2026-10-05 sur le binaire du build non signé de
18:03 : il affiche `OK`. Il a aussi été vu échouer dans les deux sens : avec
« Changer d’offre » ajouté en UTF-16, puis sur un fichier tronqué où les
témoins manquent.

| Attendu | Valeur |
|---|---|
| `CFBundleIdentifier` | `com.myweli.pro` |
| `CFBundleName` | `MyWeli Pro` |
| `CFBundleShortVersionString` / `CFBundleVersion` | **`0.0.1`** (depuis le build 569 ; `1.0.0` jusqu'au 565) / **≥ 581** |
| `UIDeviceFamily` | **`[1]`** |
| `CFBundleLocalizations` | **`[fr]`** |
| `CFBundleDevelopmentRegion` | **`fr`** (depuis le build 579 ; `en` jusqu'au 577) |
| dossiers de langue à la racine de `Runner.app` | **`Base.lproj` et `fr.lproj`**, aucun autre |
| `UISupportedInterfaceOrientations` (la clé iPhone, sans `~ipad`) | **`[UIInterfaceOrientationPortrait]`** |
| `NSLocationWhenInUseUsageDescription` | « MyWeli Pro utilise votre position pour placer votre salon sur la carte et trouver votre commune. » |
| caméra / photos | les deux textes Pro du §1.3 |
| `ITSAppUsesNonExemptEncryption` | `false` |
| DK… | **0** occurrence |
| phrases de la voie compagnon | `OK : 22 phrases à 0, 9 témoins présents` |
| droits (entitlements) | `aps-environment = production`, `com.apple.developer.applesignin`, `get-task-allow = false`, `beta-reports-active = true` |

Un seul écart : on ne l'envoie pas.

### 11.4 L'identifiant d'envoi (une fois)

L'audit avait classé « aucun identifiant d'envoi sur ce Mac » en bloquant ;
**réfuté** : le compte Apple connecté dans Xcode peut envoyer. On retient
pourtant une clé d'API, qui n'oblige pas à passer par Xcode :

1. App Store Connect → Utilisateurs et accès → Intégrations → **App Store
   Connect API**. Si c'est la première fois, l'**Account Holder** clique
   « Demander l'accès ».
2. **Clés d'équipe** → Générer une clé, accès **App Manager**. Noter le **Key
   ID** et l'**Issuer ID** (en haut de la page). Télécharger
   `AuthKey_<KEY_ID>.p8` — **téléchargeable une seule fois**.
3. Ranger, jamais dans le repo :

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
```

Le `.p8` déjà présent dans `~/Downloads` (2026-08-06) est, selon toute
vraisemblance, la **clé APNs** créée pour Firebase, pas une clé d'API App Store
Connect (INFERRED) : ne pas l'utiliser ici ; le ranger ailleurs en `chmod 600`.

### 11.5 Valider, envoyer, suivre

*Depuis B9.2, la validation est faite par `release_build.sh`, et la commande
d'envoi n'est imprimée qu'après elle.* À la main, pour mémoire :

```bash
cd "/Users/sadreddinedaher/beauty app/mobile"
xcrun altool --validate-app build/ios/ipa/MyWeli-pro.ipa --api-key <KEY_ID> --api-issuer <ISSUER_ID>
xcrun altool --upload-package build/ios/ipa/MyWeli-pro.ipa --api-key <KEY_ID> --api-issuer <ISSUER_ID> --wait --show-progress
xcrun altool --build-status --delivery-id <DELIVERY_UUID_IMPRIMÉ_PAR_L_ENVOI> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

**Une fois le build traité, lire la langue qu'Apple y a vue** — c'est la
ligne « Langues » de la fiche, et rien de local ne la montre :
`GET /v1/builds/<id>?include=buildBundles`, attribut `locales`. Attendu :
**`["fr"]`**. Les builds 569 et 577 donnent `["en"]`
([ios-language-and-orientation.md](ios-language-and-orientation.md) §8.3). Une
autre valeur : on ne soumet pas ce build. **Le build 579 donne `["fr"]`** (lu
le 2026-10-13, et le 577 relu au même moment : `["en"]`).

*Corrigé le 2026-10-09 :* `--build-status` exige `--delivery-id` (ou
`--bundle-short-version-string` avec `--apple-id`/`--bundle-version`) ; la
forme précédente échouait (`Expected delivery ID argument is missing`). Clé
d'API créée le 2026-10-09 : équipe, rôle **App Manager**, nom
`myweli-ci-upload`, Key ID `SRP86N339X`, Issuer ID
`c83c2a4a-ebe8-43df-879c-c31bffbe692b` (identifiants, pas des secrets — le
`.p8` reste dans `~/.appstoreconnect/private_keys/`). Build 551 : validé,
envoyé (delivery `b953e22a-f2c3-41be-8570-25ec41a62524`), traité `VALID` en
deux minutes — puis l'e-mail **ITMS-90683** (texte « Always » manquant, voir
§1) : corrigé, build suivant. **Build 555** (#559, le texte « Always » par
saveur) : IPA relue au §11.3 (la clé
`NSLocationAlwaysAndWhenInUseUsageDescription` présente), validé, envoyé le
2026-10-10 (delivery `47f7ae26-c09c-430c-8c64-cba9af151085`), traité
`VALID`, conformité export déjà répondue (`usesNonExemptEncryption` faux).
~~C'est le build à soumettre~~ — remplacé par le 560 (ci-dessous) ; le 551
reste dans TestFlight, jamais soumis.

**Build 560** (2026-10-12, depuis `main` après #562–#567 ; le numéro compte les
commits, d'où 560 et non 556) : la carte (clé CARTO, #563), l'animation
d'ouverture « MyWeli Pro » (#564), la photo de couverture du salon (#565) et
la correction des déconnexions au redémarrage (#562). IPA relue au §11.3 :
1.0.0 (560), iPhone seul, `fr`, les textes de position dont « Always »,
entitlements de production, l'asset `myweli_loader_mixed_pro.json` présent,
35 manifestes de confidentialité ; la **clé d'app CARTO est dans le binaire**
(une occurrence dans `App.framework/App`, comparée sans l'afficher), la clé
web n'y est pas, un témoin inventé non plus. Validé, envoyé, traité `VALID`
(build `d7279396-17f1-402b-b76c-566cd3a7c4fa`), archive rangée en
`Runner-pro-560.xcarchive`. ~~C'est le build à soumettre~~ — remplacé par le
565 (ci-dessous) après les retours du propriétaire sur l'iPhone : l'animation
se fermait avant la fin, et la page salon n'avait pas de carte.

**Build 565** (2026-10-12 au soir, depuis `main` à `75503243`, après #569 et
#570) : l'animation d'ouverture joue **un tour complet du logo** puis marque
une pause avant l'app (#569), la page salon montre **une carte de
l'adresse** dans « Contact » et « Voir sur la carte » remarche (#570), les
crédits de la carte du profil Pro s'ouvrent en feuille, hors du bouton « Me
localiser ». IPA relue au §11.3 : 1.0.0 (565), `com.myweli.pro`, iPhone seul,
`fr`, les textes de position dont « Always », `ITSAppUsesNonExemptEncryption`
faux, entitlements de production (`aps-environment` production,
`get-task-allow` faux, `beta-reports-active` vrai), l'asset
`myweli_loader_mixed_pro.json` présent, 35 manifestes de confidentialité ; la
clé d'app CARTO dans le binaire (une occurrence, comparée sans l'afficher), la
clé web absente, un témoin absent. `altool --validate-app` réussi, envoyé
(delivery `10b428cf-76e5-4ccd-a805-277e54bb802f`), traité `VALID`, état bêta
`READY_FOR_BETA_TESTING` ; archive rangée en `Runner-pro-565.xcarchive`.
~~C'est le build à soumettre~~ — remplacé par le 569 (ci-dessous).

**Build 569** (2026-10-13, depuis `main` à `79bfcf1f`, après #573, #574 et
#575) — **version 0.0.1** (décision du propriétaire ; 1.0.0 jusqu'au 565) :
« Nouveau » au lieu de « ★ 0.0 · 0 avis » (#573), les quatre défauts
d'affichage vus au tournage — la date « Dernière », le numéro brut,
« Réessayer », les cartes de l'accueil — et « Client sans numéro », sans
interrupteur SMS (#574). Avant l'envoi, une revue contradictoire de tout ce
qui a changé depuis le 565 (quatre relecteurs, un sceptique par domaine, un
critique d'exhaustivité) : **aucun bloquant** ; les défauts confirmés sont
listés pour le build suivant. IPA relue au §11.3 : **0.0.1 (569)**,
`com.myweli.pro`, iPhone seul, `fr`, les textes de position dont « Always »,
`ITSAppUsesNonExemptEncryption` faux, entitlements de production
(`aps-environment` production, `get-task-allow` faux, `beta-reports-active`
vrai, Sign in with Apple), l'asset `myweli_loader_mixed_pro.json` présent, 35
manifestes de confidentialité, la voie compagnon `OK : 22 phrases à 0, 9
témoins présents` ; la clé d'app CARTO dans le binaire (une occurrence,
comparée sans l'afficher), la clé web absente, un témoin inventé absent ;
« Client sans numéro » présent, « (walk-in) » absent. `altool
--validate-app` réussi — **Apple accepte 0.0.1** après des builds 1.0.0, rien
n'ayant été publié —, envoyé, traité `VALID` (build
`cc4f9bf5-471f-4ced-8a77-ad7a02ccb56d`) ; « What to Test » fr-FR repris du
565 ; symboles Dart et natifs relus dans la liste du serveur Sentry ;
archive rangée en `Runner-pro-569.xcarchive`. ~~C'est le build à soumettre~~
— remplacé par le 577 (ci-dessous) ; la page est renommée « 0.0.1 » (§3).

**Build 577** (2026-10-13, depuis `main` à `d2fb12c6`, après #577 à #582) :
les correctifs de [amounts-that-fit.md](amounts-that-fit.md) — un montant ne
se coupe plus au milieu de son nombre (fiche client, accueil, résumé des
visites choisissent leur forme en mesurant), une seule espace avant « FCFA »,
le numéro d'un client sur une ligne, « dernière à l’instant », et côté
client le compte d'avis après un renvoi. Six PR fusionnées une à une, chacune
à jour de `main` et verte ; l'arbre de `main` est identique, à l'octet, à
celui que la CI a testé. IPA relue au §11.3 : **0.0.1 (577)**,
`com.myweli.pro`, iPhone seul, `fr`, textes de position et d'appareil photo,
`ITSAppUsesNonExemptEncryption` faux, entitlements de production, 35
manifestes de confidentialité, voie compagnon `OK : 22 phrases à 0, 9 témoins
présents`, clé d'app CARTO une fois (comparée sans l'afficher), clé web et
témoin inventé absents, « à l’instant » présent, « (walk-in) » absent.
`altool --validate-app` réussi, envoyé, traité `VALID` (build
`c2c7ff22-448f-48a5-9d35-17db8f7e4c82`) ; « What to Test » fr-FR repris du
569 ; symboles Dart et natifs relus dans la liste du serveur Sentry ; archive
rangée en `Runner-pro-577.xcarchive`. ~~C'est le build le plus récent~~ —
remplacé par le 579 (ci-dessous) : trois décisions du §13.1 touchaient le
binaire ou le serveur (la langue lue par App Store Connect, le paysage, la
suppression du compte démo).

**Build 579** (2026-10-13, soir, depuis `main` à `6850fabe`, après #584) : la
langue de développement du projet iOS passe au français, le paquet reçoit un
`fr.lproj`, et l'iPhone ne déclare plus que le portrait
([ios-language-and-orientation.md](ios-language-and-orientation.md)). IPA
relue au §11.3 : **0.0.1 (579)**, `com.myweli.pro`, iPhone seul,
`CFBundleDevelopmentRegion = fr`, `Base.lproj` et `fr.lproj` à la racine et
aucun autre dossier de langue, `UISupportedInterfaceOrientations =
[Portrait]`, `CFBundleLocalizations = [fr]`, les quatre textes de permission
Pro, `ITSAppUsesNonExemptEncryption` faux, entitlements de production
(`aps-environment = production`, Sign in with Apple, `get-task-allow` faux),
35 manifestes de confidentialité, voie compagnon `OK : 22 phrases à 0, 9
témoins présents`, clé d'app CARTO une fois (comparée sans l'afficher), clé
web et témoin inventé absents. `altool --validate-app` réussi, envoyé, traité
`VALID` (build `e2cf7828-c501-469f-8429-2cfa3fc1e656`). **Lu par l'API une
fois traité : `buildBundles.locales = ["fr"]`** — la fiche dira « Langues :
français » ; le 577, relu au même moment, dit toujours `["en"]`. « What to
Test » fr-FR repris du 577 ; « Équipe MyWeli » ne contient plus que le 579 ;
ajouté à « Testeurs externes » et soumis à la revue bêta — disponible
aussitôt (`IN_BETA_TESTING`) ; symboles Dart et dSYM natifs relus dans la
liste du serveur Sentry ; archive rangée en `Runner-pro-579.xcarchive`.
**Rattaché à la version 0.0.1** (relu par l'API). ~~C'est le candidat à la
soumission~~ — remplacé par le 581 (ci-dessous) : le propriétaire a choisi de
corriger d'abord le rafraîchissement de « Ma journée »
([pro-app-preview.md](pro-app-preview.md) §9, décision 2). Le refus de
suppression du compte démo, lui, ne demande pas de build : l'app affiche déjà
la phrase, il ne manque que le serveur
([demo-account-deletion-lock.md](demo-account-deletion-lock.md) — fusionné le
2026-10-13 (#585), **déployé en production le 2026-10-14 et vu répondre dans
l'app** — §8).

**Build 581** (2026-10-14, nuit, depuis `main` à `322bd799`, après #587) :
« Ma journée » affiche un rendez-vous dès qu'il est créé, sans geste
([pro-journal-shows-new-booking.md](pro-journal-shows-new-booking.md)). IPA
relue au §11.3 : **0.0.1 (581)**, `com.myweli.pro`, iPhone seul,
`CFBundleDevelopmentRegion = fr`, `Base.lproj` et `fr.lproj` seuls à la
racine, portrait seul, `CFBundleLocalizations = [fr]`,
`ITSAppUsesNonExemptEncryption` faux, entitlements de production, 35
manifestes de confidentialité, voie compagnon `OK : 22 phrases à 0, 9 témoins
présents`, clé d'app CARTO une fois (comparée sans l'afficher), clé web et
témoin inventé absents. `altool --validate-app` réussi, envoyé, traité `VALID`
(build `d4fb054c-3c3c-424c-86f8-5e069a42b608`) ; **`buildBundles.locales =
["fr"]`**. « What to Test » fr-FR repris du 579 ; « Équipe MyWeli » ne
contient plus que le 581 ; ajouté à « Testeurs externes » et soumis à la revue
bêta — `IN_BETA_TESTING` aussitôt ; symboles Dart et dSYM natifs relus dans la
liste du serveur Sentry ; archive rangée en `Runner-pro-581.xcarchive`.
**Rattaché à la version 0.0.1 à la place du 579** (relu par l'API).

**Le correctif vu fonctionner, sur le simulateur** — pas sur l'IPA, mais sur
un build de débogage du même commit (`322bd799`), contre la production, sur
le salon démo : un rendez-vous créé le samedi 17 depuis une journée vide est
dans « Ma journée » environ 1,25 s après l'appui sur « Créer le
rendez-vous », pendant que le formulaire se retire, sans aucun geste ; la
pastille du jour apparaît avec lui ; « Rendez-vous créé » reste environ
2,8 s ; aucun chargement plein écran. La veille, sur le build précédent, le
même geste laissait la liste inchangée jusqu'au « tirer pour actualiser »
(vu en préparant la journée du film). Il en reste un rendez-vous d'essai,
« Essai Fix », le 17 à 10:00 sur le salon démo — la remise à zéro
hebdomadaire l'effacera.

~~C'est le candidat à la soumission~~ — remplacé par le 587 (ci-dessous).

**Build 587** (2026-10-14, soir, depuis `main` à `e105aabd`, après #592) :
les chiffres de l'accueil disent « Revenus prévus » et l'écran « Revenus »
dit « Total réalisé » sur « Rendez-vous terminés »
([provider-dashboard-stats.md](provider-dashboard-stats.md),
[provider-earnings.md](provider-earnings.md)). IPA relue au §11.3 : **0.0.1
(587)**, français, portrait seul, entitlements de production, 35 manifestes,
voie compagnon `OK`, les trois nouvelles formules présentes dans le binaire
et « encaissés » absent, clé d'app CARTO une fois (comparée sans l'afficher),
clé web absente. *L'étape séparée `altool --validate-app` n'a pas tourné* :
une substitution de processus mal lue a cassé la chaîne de commandes ; l'envoi
a validé lui-même et le traitement a rendu **`VALID`** (build
`0535c30e-33a1-4f3b-9902-e0a9c38ee328`), **`buildBundles.locales = ["fr"]`**.
« What to Test » repris du 581 ; « Équipe MyWeli » ne contient plus que le
587 ; « Testeurs externes » le reçoit (`IN_BETA_TESTING`) ; symboles relus
sur le serveur Sentry ; archive `Runner-pro-587.xcarchive`. **Rattaché à la
version 0.0.1 à la place du 581** (relu par l'API). **C'est le candidat à la
soumission**, sous réserve des vérifications sur l'iPhone (§11.6).
*2026-10-22 : **soumis**, en revue, publication manuelle (BACKLOG B0.1) ;
les vérifications sur l'iPhone restent dues (BACKLOG B0.2).*
***Refusé*** *(revue du 2026-10-19, guideline 3.1.1 : l'inscription
d'entreprises dans l'app) — remplacé par le 698, ci-dessous.*

**Build 698** (2026-10-26, depuis `main` à `54b02dac`, après #711) : la
nouvelle soumission de 0.0.1 après le refus 3.1.1 — l'app Pro connecte les
salons, elle ne les inscrit plus ([pro-app-login-only.md](pro-app-login-only.md),
BACKLOG B0.11) — avec tous les correctifs de l'app depuis le 587 (lots 1 à
9). Construit par `release_build.sh` ; IPA relue au §11.3 : **0.0.1 (698)**,
`com.myweli.pro`, français, portrait seul sur iPhone, aucun
`UIBackgroundModes` (B0.9), entitlements de production, 35 manifestes, voie
compagnon `OK` (22 phrases à 0, 9 témoins), B0.11 `OK` (7 phrases à 0 ;
« S’inscrire sur myweli.com », la phrase « Aucun compte MyWeli Pro… » et
`/pro/inscription` présents). `altool --validate-app` réussi ; envoyé à
13:49 UTC (delivery `5363b385-3659-469d-968c-2421a396a8c7`, qui est aussi
l'identifiant du build), traité **`VALID`** en trois minutes,
**`buildBundles.locales = ["fr"]`**, chiffrement non exempt `false`.
« Équipe MyWeli » ne contient plus que le 698 (le 587 retiré, relu par
l'API), `IN_BETA_TESTING` ; son « What to Test » fr-FR est réécrit —
l'inscription passe par « S’inscrire sur myweli.com », là où celui du 587
disait « Créer un compte ». **Pas** ajouté à « Testeurs externes »
(`READY_FOR_BETA_SUBMISSION`). Symboles et 20 commits sur Sentry (§12) ;
archive `Runner-pro-698.xcarchive`. **C'est le candidat à la soumission**,
après les vérifications sur l'iPhone (§11.6, BACKLOG B0.2) : le rattacher
à la version 0.0.1 à la place du 587, coller les notes du §8, envoyer la
réponse du §13.2, soumettre (étapes du propriétaire, BACKLOG B0.3).
*Un envoi peut sembler fait sans l'être* : la validation crée déjà un
enregistrement d'envoi, qui reste `AWAITING_UPLOAD` tant que rien n'est
parti, et la liste des builds reste vide jusque-là. C'est
`GET /v1/apps/<id>/buildUploads` qui le dit (`state`), et
`~/Library/Logs/ContentDelivery/com.apple.itunes.altool/` qui montre ce que
l'`altool` local a fait (`validateApp` ou un envoi).

Syntaxe relue dans l'aide de l'`altool` local (version 27.0.5) :
`--upload-package` est la forme de ses exemples ; `--upload-app -f` existe
encore. **Repli** : l'app **Transporter** (Mac App Store), connexion avec le
compte Apple, glisser l'IPA, « Livrer ». Le traitement prend en général moins
de 24 h ; au-delà, Apple indique un problème. Un e-mail arrive à la fin.

### 11.6 TestFlight interne, puis l'appareil

App Store Connect → l'app → **TestFlight** : le build apparaît, conformité
export déjà répondue. Créer un **groupe interne** (jusqu'à 100 utilisateurs
App Store Connect, **sans revue**), s'y ajouter, installer via l'app
TestFlight sur un iPhone réglé en français. Les builds expirent au bout de 90
jours. À vérifier sur l'appareil, contre la production :

*Fait le 2026-10-10, par l'API App Store Connect (la clé du §11.4) :* groupe
interne **« Équipe MyWeli »**, `hasAccessToAllBuilds` **faux** — il ne
contient que le **build 555**, pour qu'on teste exactement ce qui sera
soumis (chaque nouveau build s'y ajoute à la main, ou par l'API). Testeur :
le propriétaire (l'utilisateur App Store Connect Account Holder), état
`INVITED` à la création — l'invitation part par e-mail. Le « What to Test »
du 555 (fr-FR) résume la liste ci-dessous. Relu après coup par l'API : un
build (555), un testeur. *2026-10-12 :* le **560** remplace le 555 dans le
groupe (relu : un seul build, 560), avec son « What to Test » en français —
la liste ci-dessous plus les quatre corrections du 560 (animation, rester
connecté après 15 min, carte, couverture Maison Nala, lien de
notification). *2026-10-12, soir :* le **565** remplace le 560 (relu : un
seul build, 565). Son « What to Test » fr-FR existait déjà à la création du
build — un `POST` aurait répondu 409 —, il a donc été modifié par `PATCH` :
le tour complet du logo, la carte de l'aperçu et le choix d'apps de cartes,
la carte du profil et ses crédits, rester connecté, la connexion démo, le
compte neuf Apple. Les quatre cases ci-dessous, avant « Faire pivoter »,
reprennent ce qui est propre au 565. *2026-10-26 :* le **698** remplace le
587 (relu : un seul build, 698) ; son « What to Test » fr-FR existait déjà à
la création du build et a été réécrit par `PATCH` — l'inscription sur
myweli.com, plus de « Créer un compte ».

- [ ] **Connexion démo** : `revue@myweli.test` + le code, exactement comme les
      notes du §8 le décrivent — c'est aussi le test « le code n'a pas expiré ».
- [ ] **Sign in with Apple** : un compte neuf (4.8 ; jamais exercé par
      un build signé). *Corrigé le 2026-10-05 : pas directement — « Continuer
      avec Apple » sur une identité neuve propose « Créer un compte » →
      « Inscription Pro » → « S’inscrire avec Apple » → « Accueil » (§8).*
      **Depuis le 2026-10-26 (3.1.1, B0.11), le compte se crée sur le web** :
      dans l'app, « S’inscrire sur myweli.com » **ouvre le navigateur** sur
      `/pro/inscription` (le vérifier) ; s'y inscrire avec Apple (ou Google, ou
      un e-mail si Apple n'y est pas proposé) ; revenir dans l'app,
      « Continuer avec Apple » → « Accueil ». Avant l'inscription, la même
      identité lit « Aucun compte MyWeli Pro n’est associé à cette
      adresse. … » sans bouton.
      Ce compte neuf sert aux quatre cases suivantes, **dans cet ordre** ;
      puis **le supprimer** (Profil → « Supprimer mon compte » → `SUPPRIMER`) :
      la suppression aboutit.
- [ ] **Onboarding sans étape d'offre** (compte neuf) : « Configurer mon
      profil » → la liste n'a **aucune** étape « Choisissez votre offre » /
      « 3 mois offerts », et « N étapes sur M » ne la compte pas
      ([pro-companion-path.md](pro-companion-path.md) §2.2).
- [ ] **« Mon abonnement » en lecture seule** (compte neuf, avant la mise en
      ligne) : « Pas encore d’offre active » / « Votre offre démarre à la mise
      en ligne de votre salon. », et rien d'autre — aucune carte, aucun
      bouton.
- [ ] **Feuille d'invitation neutre** (compte neuf, **avant** la mise en
      ligne — après, l'invitation partirait vraiment) : Profil → « Équipe » →
      « Inviter un membre » → saisir une adresse à vous dans « E-mail du
      membre » → « Continuer » → choisir « Manager » → « Envoyer
      l’invitation ». La phrase n'apparaît qu'à ce moment, quand le serveur
      refuse : « Vous pourrez inviter votre équipe une fois votre salon en
      ligne. », sans bouton ajouté (ni « Choisir mon offre », ni « Changer
      d’offre ») — la feuille garde ses propres boutons.
- [ ] **Mise en ligne du compte neuf, de bout en bout** — exige le backend de
      la voie compagnon **déployé en production** (§0 #5) : fiche, point sur
      la carte, ≥ 3 prestations, ≥ 3 photos, horaires → « Mettre mon profil
      en ligne » → le salon passe en ligne, et « Mon abonnement » affiche
      « Essai gratuit — 89 jours restants » / « Offre Pro · se termine le
      {date} », la jauge « {used} / {cap} places » et « Vos données ne sont
      jamais bloquées. », sans carte ni bouton. *89, pas 90* : le serveur
      fixe la fin de l'essai à la publication + 90 jours, et l'app compte les
      jours entiers restants, arrondis vers le bas — une lecture une seconde
      plus tard donne 89 (90 seulement si l'horloge du téléphone retarde sur
      celle du serveur). Le salon est
      alors public sur myweli.com jusqu'à la suppression du compte (INFERRED :
      c'est ce que fait une publication) — d'où la suppression juste après.
- [ ] **Refus démo à l'écran** (compte démo) : Profil → « Équipe » →
      « Inviter un membre » → une adresse à vous → « Continuer » →
      « Manager » → « Envoyer l’invitation » ; et « Mettre mon profil en
      ligne » si le bouton est actif. Les deux affichent alors « Compte de
      démonstration — cette action est désactivée. », sans bouton ajouté —
      la phrase que les notes promettent (§8).
- [ ] **Invite de position** : Profil → « Profil du salon » → « Utiliser ma
      position » → l'alerte affiche le texte Pro du §1.3, boutons en français.
- [ ] **Appareil photo / photos** : Photos du salon → alerte avec le texte Pro.
- [ ] **KYC** : Profil → « Vérification » → choisir une image **et** un PDF
      (API `file_picker` changée) ; l'envoi passe sous 5 Mo.
- [ ] **Push** : un vrai événement Pro (réservation sur un salon de test publié)
      arrive sur l'install TestFlight — preuve à la fois de l'`aps-environment`
      de production et de la clé APNs dans Firebase, jamais attestée.
- [ ] **Push, l'app tuée** (B0.9, décision 7 — le mode d'arrière-plan
      `remote-notification` est retiré) : l'app fermée du sélecteur d'apps,
      une réservation arrive en notification, et **le tap ouvre le rendez-vous**
      (pas seulement l'app). Puis l'app en arrière-plan : même chose.
- [ ] **« Mon abonnement »** : aucune mention de myweli.com, ni ligne de ROI,
      ni « Tarif personnalisé » ; et selon la voie choisie au §2.4, pas de
      sélecteur. *2026-10-05, voie (a) — sur le compte démo* : « Offre Pro
      active » / « Jusqu’au {date} », la jauge « {used} / {cap} places » et
      la ligne « Vos données ne sont jamais bloquées. », **rien d'autre** —
      ni carte d'offre, ni « Choisir » / « Changer d’offre », ni « 3 mois
      offerts », ni bouton « Aide & Support »
      ([pro-companion-path.md](pro-companion-path.md) §2.2 ; l'état « Pro »
      tient à la capture et à la remise à zéro démo, spec §3.3).
- [ ] **Ouverture** (Pro, appli fermée) : « MyWeli Pro », le logo, puis
      **un tour complet** du logo et une courte pause avant l'app — rien ne
      se coupe en route (#569).
- [ ] **Carte de l'aperçu** : Profil → « Configurer mon profil » → « Aperçu
      de ma page » → « Contact » : une carte avec les rues et le repère du
      salon ; la toucher ouvre le choix d'apps de cartes (#570).
- [ ] **Carte du profil** : Profil → « Profil du salon » : la carte affiche
      les rues ; le « i » ouvre les crédits en feuille, pleine largeur, et
      n'est pas caché par « Me localiser ».
- [ ] **Rester connecté** : fermer l'app plus de 15 min, la rouvrir → toujours
      connecté ; le journal de production montre alors un
      `auth_refresh … outcome=rotated` (ou `grace`), pas de `reused`.
- [ ] **Version** : Profil → « À propos » affiche « Version 0.0.1 (587) » — ou le numéro du build installé.
- [ ] **Chiffres** (587, #592) : l'accueil dit « Revenus prévus » ; Analyses → « Revenus » dit « Total réalisé » et « Rendez-vous terminés ».
- [ ] **« Ma journée »** (581, #587) : Rendez-vous → « Nouveau » ou une ligne « Libre » → créer un rendez-vous → il est dans la liste au retour, sans tirer pour actualiser ; l'accueil compte un rendez-vous de plus.
- [ ] **Fiche client** (569, #574) : Clients → un client → la tuile
      « Dernière » lit « 13 oct. 2026 » (jamais un mot coupé), le numéro est
      groupé (« +225 07 … »), les quatre tuiles ont la même hauteur ; avec un
      texte agrandi (Réglages → Accessibilité → Affichage et taille du
      texte), elles passent en 2 × 2.
- [ ] **Photo lente** (569, #574) : Réglages → Développeur → Network Link
      Conditioner → « 100% Loss », activer, puis ouvrir une page avec des
      photos (Profil → Photos du salon) : après une douzaine de secondes, un
      fond clair cache le chargeur, avec « Réessayer » (ou l'icône seule dans
      une petite vignette) ; aucun mot coupé. Désactiver, toucher
      « Réessayer » : la photo arrive.
- [ ] **Accueil** (569, #574) : les deux cartes de chaque rangée de chiffres
      ont la même hauteur, même quand « Ce mois » passe à la ligne.
- [ ] **« Nouveau »** (569, #573) : l'Aperçu d'un salon sans avis affiche
      « Nouveau », jamais « 0.0 · 0 avis » ; pas de carte « Vos rendez-vous
      ici — Connectez-vous… ».
- [ ] **Réservation au comptoir** (569, #574) : « Client sans numéro », et
      aucun interrupteur SMS.
- [ ] Faire pivoter le téléphone : **à partir du build 579,
      l'app reste en portrait**
      ([ios-language-and-orientation.md](ios-language-and-orientation.md)) —
      non observé sur le simulateur, à voir ici. Sur le 577 et avant, le
      paysage est encore permis : noter ce qui casse.

Si un point échoue : on corrige, on reconstruit (le numéro monte tout seul),
on renvoie. Rien n'est soumis sur un build non vérifié.

---

## 12 · Une fois la fiche créée et le build envoyé

1. **`updateUrl` iOS** — la mise à jour forcée reste inerte sur iOS tant
   qu'elle est vide ([LAUNCH.md](../LAUNCH.md) §5.3). Dans la console admin
   (prod rétablie), plateforme Pro iOS :
   `https://apps.apple.com/app/id6805272779` (Apple ID relu le 2026-10-05, §3).
2. **Symboles Sentry** — sans eux, les plantages du premier build TestFlight
   arrivent mais restent illisibles. Le jeton est dans Secret Manager ;
   `sentry-cli` est installé depuis le 2026-10-10 hors de Homebrew (dont le
   téléchargement échouait) — `~/.local/sentry-cli/node_modules/.bin/sentry-cli`,
   par `npm --prefix ~/.local/sentry-cli install @sentry/cli
   @sentry/cli-darwin` :

   ```bash
   brew install getsentry/tools/sentry-cli
   cd "/Users/sadreddinedaher/beauty app"
   SENTRY_AUTH_TOKEN="$(gcloud secrets versions access latest --secret=SENTRY_AUTH_TOKEN --project=myweli)" \
     sentry-cli debug-files upload --include-sources -o myweli -p myweli-app \
       mobile/build/symbols/pro "mobile/build/ios/archive/Runner-pro-<N>.xcarchive/dSYMs"
   ```

   Les symboles Dart (`build/symbols/pro`) **et** les dSYM natifs de
   l'archive rangée au §11.2 — la commande imprimée par le script n'envoie que
   les premiers. Vérifier **côté serveur** :
   `GET /api/0/projects/myweli/myweli-app/files/dsyms/` liste les nouveaux
   debug IDs (la note du script ne compte que les entrées Android). Ne pas
   bloquer TestFlight sur cette étape.
   *Build 698, 2026-10-26 :* symboles Dart et dSYM natifs de
   `Runner-pro-698.xcarchive` envoyés (10 fichiers manquants), puis les cinq
   identifiants relus un par un dans la liste du serveur : `Runner`
   (`0c0a82aa…`), `App` (`0c7143a3-9a3e…`, celui des symboles Dart aussi),
   `Flutter` (`4c4c4467…`, déjà présent), `add_2_calendar` (`656d5c5d…`),
   `objective_c` (`93db733e…`). Release `com.myweli.pro@0.0.1+698` créée et
   `set-commits` accepté : le serveur liste **20 commits**, le dernier
   `54b02dac` — l'intégration GitHub de Sentry connaît `Zaslons/myweli`
   depuis le 2026-08-12.
   *Build 565, 2026-10-12 :* symboles Dart (2 fichiers manquants envoyés) et
   dSYM natifs (2 envoyés) ; relus dans la liste du serveur : `Runner`
   (`691b934c…`), `App` (`0c7143a3-47bf-01e0…`) et le paquet source Dart.
   Attention : `?query=<debug ID>` sur cette route répond une liste **vide**
   même pour un fichier présent — lire la liste (`?per_page=…`), pas le
   filtre.
   *Build 560, 2026-10-12 :* symboles Dart et dSYM natifs envoyés, `Runner`
   (`a00e3585…`) relu côté serveur.
   *Build 555, 2026-10-10 :* les symboles Dart étaient déjà sur le serveur
   (même identifiant que le 551, code Dart inchangé), mais **cinq des six
   dSYM natifs manquaient** — envoyer seulement `build/symbols/pro` les
   aurait laissés dehors. Les six sont maintenant listés par l'API ci-dessus
   (`Runner` 75aa8dd8…, `App` 0c7143a3…, `Flutter` 4c4c4467…, vérifiés un
   par un).
3. **Consigner** ici et dans [LAUNCH.md](../LAUNCH.md) §6.2 : Apple ID de
   l'app, numéro de build envoyé, date, résultat des vérifications du §11.6.

---

## 13 · La liste du propriétaire, d'aujourd'hui à « Soumettre pour la revue »

*Mise à jour le 2026-10-05 : points 1, 7 et 8 annotés ; points 6 et 9
ajoutés (la liste est renumérotée, aucun renvoi extérieur ne cite ses
numéros).*

1. [x] **Trancher 3.1.1** (§2.4, recommandé : (a)) → la PR mobile qui retire
       le choix d'offre sur iOS, avec ses tests iOS forcés. **Tranché le
       2026-10-05 : (a), sur les deux apps** (§2.4) ; la PR est **construite
       le 2026-10-05** — backend, mobile et docs, tests sur les deux
       plateformes ([pro-companion-path.md](pro-companion-path.md)) ; sa
       fusion est le point 5, son déploiement le point 6.
2. [x] **Rétablir la facturation GCP.** Puis : Cloud SQL et Cloud Run servent
       (`/health` 200), « Production checks » vert, `DEMO_PROVIDER_CODE`
       lisible et monté sur la révision servie. *Fait : facturation rouverte
       le 2026-10-06, production rétablie ; la connexion démo a marché sur le
       build 555 le 2026-10-11 (§0 #4).*
3. [x] **Avant que quoi que ce soit ne touche la base staging** : établir où
       vit le salon démo curé (prod ? staging ?) — se connecter en démo contre
       la prod ; s'il n'existe qu'en staging, le recréer en prod par l'app.
       *2026-10-05 : le recréer ne demande plus aucun choix d'offre dans
       l'app. Sa ligne d'offre Pro est créée par la **capture du snapshot**
       (point 4) : `POST /admin/demo/snapshot` crée la ligne si elle manque,
       épingle `tier = pro` et `paidUntil = maintenant + 30 jours`, comme
       chaque remise à zéro hebdomadaire ensuite. « Mon abonnement » affiche
       donc « Offre Pro active » dès la capture
       ([backend-demo-review-account.md](backend-demo-review-account.md) §6.2,
       §9).* *Fait le 2026-10-11 : il vit en production (§0 #4).*
4. [x] **Salon démo** : prestations, photos, horaires, agenda ; « Publier » et
       « Inviter » répondent 403 `demo_account_locked` ; téléverser le **vrai
       logo** ; **recapturer le snapshot** (`POST /admin/demo/snapshot`) ;
       consigner date + environnement dans
       [backend-demo-review-account.md](backend-demo-review-account.md) §9.
       *2026-10-05 : et « Mon abonnement » affiche « Offre Pro active »
       (§11.6).* *Fait le 2026-10-11 : « Maison Nala », logo réel, snapshot
       recapturé (§0 #4).*
5. [x] Fusionner la PR de l'audit (et celle du point 1) ; CI vert sur `main`.
       *2026-10-05 : la PR de l'audit (#550) est fusionnée — squash
       `f6ffb585` ; reste celle du point 1.* *Celle du point 1 (#551) est
       fusionnée le 2026-10-06.*
6. [x] **Déployer en production le backend de la voie compagnon** (feu vert
       du propriétaire, après le point 2) **avant la soumission** : l'essai qui
       démarre à la première mise en ligne et les verrous démo doivent tourner
       quand le relecteur crée son compte neuf. Depuis « Accueil », il peut
       ouvrir « Configurer mon profil » et mettre ce salon en ligne ; sans ce
       backend, il lirait « …l’offre de votre salon n’est plus active. » pour
       une offre qui n'a jamais existé (spec §9.3–9.4). *Fait avant la
       soumission : le déploiement de production du 2026-10-07 part d'un
       `main` qui contient #551.*
7. [ ] **Licence Xcode**, `runFirstLaunch`, `xcodebuild -version`,
       `flutter doctor -v`, compte Xcode connecté (§11.1). *2026-10-05 :
       licence et premier lancement faits, build iOS non signé de Pro réussi
       sous Xcode 27 (§0 #2, §11.1) ; reste à voir l'équipe 5VWKJD956A dans
       Xcode → Réglages → Comptes.*
8. [x] **App Store Connect** : vérifier ou créer la fiche (§3) ; noter l'Apple
       ID ici. **Fiche vérifiée le 2026-10-05 — Apple ID 6805272779** (§3).
9. [x] **Les deux avis App Store Connect** (§0 #6). *Fait le 2026-10-06 :*
       la classification (4+, nouvelles questions consignées, §6), le statut
       de professionnel UE déclaré, ses coordonnées vérifiées et le
       certificat de résidence téléversé — « In Review » chez Apple (§9.1),
       le prix, la disponibilité et l'exclusion Mac / Vision Pro (§9).
10. [x] **Clé d'API** App Store Connect (§11.4) — ou installer Transporter.
       *Fait le 2026-10-09 : `SRP86N339X`, équipe, App Manager.*
11. [x] **Build** `./tool/release_build.sh ios pro` depuis `main` ; ranger
       l'archive ; **vérifier l'IPA** (§11.3). *Build 555, 2026-10-10 ;
       archive rangée en `Runner-pro-555.xcarchive`. Puis 560 et **565**
       (2026-10-12), archive `Runner-pro-565.xcarchive`.*
12. [x] **Valider, envoyer**, attendre le traitement (§11.5). *555 `VALID` ; 560 `VALID` ; 565 `VALID` (2026-10-12) ; 569 `VALID` (2026-10-13, 0.0.1) ; 577 `VALID` (2026-10-13) ; 579 `VALID` (2026-10-13, soir) ; 581 `VALID` (2026-10-14) ; **587 `VALID`** (2026-10-14, soir), le plus récent — lu comme français.*
13. [ ] **TestFlight interne** et toutes les cases du §11.6. *Groupe et
       invitation faits le 2026-10-10 ; les vérifications sur l'appareil
       restent au propriétaire.*
14. [x] **Symboles Sentry** (§12.2). *Dart et natifs, builds 555, 560, 565, 569, 577, 579, 581 et 587.*
15. [x] **Captures** sur le salon démo — *8 captures légendées, 1206 × 2622 (obligatoire) et 1320 × 2868, faites le 2026-10-13 ([pro-app-store-screenshots.md](pro-app-store-screenshots.md)) ; **validées par le propriétaire et téléversées le 2026-10-13** — 16 images, traitées, dans l'ordre (§13.1).*
16. [x] **Remplir App Store Connect** : informations sur l'app (§3, §5, §6,
       §9), tarifs et disponibilité — Côte d'Ivoire seule, Mac et Vision Pro
       décochés (§9), confidentialité (§7), page 0.0.1 — captures, texte
       promotionnel, description, mots-clés, URL, copyright, **build**,
       publication **manuelle** (§4, §9, §10), informations pour la revue avec
       le code lu à ce moment-là et la **ligne SUBSCRIPTION remplacée** (§8).
       *2026-10-05 : la ligne est remplacée dans le dossier — coller les notes
       du §8 telles quelles ; le nom « MyWeli Pro — Gestion de salon » si le
       propriétaire le retient (§3) ; la version est **renommée « 0.0.1 »**
       depuis le 2026-10-13 (accord du propriétaire ; relue par l'API :
       `0.0.1`, « Prepare for Submission », aucun build rattaché) — reste à
       vérifier que le build 569 s'y rattache (§3). **À corriger en
       remplissant la page** : la publication y est encore « après
       approbation », pas manuelle (§9).* *2026-10-13, soir : **rempli par
       l'API, avec l'accord du propriétaire**, tout ce qui pouvait l'être —
       le détail, champ par champ, au §13.1. La publication est **manuelle**,
       le build 579 est rattaché. **Restent au propriétaire, dans le site** :
       l'étiquette de confidentialité (§7), la déclaration des droits sur le
       contenu (§9), le mot de passe démo et ses coordonnées dans les
       informations pour la revue (§8).* *2026-10-22 : la version est
       **soumise** — App Store Connect n'en accepte pas sans ces champs ; ce
       qu'ils disent se relit au lot 10.*
17. [ ] **`updateUrl` iOS** dans la console admin (§12.1).
18. [x] **Porte d'entrée Cloudflare** : ne pas lancer la phase A pendant une
       revue ; si elle a été déployée avant, vérifier qu'un client non
       navigateur (l'app) n'est pas mis au défi par Browser Integrity Check /
       Bot Fight Mode sur `api.myweli.com`
       ([infra-cloudflare-front-door.md](infra-cloudflare-front-door.md)).
       *2026-10-22 : la porte est en ligne depuis le 2026-10-07, avant la
       soumission ; la connexion démo du build 555 l'a traversée le
       2026-10-11 (§0 #4) — l'app n'est pas mise au défi.*
19. [ ] **Le jour même** : connexion démo sur le build TestFlight contre la
       prod, « Production checks » vert. *2026-10-22 : le jour de la
       soumission et ces deux essais ne sont pas consignés ici — à relire au
       lot 10.*
20. [x] **Soumettre pour la revue.** Ne plus toucher au code démo tant que la
       version est en revue. *Soumis : le build 587 est en revue, publication
       manuelle (BACKLOG B0.1).* **2026-10-25 : Apple a refusé le 0.0.1
       (build 587)** ; le motif suit. Le prochain envoi est **un nouveau build
       de la 0.0.1**, avec toutes les corrections depuis le 587 (BACKLOG,
       décision 1) — pas de 0.0.2 avant.
21. [ ] Après approbation : **ne pas publier** avant que [LAUNCH.md](../LAUNCH.md)
       §3 le permette (production rétablie et stable) — la publication est
       manuelle (§9).

### 13.1 Ce qu'App Store Connect contient au 2026-10-13 — et ce qu'il reste à y écrire

**Écrit le 2026-10-13 au soir, par l'API, avec l'accord du propriétaire**
(« tout comme recommandé ; les captures sont validées ») — puis **chaque
valeur relue par une seconde requête et comparée au texte de ce dossier**
(17 valeurs, toutes identiques ; aucun secret ni coordonnée écrit ni
affiché). Le matin, la fiche était une coquille : la colonne « Avant » le
garde. « Propriétaire » : un secret, une déclaration ou un geste que lui seul
fait ; « site » : seulement dans le site App Store Connect.

| Champ | Avant (matin) | Maintenant | Reste |
|---|---|---|---|
| Nom | « MyWeli Pro » | **« MyWeli Pro »** — gardé, décision du propriétaire | — |
| Sous-titre | vide | `Agenda, clients, réservations` | — |
| URL de la politique de confidentialité | vide | `https://myweli.com/politique-confidentialite` (200 le jour même) | — |
| Catégories | vides | Business, puis Productivity | — |
| Droits sur le contenu | vide | **vide** | **propriétaire** — c'est une déclaration (§9) |
| Classification d'âge | remplie, 4+ | inchangée | — |
| Prix, disponibilité | gratuit, Côte d'Ivoire seule | inchangés | à relire dans le site : l'API affiche `CANNOT_SELL` sur les 175 pays, sens inconnu avant une première sortie |
| Confidentialité de l'app (l'étiquette) | illisible par l'API | **illisible par l'API** | **propriétaire, site** — les réponses du §7, puis « Publier » |
| Captures 1206 × 2622 et 1320 × 2868 | aucun jeu | **8 + 8**, toutes `COMPLETE`, dans l'ordre 01 → 08 ; dimensions, taille et somme MD5 de chaque fichier comparées aux fichiers validés | — |
| Texte promotionnel, description, mots-clés | vides | ceux du §4 (144, 996 et 99 caractères — 100 octets pour les mots-clés) | — |
| URL d'assistance | vide | `https://myweli.com/support` (200 le jour même) | la boîte `support@myweli.com` : à confirmer comme lue |
| URL marketing (facultative) | vide | **vide** — décision du propriétaire | — |
| Copyright | vide | `2026 Sadr Eddine Daher` (§3) | — |
| Publication de la version | **après approbation** | **manuelle** (`MANUAL`) | — |
| Informations pour la revue | n'existaient pas | créées : connexion requise, identifiant `revue@myweli.test`, **les notes en vigueur du §8** (3 476 octets) | **propriétaire** : le mot de passe démo et les coordonnées de contact — vides, et l'assistant ne les écrit pas — *2026-10-14 : le verrou du compte démo est vérifié en production ; ce sont **les notes amendées** du §8 qui doivent remplacer celles-ci, et l'API refuse de le faire sans les coordonnées de contact (§8)* |
| Build rattaché | aucun | **587** (0.0.1), lu comme français (§11.5) — il remplace le 581 depuis le 2026-10-14 au soir | les vérifications sur l'iPhone (§11.6) |
| Aperçu vidéo (facultatif) | aucun | **le film choisi par le propriétaire** (version 2, coupe 1, 28,7 s — [pro-app-preview.md](pro-app-preview.md) §0), **téléversé le 2026-10-14** dans les deux emplacements iPhone, traité par Apple, placé avant les captures (`APP_PREVIEW`, `ACTIVE`, lu par la nouvelle API) ; l'image d'affiche demandée à 25 s (`00:00:25:00`) — Apple avait d'abord ignoré le temps envoyé au téléversement et pris son défaut de 5 s ; corrigé, l'image était encore en cours de génération au dernier relevé | regarder l'affiche dans le site ; sinon « Edit Poster Frame » à 25 s |
| « Soumettre pour la revue » | — | — | propriétaire — **fait** (587 en revue) |

**Les captures, vues par les deux API.** Elles ont été envoyées par les
ressources `appScreenshotSets` / `appScreenshots`, qu'Apple déclare
dépréciées depuis l'API 4.5.1 au profit de la bibliothèque de ressources
(*App Asset Library*) — elles fonctionnent. Relu par la nouvelle API
(`/placements` de la localisation) : **8 placements `APP_SCREENSHOT` dans
`IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE`** — le jeu obligatoire — **et 8 dans
`IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE`**, tous `ACTIVE`. C'est aussi ce qui
établit la correspondance `APP_IPHONE_61` → écran moyen (1206 × 2622) et
`APP_IPHONE_67` → grand écran (1320 × 2868), qu'aucune page d'Apple n'écrit.
Un prochain envoi devrait passer par la bibliothèque.

**Trois décisions touchent le binaire ou le serveur, donc le build à
soumettre** — *prises par le propriétaire le 2026-10-13 : les trois, comme
recommandé. La langue et le portrait sont construits
([ios-language-and-orientation.md](ios-language-and-orientation.md)) ; le
refus de suppression du compte démo a sa propre PR.* Telles qu'elles étaient
posées :

1. **La langue.** App Store Connect lit les builds 569 et 577 comme
   *anglais* : `CFBundleDevelopmentRegion` vaut `en` et le paquet ne contient
   que `Base.lproj`, bien que `CFBundleLocalizations` dise `fr`. La fiche
   afficherait « Langues : anglais » pour une app en français. Le corriger
   demande un changement du projet Xcode et un nouveau build ; l'effet ne se
   lit qu'après l'envoi (§14 le croyait « sans effet visible »).
2. **Le paysage.** `Info.plist` autorise les deux orientations paysage sur
   iPhone ; rien n'y a jamais été essayé. Verrouiller en portrait, ou
   accepter des écrans serrés si le relecteur tourne le téléphone.
3. **La suppression du compte démo.** L'app propose la suppression de compte
   (exigée par 5.1.1(v)) ; seuls des rendez-vous à venir la bloquent. Un
   relecteur qui l'essaie sur le compte partagé le détruit. Un refus côté
   serveur pour l'identité démo est un changement backend et un déploiement
   en production.

**Restent aussi au propriétaire** : les réponses à confirmer pour l'étiquette
de confidentialité ; les notes du §8 (telles quelles — ce sont celles sous
lesquelles la revue bêta a approuvé le 569 — ou amendées) — *2026-10-13 : le
§8 porte désormais deux blocs. « Les notes en vigueur » sont celles-là, et
ce sont elles qu'App Store Connect contient ; « les notes amendées » disent
que le compte démo ne peut pas être supprimé, et ne se collent **qu'une fois
la ligne « Verrou de suppression du compte démo — vérifié en production »
du §8 datée**, c'est-à-dire après le déploiement du backend et l'essai de
[demo-account-deletion-lock.md](demo-account-deletion-lock.md) §10.1* ; la boîte
`support@myweli.com`, seul contact de la page d'assistance, à confirmer
comme lue ; la politique de confidentialité, qui ne nomme Cloudflare que
pour le stockage alors que l'API passe par lui depuis le 2026-10-07 ; les
vérifications sur l'iPhone du §11.6 sur le build retenu.

---

### 13.2 La réponse au refus 3.1.1 (Resolution Center) — à envoyer par le propriétaire

Brouillon du 2026-10-26 ([pro-app-login-only.md](pro-app-login-only.md)
§8). En anglais, dans le fil du refus, **une fois le nouveau build attaché à
la version 0.0.1** (remplacer `<BUILD>`). Il dit franchement le lien vers le
site : le cacher reviendrait à espérer que le relecteur ne le voie pas.

```text
Hello,

Thank you for reviewing MyWeli Pro (submission 45ed9726-1418-435b-b3e2-76726422c5d3).

We have removed the account registration features for businesses from the app, on iOS and Android:
- the in-app sign-up form (« Inscription Pro ») and the buttons that opened it (« Créer un compte », « S’inscrire ») are gone;
- an existing account can no longer create an additional salon in the app (« Ajouter un salon » is gone).

MyWeli Pro now only signs in to salon accounts that already exist, with an e-mail code, Apple or Google. Salons create their account on our website; the sign-in screen has one link, « S’inscrire sur myweli.com », which opens that page in Safari. The app contains no purchasing, no pricing and no choice of plan (guideline 3.1.3(f)).

Build <BUILD> of version 0.0.1 is attached, and the App Review notes describe the demo account and these changes.

Thank you,
Sadreddine Daher
```

*Si le relecteur objecte au lien* : le retirer est un seul widget
(`AuthSwitchPrompt` de `pro_login_screen.dart`) et une ligne d'essai ; le
reste de B0.11 tient sans lui.

## 14 · Points ouverts et mineurs connus, non corrigés

| Point | Nature | Risque / suite |
|---|---|---|
| **1.2 — pas de « Signaler » dans « Avis » côté Pro.** `POST /reviews/{id}/report` répond 403 à tout rôle autre que `user` (`backend/routes/reviews/[id]/report.dart`). | code | Faible (le salon démo n'a probablement pas d'avis) ; atténué par la rubrique USER CONTENT des notes. Suite : autoriser le salon à signaler les avis de son propre salon + « Signaler » sur la tuile. **Corrigé** (#678, lot 6) : Propriétaire et Gérant signalent, la file admin marque « Signalé par le salon » ; en production, l'app avec 0.0.2. |
| **5.1.1(v) — Sign in with Apple : jetons non révoqués** à la suppression (Apple : « should » appeler `/auth/revoke`). | code + clé owner | Rarement testé en revue. Suite : capter l'`authorizationCode`, l'échanger côté serveur (clé privée Sign in with Apple, portail), révoquer à la suppression. Peut suivre le lancement. **Construit** (#679, lot 6) et en production — **inactif** tant que la clé `.p8` n'existe pas (étape du propriétaire, DEPLOYMENT.md phase C). |
| **Suppression du propriétaire : le salon garde ses coordonnées** (téléphone, WhatsApp, numéro Mobile Money, adresse) en brouillon (`provider_account_service.dart`). | décision | Divulgué par la politique et `/suppression-compte`. Suite : effacer ces champs à la suppression, garder l'historique. **Corrigé** (#677, lot 6) : effacés à la suppression, le nom et l'historique gardés ; en production. |
| **Politique de confidentialité** : pas la phrase « nos sous-traitants offrent une protection équivalente » (5.1.1(i)) ; dit « Profil → Exporter mes données » là où l'app Pro dit « Mes données ». | web (texte légal) | Une phrase + aligner le libellé (`web/app/politique-confidentialite/page.tsx`). **Corrigé** (#709, B0.4, en ligne le 2026-10-26, relu) : la phrase de protection équivalente, « Profil → Mes données » côté Pro — et ce que la relecture a trouvé en plus : depuis le 2026-10-07, Google Cloud ne voit plus que l'adresse de Cloudflare. |
| **Mode d'arrière-plan `remote-notification` inutilisé** (`UIBackgroundModes`) : le backend n'envoie jamais `content-available`. | code, optionnel | Rarement rejeté. Le retirer puis revérifier sur appareil qu'une notification arrive app tuée/en arrière-plan et que le tap route. **Retiré** (B0.9, décision 7, 2026-10-25 — #708) pour le build renvoyé : le serveur n'envoie jamais de poussée silencieuse et le gestionnaire d'arrière-plan est vide (relu, et épinglé des deux côtés) ; la vérification sur l'appareil est au §11.6. |
| ~~**Paysage non verrouillé sur iPhone** (`UISupportedInterfaceOrientations`, aucun `setPreferredOrientations`).~~ | ~~décision~~ | **Tranché et construit le 2026-10-13** : portrait seul sur iPhone, pour les deux apps (un seul `Info.plist`) ; l'iPad garde ses quatre orientations ([ios-language-and-orientation.md](ios-language-and-orientation.md)). ~~Reste ouvert : **Android**, dont le manifeste ne fixe aucune orientation.~~ **Android : portrait** depuis #682 (lot 7, B7.9) ; part avec 0.0.2. |
| **Identité démo non recréée si elle est perdue.** ~~La suppression n'est pas verrouillée ; les rendez-vous à venir de la remise à zéro n'existent qu'à J+1/J+2.~~ **Suppression verrouillée côté serveur, construit le 2026-10-13** — 403 `demo_account_locked` sur `DELETE /me/provider` ([demo-account-deletion-lock.md](demo-account-deletion-lock.md)) — ~~**pas encore déployé en production**~~ (déployé le 2026-10-14, voir la fin de la ligne) : tant qu'il ne l'était pas, un relecteur peut encore détruire le compte, et ce sont les notes en vigueur du §8 qui se collent, pas les notes amendées (la ligne datée du §8 en décide). | code + déploiement (accord du propriétaire) | Une fois déployé et vérifié (spec §10.1), il ne reste que la perte hors produit — une opération en base, une restauration. Dans ce cas : recréer par l'app + recapturer. Faire recréer l'identité par la remise à zéro n'est pas construit ; observé le 2026-10-13 sur les dépôts en mémoire : elle continue de restaurer le salon orphelin et ne recrée rien. **Déployé en production et vu répondre dans l'app le 2026-10-14** (§8). |
| **`tool/release_build.sh` exige Secret Manager** (`MOBILE_SENTRY_DSN`). | owner | ~~Aucun build tant que la facturation est fermée.~~ *(2026-10-22 : facturation rouverte le 2026-10-06 ; le script construit.)* Prendre le DSN dans la console Sentry et construire à la main enfreindrait la règle « personne ne manipule le DSN » : décision, pas défaut. |
| **L'archive Xcode n'est pas rangée par saveur** : `build/ios/archive/Runner.xcarchive` est écrasée par le build suivant (celle du 2026-08-29 est aujourd'hui l'archive **consommateur**). | code | Contourné à la main au §11.2. Suite : que le script la renomme en `Runner-$FLAVOUR.xcarchive` et imprime les dSYM dans la commande Sentry. |
| **5.1.1(ix) — KYC et compte développeur individuel.** Pièce d'identité + photo du visage, vendeur = personne physique, société non immatriculée (`infra/legal/registration-manifest.json`). | décision | Majeur maintenu par l'audit, appliqué de façon inégale par Apple. Atténué par la rubrique IDENTITY DOCUMENTS. Si rejet : masquer le KYC et les acomptes sur iOS jusqu'au compte Organisation. Type d'adhésion à confirmer (developer.apple.com → Membership). |
| Numéro de build = nombre de commits de **n'importe quelle** `HEAD` : un build de branche peut griller un numéro. | code, optionnel | Construire depuis `main` (§11.2). |
| ~~`CFBundleDevelopmentRegion` reste `en`.~~ | ~~code, optionnel~~ | **L'attente était fausse** : App Store Connect lisait les builds 569 et 577 comme anglais (`buildBundles.locales = ["en"]`). **Corrigé le 2026-10-13** — langue de développement `fr` et un `fr.lproj` dans le paquet ([ios-language-and-orientation.md](ios-language-and-orientation.md)) ; l'effet se lit sur le prochain build envoyé (§11.5). |
| ~~Le dialogue de suppression dit « Votre salon sera retiré de MyWeli » même à un membre d'équipe.~~ | ~~code~~ | **Corrigé** (#682, lot 7, B7.3) : la phrase suit « le compte possède un salon » ; le web en ligne, l'app avec 0.0.2. |
| Taux de sessions sans plantage perdu (sessions Sentry coupées). | assumé | L'alerte « crash-free sessions » de l'observabilité doit être revue (plantages et blocages restent signalés). *Suivi : BACKLOG B0.7 (trois alertes d'incident).* |

---

## 15 · Liens

- La voie compagnon (3.1.3(f), décision du 2026-10-05) :
  [pro-companion-path.md](pro-companion-path.md) — l'inventaire avant → après,
  le contrat serveur, les tests.
- Android : [play-store-forms.md](play-store-forms.md) — la table Pro de
  sécurité des données a été alignée sur le §7 le 2026-09-24.
- Compte démo : [backend-demo-review-account.md](backend-demo-review-account.md).
- Chaîne de signature et d'envoi : [mobile-store-submission.md](mobile-store-submission.md)
  (son §4 est remplacé, pour Pro, par le §7 ici).
- Saveurs iOS : [mobile-ios-flavours.md](mobile-ios-flavours.md).
- Portes de lancement : [LAUNCH.md](../LAUNCH.md) §3 et §6.2.
