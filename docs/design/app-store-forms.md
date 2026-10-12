# MyWeli Pro — App Store Connect, formulaire par formulaire

| | |
|---|---|
| **Status** | **Prêt à remplir, en attente de** : la facturation GCP (production arrêtée), l'état du salon démo en production, et **la voie compagnon** ([pro-companion-path.md](pro-companion-path.md), construite le 2026-10-05) — sa fusion, et son backend déployé en production **avant** la soumission. Rédigé 2026-09-24 ; **mis à jour 2026-10-05** : fiche App Store Connect vérifiée (Apple ID 6805272779, §0 #3, §3), décision 3.1.1 prise — voie (a), sur les deux apps (§2), Xcode 27 prêt (§0 #2), deux avis App Store Connect à traiter (§0 #6). |
| **Portée** | L'app **MyWeli Pro** seule — `com.myweli.pro`, nom affiché « MyWeli Pro », iPhone uniquement. Le consommateur (`com.myweli.app`) aura son propre dossier. |
| **Source** | L'audit App Store du 2026-09-24 (cinq lentilles, chaque constat bloquant/majeur revu par un vérificateur indépendant) et le commit `68fc33c` qui en corrige la partie code. |
| **Pendant Android** | [play-store-forms.md](play-store-forms.md) — même règle, même ton. |
| **Règle** | Chaque réponse est dérivée du code, du binaire ou de la politique publiée, jamais inventée. En cas de doute en saisissant : STOP, on vérifie. Aucun secret ici : le code démo se lit au moment de remplir (§8). |

Ordre conseillé dans App Store Connect : **fiche de l'app (§3) → Informations
sur l'app : catégorie, droits, classification (§5, §6, §9) → Tarifs et
disponibilité (§9) → Confidentialité de l'app (§7) → page de la version 1.0.0 :
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
| 1 | **Production arrêtée.** Compte de facturation fermé (facturation coupée au plus tard le 2026-09-16 10:30 UTC — le dernier contrôle vert date du 15) ; les deux bases Cloud SQL suspendues le 2026-09-23 06:23 UTC, motif `BILLING_ISSUE` — Google supprime une instance suspendue au bout de **90 jours** ; le workflow « Production checks » est rouge chaque jour du 2026-09-16 au 2026-09-24 ; `api.myweli.com/health` injoignable le 2026-09-24. Le binaire ne parle qu'à `https://api.myweli.com` (c'est voulu), donc le relecteur ne passe pas l'écran de connexion — rejet 2.1 assuré (« turn on your back-end service! »). Secret Manager refuse aussi (`BILLING_DISABLED`) : pas de nouveau build (`tool/release_build.sh` lit `MOBILE_SENTRY_DSN`) et pas de code démo lisible. | owner | Rétablir la facturation ; `/health` 200 ; « Production checks » vert. L'envoi à TestFlight **interne** peut précéder (il ne contacte pas l'API), la soumission non. |
| 2 | ~~**Machine de build.**~~ **Levé le 2026-10-05** : licence Xcode 27 acceptée, premier lancement fait (`xcodebuild -checkFirstLaunchStatus` → 0), build iOS non signé de Pro réussi sous Xcode 27 depuis le correctif du Podfile (§11.1). Une liste de comptes existe dans les réglages d'Xcode ; que ce soit l'équipe **5VWKJD956A** ne se voit que dans Xcode. | owner | Vérifier l'équipe dans Xcode → Réglages → Comptes avant le §11.2. |
| 3 | ~~**Fiche App Store Connect non vérifiée.** Le profil « iOS Team Store Provisioning Profile: com.myweli.pro » prouve que l'App ID existe dans le portail développeur, pas que la fiche App Store Connect existe. Rien dans le dépôt ne l'atteste ; sans fiche, l'envoi est refusé.~~ **Levé le 2026-10-05** : la fiche « MyWeli Pro » existe, relue en lecture seule dans App Store Connect (navigateur du propriétaire) — Apple ID **6805272779**, SKU `myweli-pro`, bundle `com.myweli.pro`, langue principale français, version iOS 1.0 « Prepare for Submission », aucun build dans TestFlight. Encore vides : catégorie, sous-titre, droits sur le contenu (§3). | owner | Fait. Reste à remplir les champs (§3, §4, §5, §9). |
| 4 | **Salon démo en production non vérifié.** Le propriétaire a curé « Salon Démo MyWeli » vers le 2026-08-26/27, sans que l'environnement (staging ou prod) ni la capture du snapshot en prod soient consignés ; le logo réel doit encore être téléversé **puis le snapshot recapturé** (sinon la remise à zéro de 7 jours l'annule). | owner | Une fois la prod revenue, **avant que quoi que ce soit ne touche la base staging** : se connecter en démo, vérifier, logo, `POST /admin/demo/snapshot`, consigner date + environnement dans [backend-demo-review-account.md](backend-demo-review-account.md) §9. |
| 5 | ~~**Décision 3.1.1 ouverte** : le sélecteur d'offre et les incitations à choisir une offre sont encore dans l'app iOS (§2).~~ **Décidé le 2026-10-05** : voie (a) — app compagnon gratuite (3.1.3(f)) — sur **les deux** apps, iOS et Android, sans branche de plateforme (§2.4). Construite selon [pro-companion-path.md](pro-companion-path.md) le 2026-10-05 sur `feat/pro-companion-path` (backend, mobile, docs). La ligne SUBSCRIPTION des notes est en place (§8). | code + déploiement | La PR fusionnée ; le backend qui démarre l'essai à la première mise en ligne **déployé en production avant la soumission** : depuis « Accueil », le relecteur peut ouvrir « Configurer mon profil » et mettre son compte neuf en ligne. Sans ce backend, il lirait « …l’offre de votre salon n’est plus active. » pour une offre qui n'a jamais existé (spec §9.4). Feu vert du propriétaire pour la production. |
| 6 | **Deux avis dans App Store Connect** (relevés le 2026-10-05). **Classification : faite le 2026-10-06** (4+, nouvelles questions répondues, §6). **Statut de professionnel UE : déclaré le 2026-10-06** (option 1, coordonnées vérifiées par code, certificat de résidence téléversé — « In Review » chez Apple, §9.1). Prix (gratuit), disponibilité (Côte d'Ivoire seule) et exclusion Mac / Vision Pro faits le même jour (§9). | Apple | Attendre la décision d'Apple sur la déclaration DSA (Business → Compliance) ; répondre à toute demande de pièce. |

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
   reste `en` (non traité — §14).
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
| Version | iOS **1.0**, « Prepare for Submission » | 1.0.0 (le binaire, §11.3) | qu'App Store Connect rattache un build `1.0.0` à une version nommée « 1.0 » : UNVERIFIED — le vérifier en choisissant le build (§13) |
| TestFlight | aucun build | — | §11.5 — *2026-10-10 : builds 551 et 555 envoyés, traités `VALID` ; le groupe interne ne reçoit que le 555 (§11.6)* |

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
| Contact Info | **Name** | Oui | Oui | Non | App Functionality | nom du pro (Apple, Google, inscription) ; noms des clients saisis par le salon (fiche client, réservation manuelle) |
| Contact Info | **Email Address** | Oui | Oui | Non | App Functionality | e-mail de connexion ; e-mail des membres invités |
| Contact Info | **Phone Number** | Oui | Oui | Non | App Functionality | « Téléphone du salon », WhatsApp, téléphones des clients saisis par le salon |
| Contact Info | **Physical Address** | Oui | Oui | Non | App Functionality | « Adresse » à l'inscription, adresse du salon (publiée sur sa page) |
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

**Notes** (coller tel quel). Poids : **3 483 octets** (3 430 caractères) —
sous la limite de 4 000. Recompté le 2026-10-05 par script sur le texte exact
du bloc, sans le saut de ligne final (`printf '%s' "$(cat notes.txt)" | wc -c` ;
la même méthode redonne bien les 3 005 octets de la version du 2026-09-24).
*Historique : 3 005 octets avec la ligne réservée, 3 181 avec la seule phrase
(a) ; le 2026-10-05, la ligne réservée est remplacée par la phrase (a) suivie
d'une phrase sur l'essai (§2.4), et les deux dernières rubriques sont
corrigées (ci-dessous).*

```text
MyWeli Pro is the business app for beauty salons in Côte d'Ivoire (French UI). Salon owners and their staff manage their agenda, clients, services, photos and opening hours; their customers book through the separate MyWeli app and myweli.com.

HOW TO SIGN IN (demo account)
The app signs in with an e-mail address and a 6-digit code, not a password. The demo account uses a FIXED code that does not expire, so the Password field above contains that 6-digit code.
1. On the « Espace Pro » screen, type revue@myweli.test in the « Votre e-mail » field.
2. Tap « Continuer avec e-mail ». No e-mail is sent: the .test domain cannot receive mail, and the fixed code replaces the one normally e-mailed.
3. Type the code from the Password field in « Code à 6 chiffres », then tap « Se connecter ».
You land on « Salon Démo MyWeli », a complete demo salon: agenda with bookings, manual bookings, clients, services, photos, availability, journal and data export all work. The « Profil » icon at the top right of the « Accueil » screen opens the account menu.

Two actions are deliberately disabled for this shared demo account and say so on screen (« Compte de démonstration — cette action est désactivée. »): publishing the salon publicly, and inviting team members by e-mail (it would send e-mail to third parties).

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
Profil > « Supprimer mon compte », then type SUPPRIMER to confirm. Please do not delete the shared demo account: later reviews use it. If it has upcoming appointments, the app first asks to finish or cancel them. To test deletion end to end, please create a fresh account (below) and delete that one.

Sign in with Apple and Google only sign in to an existing salon account. A new identity is offered « Créer un compte », which opens the « Inscription Pro » form: fill in the salon's name, type, phone and address, then tap « S’inscrire avec Apple » to create a new, empty salon. Please use the demo account above to see a populated salon.
```

Libellés relus dans le code le 2026-09-24 : `pro_login_screen.dart`
(« Espace Pro », « Votre e-mail », « Continuer avec e-mail », « Code à 6
chiffres », « Se connecter »), `dashboard_screen.dart` (« Accueil », icône
« Profil »), `pro_profile_screen.dart` (« Profil du salon », « Vérification »,
« Mon abonnement », « Aide & Support », « Supprimer mon compte », mot
`SUPPRIMER`), `pro_salon_profile_screen.dart` (« Utiliser ma position »),
`commune_picker_sheet.dart` (« Près de moi »), `reviews_screen.dart` (« Avis »).
**Si un libellé change, ces notes changent dans la même PR.**

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
  Google »), qui ouvre ensuite « Accueil », pas l'onboarding.
- *Refus démo* : la phrase « Compte de démonstration — cette action est
  désactivée. » que la note promet **n'existait dans aucune surface de
  l'app** — un refus démo affichait « Une erreur est survenue. » (publication)
  ou « Une erreur est survenue. Réessayez. » (invitation). Elle est
  **implémentée sur cette branche** ([pro-companion-path.md](pro-companion-path.md)
  §2.2) ; la voir à l'écran sur le build TestFlight avant de soumettre
  (§11.6).

Pourquoi la rubrique ACCOUNT DELETION est écrite ainsi : la suppression n'est
pas verrouillée pour l'identité démo, et la remise à zéro hebdomadaire ne crée
des rendez-vous à venir qu'à J+1 et J+2
(`backend/lib/src/demo/demo_reset_service.dart`) — cinq jours sur sept, rien
n'arrête une suppression du compte démo. D'où la demande explicite, et le
compte Apple neuf pour tester la suppression de bout en bout (§14).

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
| Publication progressive | sans objet pour la 1.0.0 | elle s'applique aux **mises à jour** (utilisateurs en mise à jour automatique) ; à activer dès la 1.0.1 ([LAUNCH.md](../LAUNCH.md) §6.2) |

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

## 10 · Captures d'écran — iPhone 6,9 pouces seulement

L'app est iPhone uniquement (§1.2) : **aucun jeu iPad**. Un seul jeu, **6,9
pouces**, portrait, **1320 × 2868** (ou 1290 × 2796 ; 1260 × 2736 est aussi
accepté) ; Apple en dérive les tailles plus petites. **1 à 10** images, JPEG ou
PNG, **sans canal alpha ni transparence**.

**Sur le salon démo, après** le logo réel et la recapture du snapshot (§0 #4),
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
git checkout main && git pull --ff-only && git status --short    # doit être vide
./tool/release_build.sh ios pro
# → mobile/build/ios/ipa/MyWeli-pro.ipa (et DistributionSummary-pro.plist)
```

Le script choisit `lib/main_pro.dart` (`--target`), injecte le DSN sans
l'afficher, numérote le build au nombre de commits, obfusque et écrit les
symboles Dart dans `mobile/build/symbols/pro/`.

**Tout de suite après** — l'archive n'est pas rangée par saveur, le prochain
build consommateur l'écraserait (§14) :

```bash
cd "/Users/sadreddinedaher/beauty app/mobile"
N=$(unzip -p build/ios/ipa/MyWeli-pro.ipa Payload/Runner.app/Info.plist | plutil -extract CFBundleVersion raw -)
cp -R build/ios/archive/Runner.xcarchive "build/ios/archive/Runner-pro-$N.xcarchive"
```

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
  'CFBundleIdentifier|CFBundleName|CFBundleShortVersionString|CFBundleVersion|CFBundleLocalizations|UIDeviceFamily|NSLocationWhenInUse|NSCameraUsage|NSPhotoLibraryUsage|ITSAppUsesNonExempt'
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
| `CFBundleShortVersionString` / `CFBundleVersion` | `1.0.0` / **> 536** |
| `UIDeviceFamily` | **`[1]`** |
| `CFBundleLocalizations` | **`[fr]`** |
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

```bash
cd "/Users/sadreddinedaher/beauty app/mobile"
xcrun altool --validate-app build/ios/ipa/MyWeli-pro.ipa --api-key <KEY_ID> --api-issuer <ISSUER_ID>
xcrun altool --upload-package build/ios/ipa/MyWeli-pro.ipa --api-key <KEY_ID> --api-issuer <ISSUER_ID> --wait --show-progress
xcrun altool --build-status --delivery-id <DELIVERY_UUID_IMPRIMÉ_PAR_L_ENVOI> \
  --api-key <KEY_ID> --api-issuer <ISSUER_ID>
```

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
**C'est le build à soumettre ; le 551 reste dans TestFlight, jamais
soumis.**

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
build (555), un testeur.

- [ ] **Connexion démo** : `revue@myweli.test` + le code, exactement comme les
      notes du §8 le décrivent — c'est aussi le test « le code n'a pas expiré ».
- [ ] **Sign in with Apple** : crée un compte neuf (4.8 ; jamais exercé par
      un build signé). *Corrigé le 2026-10-05 : pas directement — « Continuer
      avec Apple » sur une identité neuve propose « Créer un compte » →
      « Inscription Pro » → « S’inscrire avec Apple » → « Accueil » (§8).*
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
- [ ] **« Mon abonnement »** : aucune mention de myweli.com, ni ligne de ROI,
      ni « Tarif personnalisé » ; et selon la voie choisie au §2.4, pas de
      sélecteur. *2026-10-05, voie (a) — sur le compte démo* : « Offre Pro
      active » / « Jusqu’au {date} », la jauge « {used} / {cap} places » et
      la ligne « Vos données ne sont jamais bloquées. », **rien d'autre** —
      ni carte d'offre, ni « Choisir » / « Changer d’offre », ni « 3 mois
      offerts », ni bouton « Aide & Support »
      ([pro-companion-path.md](pro-companion-path.md) §2.2 ; l'état « Pro »
      tient à la capture et à la remise à zéro démo, spec §3.3).
- [ ] Faire pivoter le téléphone : le paysage est encore permis (§14) —
      noter ce qui casse.

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
2. [ ] **Rétablir la facturation GCP.** Puis : Cloud SQL et Cloud Run servent
       (`/health` 200), « Production checks » vert, `DEMO_PROVIDER_CODE`
       lisible et monté sur la révision servie.
3. [ ] **Avant que quoi que ce soit ne touche la base staging** : établir où
       vit le salon démo curé (prod ? staging ?) — se connecter en démo contre
       la prod ; s'il n'existe qu'en staging, le recréer en prod par l'app.
       *2026-10-05 : le recréer ne demande plus aucun choix d'offre dans
       l'app. Sa ligne d'offre Pro est créée par la **capture du snapshot**
       (point 4) : `POST /admin/demo/snapshot` crée la ligne si elle manque,
       épingle `tier = pro` et `paidUntil = maintenant + 30 jours`, comme
       chaque remise à zéro hebdomadaire ensuite. « Mon abonnement » affiche
       donc « Offre Pro active » dès la capture
       ([backend-demo-review-account.md](backend-demo-review-account.md) §6.2,
       §9).*
4. [ ] **Salon démo** : prestations, photos, horaires, agenda ; « Publier » et
       « Inviter » répondent 403 `demo_account_locked` ; téléverser le **vrai
       logo** ; **recapturer le snapshot** (`POST /admin/demo/snapshot`) ;
       consigner date + environnement dans
       [backend-demo-review-account.md](backend-demo-review-account.md) §9.
       *2026-10-05 : et « Mon abonnement » affiche « Offre Pro active »
       (§11.6).*
5. [ ] Fusionner la PR de l'audit (et celle du point 1) ; CI vert sur `main`.
       *2026-10-05 : la PR de l'audit (#550) est fusionnée — squash
       `f6ffb585` ; reste celle du point 1.*
6. [ ] **Déployer en production le backend de la voie compagnon** (feu vert
       du propriétaire, après le point 2) **avant la soumission** : l'essai qui
       démarre à la première mise en ligne et les verrous démo doivent tourner
       quand le relecteur crée son compte neuf. Depuis « Accueil », il peut
       ouvrir « Configurer mon profil » et mettre ce salon en ligne ; sans ce
       backend, il lirait « …l’offre de votre salon n’est plus active. » pour
       une offre qui n'a jamais existé (spec §9.3–9.4).
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
       archive rangée en `Runner-pro-555.xcarchive`.*
12. [x] **Valider, envoyer**, attendre le traitement (§11.5). *555 `VALID`.*
13. [ ] **TestFlight interne** et toutes les cases du §11.6. *Groupe et
       invitation faits le 2026-10-10 ; les vérifications sur l'appareil
       restent au propriétaire.*
14. [x] **Symboles Sentry** (§12.2). *Dart et natifs, build 555.*
15. [ ] **Captures** 6,9 pouces sur le salon démo (§10).
16. [ ] **Remplir App Store Connect** : informations sur l'app (§3, §5, §6,
       §9), tarifs et disponibilité — Côte d'Ivoire seule, Mac et Vision Pro
       décochés (§9), confidentialité (§7), page 1.0.0 — captures, texte
       promotionnel, description, mots-clés, URL, copyright, **build**,
       publication **manuelle** (§4, §9, §10), informations pour la revue avec
       le code lu à ce moment-là et la **ligne SUBSCRIPTION remplacée** (§8).
       *2026-10-05 : la ligne est remplacée dans le dossier — coller les notes
       du §8 telles quelles ; le nom « MyWeli Pro — Gestion de salon » si le
       propriétaire le retient (§3) ; vérifier que le build 1.0.0 se rattache
       à la version « 1.0 » (§3, UNVERIFIED).*
17. [ ] **`updateUrl` iOS** dans la console admin (§12.1).
18. [ ] **Porte d'entrée Cloudflare** : ne pas lancer la phase A pendant une
       revue ; si elle a été déployée avant, vérifier qu'un client non
       navigateur (l'app) n'est pas mis au défi par Browser Integrity Check /
       Bot Fight Mode sur `api.myweli.com`
       ([infra-cloudflare-front-door.md](infra-cloudflare-front-door.md)).
19. [ ] **Le jour même** : connexion démo sur le build TestFlight contre la
       prod, « Production checks » vert.
20. [ ] **Soumettre pour la revue.** Ne plus toucher au code démo tant que la
       version est en revue.
21. [ ] Après approbation : **ne pas publier** avant que [LAUNCH.md](../LAUNCH.md)
       §3 le permette (production rétablie et stable) — la publication est
       manuelle (§9).

---

## 14 · Points ouverts et mineurs connus, non corrigés

| Point | Nature | Risque / suite |
|---|---|---|
| **1.2 — pas de « Signaler » dans « Avis » côté Pro.** `POST /reviews/{id}/report` répond 403 à tout rôle autre que `user` (`backend/routes/reviews/[id]/report.dart`). | code | Faible (le salon démo n'a probablement pas d'avis) ; atténué par la rubrique USER CONTENT des notes. Suite : autoriser le salon à signaler les avis de son propre salon + « Signaler » sur la tuile. |
| **5.1.1(v) — Sign in with Apple : jetons non révoqués** à la suppression (Apple : « should » appeler `/auth/revoke`). | code + clé owner | Rarement testé en revue. Suite : capter l'`authorizationCode`, l'échanger côté serveur (clé privée Sign in with Apple, portail), révoquer à la suppression. Peut suivre le lancement. |
| **Suppression du propriétaire : le salon garde ses coordonnées** (téléphone, WhatsApp, numéro Mobile Money, adresse) en brouillon (`provider_account_service.dart`). | décision | Divulgué par la politique et `/suppression-compte`. Suite : effacer ces champs à la suppression, garder l'historique. |
| **Politique de confidentialité** : pas la phrase « nos sous-traitants offrent une protection équivalente » (5.1.1(i)) ; dit « Profil → Exporter mes données » là où l'app Pro dit « Mes données ». | web (texte légal) | Une phrase + aligner le libellé (`web/app/politique-confidentialite/page.tsx`). |
| **Mode d'arrière-plan `remote-notification` inutilisé** (`UIBackgroundModes`) : le backend n'envoie jamais `content-available`. | code, optionnel | Rarement rejeté. Le retirer puis revérifier sur appareil qu'une notification arrive app tuée/en arrière-plan et que le tap route. |
| **Paysage non verrouillé sur iPhone** (`UISupportedInterfaceOrientations`, aucun `setPreferredOrientations`). | décision | Qualité, pas une règle : écrans écrasés si le relecteur pivote. Portrait seul sur iPhone, ou une passe en paysage. |
| **Identité démo non recréée si supprimée** ; la suppression n'est pas verrouillée ; les rendez-vous à venir de la remise à zéro n'existent qu'à J+1/J+2. | code/décision | Les notes l'évitent (§8). Sinon : recréer par l'app + recapturer, ou faire recréer l'identité par la remise à zéro. |
| **`tool/release_build.sh` exige Secret Manager** (`MOBILE_SENTRY_DSN`). | owner | Aucun build tant que la facturation est fermée. Prendre le DSN dans la console Sentry et construire à la main enfreindrait la règle « personne ne manipule le DSN » : décision, pas défaut. |
| **L'archive Xcode n'est pas rangée par saveur** : `build/ios/archive/Runner.xcarchive` est écrasée par le build suivant (celle du 2026-08-29 est aujourd'hui l'archive **consommateur**). | code | Contourné à la main au §11.2. Suite : que le script la renomme en `Runner-$FLAVOUR.xcarchive` et imprime les dSYM dans la commande Sentry. |
| **5.1.1(ix) — KYC et compte développeur individuel.** Pièce d'identité + photo du visage, vendeur = personne physique, société non immatriculée (`infra/legal/registration-manifest.json`). | décision | Majeur maintenu par l'audit, appliqué de façon inégale par Apple. Atténué par la rubrique IDENTITY DOCUMENTS. Si rejet : masquer le KYC et les acomptes sur iOS jusqu'au compte Organisation. Type d'adhésion à confirmer (developer.apple.com → Membership). |
| Numéro de build = nombre de commits de **n'importe quelle** `HEAD` : un build de branche peut griller un numéro. | code, optionnel | Construire depuis `main` (§11.2). |
| `CFBundleDevelopmentRegion` reste `en`. | code, optionnel | Sans effet visible attendu une fois `CFBundleLocalizations = [fr]` ; à vérifier sur l'alerte de permission (§11.6). |
| Le dialogue de suppression dit « Votre salon sera retiré de MyWeli » même à un membre d'équipe. | code | Texte à ajuster pour le personnel. |
| Taux de sessions sans plantage perdu (sessions Sentry coupées). | assumé | L'alerte « crash-free sessions » de l'observabilité doit être revue (plantages et blocages restent signalés). |

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
