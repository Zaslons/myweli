# Play Console — les formulaires, réponse par réponse

| | |
|---|---|
| **Status** | **Ré-audité le 2026-10-28 (BACKLOG B0.10)** contre le binaire, la politique publiée, l'étiquette App Store relue ce jour-là et les règles Play en vigueur. **MyWeli Pro seule pour l'instant** (décision 51) ; la saisie se fait dans le volet navigateur, formulaire par formulaire, montré au propriétaire avant chaque enregistrement (décision 53). Historique : rédigé 2026-08-28 ; corrigé 2026-09-24 (libellés de connexion, adresse et numéro Mobile Money) ; 2026-10-05 (plus de choix d'offre dans l'app Pro Android) ; 2026-10-13 (texte d'accès amendé, verrou de suppression du compte démo). |
| **Portée** | **MyWeli Pro** (`com.myweli.pro`) maintenant. MyWeli (`com.myweli.app`) au §8, à ré-auditer avant sa soumission. |
| **Source de vérité** | La politique de confidentialité publiée (`/politique-confidentialite`) et le binaire — un formulaire qui les contredit est un rejet ET une exposition légale (LAUNCH.md §6.3) |
| **Règle** | Chaque réponse ci-dessous est dérivée du code, du binaire ou de la politique, jamais inventée. En cas de doute en saisissant : STOP, on vérifie. |
| **Garde-fous** | `mobile/test/infra/play_store_forms_test.dart` (longueurs du §1 contre les limites de Play ; le texte de connexion du §2 sous les 500 caractères que compte la console, et ses libellés contre l'écran de connexion Pro) · `mobile/test/infra/app_review_notes_test.dart` (la phrase du compte démo, le verrou de suppression) |

Ordre conseillé dans la console : **Fiche du Play Store → Contenu de
l'application (§2 à §5) → Test fermé (§6)**.

---

## 0 · Ce qui a changé le 2026-10-28, et pourquoi

**Les décisions du propriétaire** (BACKLOG, décisions 51 à 54) :

1. **MyWeli Pro seule sur Play pour l'instant.** La production n'affiche
   **aucun salon public** (`GET /providers` → `total: 0`, lu le 2026-10-28, une
   route inexistante en témoin → 404). L'app client s'ouvrirait vide pour le
   relecteur de Google et pour quiconque l'installe. Comme sur iOS, l'app Pro
   d'abord, pour que les salons s'inscrivent ; MyWeli suivra (§8).
2. **Le compte développeur Play est un compte personnel.** Production
   n'est accessible qu'après un **test fermé : 12 testeurs inscrits sans
   interruption pendant 14 jours** (§6).
3. **La saisie** : Claude dans le volet navigateur, le propriétaire connecté,
   chaque formulaire montré avant d'être enregistré.
4. **Les captures** : les 8 cadres déjà approuvés pour l'App Store, recomposés
   au format de Play (§1.3).

**Ce que l'audit a lu et changé.**

- **Le binaire** (APK de version Pro et client construits le 2026-10-28,
  `aapt2 dump`) :
  - `targetSdkVersion` **36**, ce que Play exige depuis le 2026-08-31 ;
  - permissions : `INTERNET`, `ACCESS_FINE_LOCATION`/`COARSE`,
    `POST_NOTIFICATIONS`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `VIBRATE`,
    `USE_BIOMETRIC`/`USE_FINGERPRINT`, et la réception FCM ;
  - **aucune** permission de photos ou de médias (le sélecteur du système
    suffit), **aucun** `AD_ID`, aucune alarme exacte, aucun service au
    premier plan. Aucune déclaration de permission n'est donc due (§5).
- **Les règles de Play**, relues sur les pages de Google le 2026-10-28 :
  - **les journaux de plantage et les diagnostics ont la finalité
    « Analyses »** : c'est la définition de Google (« to monitor app health,
    to diagnose and fix bugs or crashes »). L'ancien §4 disait qu'aucune
    donnée n'avait cette finalité ; corrigé au §4 ;
  - **« ID utilisateur » manquait**, alors que l'étiquette App Store le
    déclare ;
  - « Accès à l'application » s'appelle désormais **« Informations de
    connexion »**, et Google veut les identifiants et les instructions **en
    anglais** : le texte du §2 l'est ;
  - **« Fonctionnalités financières » et « Applications de santé » sont dues
    par toute app**, même sans ces fonctionnalités (§5).
- **Le code depuis août** :
  - B0.11 (#711) : l'app Pro ne crée plus de compte ni de salon, l'« Adresse
    à l'inscription » n'existe plus dans l'app ;
  - la recherche de clients envoie le texte cherché dans l'adresse de la
    requête (`?query=`). **Google Cloud garde cette adresse 30 jours dans ses
    journaux** (lu dans Cloud Logging le 2026-10-28 : l'URL entière, chaîne de
    requête comprise). C'est donc une donnée collectée : « Historique des
    recherches dans l'application » au §4. L'ancienne justification d'Apple
    (« le serveur ne journalise que le chemin, jamais la requête ») est fausse
    pour les journaux de Google Cloud ; voir BACKLOG B0.15.
- **La longueur des instructions de connexion** : aucune page d'aide de
  Google n'en donne, **mais la console en compte une**. Lu dans le formulaire
  le 2026-10-28 : nom de l'ensemble 60 caractères, identifiant 100, mot de
  passe 100, « Toute autre information » **500**. Le test de longueur prévu
  par B0.10 tient donc ce texte sous 500, et les textes de la fiche sous les
  limites de Play (§1).

---

## 0.1 · Dans la console, le 2026-10-28

Saisi dans le volet navigateur, chaque formulaire montré au propriétaire avant
d'être enregistré, puis relu.

- **« Contenu de l'application » : les 10 déclarations traitées.** La page dit
  « Vous savez tout ! ».
  - Règles de confidentialité, Annonces (non), Identifiant publicitaire (non),
    Applis gouvernementales (non), Fonctionnalités financières (aucune),
    Applis de santé (aucune).
  - **Informations de connexion** : l'ensemble « Demo salon (shared review
    account) », l'identifiant, le mot de passe tapé par le propriétaire, et le
    texte du §2 (463/500).
    - **La case « accès complet à toutes les fonctionnalités » est cochée.**
      La console refuse l'ensemble sans elle. Les trois actions désactivées
      sont nommées dans le même texte (choix du propriétaire).
    - **Les tests automatiques de Google avec ces identifiants restent
      activés** (réglage par défaut). Le propriétaire l'a choisi en sachant
      que les robots peuvent modifier le salon démo partagé avec la revue
      Apple jusqu'à la réinitialisation hebdomadaire.
  - **Cible et contenu** : 18 ans et plus.
  - **Classification du contenu** : catégorie « Tous les autres types
    d'applications », contact `support@myweli.com`, conditions de l'IARC
    acceptées (propriétaire).
    - Les réponses du §3 donnent **3 ans et plus** (IARC), **PEGI 3**, ESRB
      **Tout public**, USK et ClassInd « tous publics », avec la seule mention
      « Interactivité des utilisateurs ».
    - C'est le « 4+ » voulu, comme Planity Pro.
  - **Sécurité des données** : les 15 types du §4, tous « collectés », aucun
    « partagé », aucun éphémère.
    - Les finalités portent les libellés de la console : « Fonctionnement de
      l'appli », « Gestion des comptes », « Analyse », « Prévention des
      fraudes, sécurité et conformité ».
    - Création de compte : « Nom d'utilisateur et autre authentification » et
      « OAuth » ; Google compte aussi un compte créé sur le Web vers lequel
      l'app renvoie.
    - L'URL de suppression : `https://myweli.com/suppression-compte`.
    - Aperçu relu : « Aucune donnée partagée avec des tiers ».
- **Paramètres de la fiche** : catégorie **Professionnel**, e-mail
  `support@myweli.com`, site `https://myweli.com`, pas de téléphone.
  - Ces coordonnées sont « publiées » aussitôt, sur l'accord du propriétaire.
  - Le site, d'abord enregistré en `http://` (le « https:// » du champ était
    une indication, pas un préfixe), a été corrigé et relu.
- **Fiche par défaut (fr-FR)** : nom, description courte et description
  complète **enregistrés en brouillon**, relus caractère pour caractère
  (29/30, 70/80, 996/4000).
  - **Restent les images** (icône, bannière, 8 captures) : le volet
    navigateur ne peut pas joindre de fichier. Le propriétaire les dépose
    depuis `build/play-store/pro/`.
- **Rien n'est envoyé pour examen.** Les modifications attendent dans « Vue
  d'ensemble de la publication », avec la première version du test fermé (§6).

## 1 · Fiche du Play Store (Store listing) — MyWeli Pro

Limites de Play (aide Play, « Add product details ») : nom 30 caractères,
description courte 80, description complète 4 000. Le test les relit.

- **Nom de l'app** : `MyWeli Pro — Gestion de salon` (29 caractères ; le nom
  de l'App Store, §4 d'[app-store-forms.md](app-store-forms.md))
- **Description courte** :
  `L'agenda, la clientèle et les réservations de votre salon, en une app.`
- **Description complète** — la même que sur l'App Store, mot pour mot, en
  texte brut (Play n'interprète pas le Markdown : un `**` collé s'afficherait
  tel quel) :

**Description complète** (coller tel quel) :

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

### 1.1 Catégorie et coordonnées

- **Catégorie** : Appli → **Professionnel** (« Business » en anglais : la
  console française ne dit pas « Entreprise », lu le 2026-10-28), comme
  « Économie et entreprise » sur l'App Store.
- **Adresse e-mail** : `support@myweli.com` — **lue**, vérifiée le 2026-10-28
  (BACKLOG, lot 10).
- **Site Web** : `https://myweli.com`.
- **Téléphone** : aucun (facultatif).
- **Politique de confidentialité** (Contenu de l'application) :
  `https://myweli.com/politique-confidentialite`.

### 1.2 Icône et bannière

Produites par `tool/app_store_screenshots/` à partir des captures brutes du
tournage App Store (`build/app-store/pro/raw`, hors dépôt) :

```bash
python3 tool/app_store_screenshots/feature_graphic.py --raw build/app-store/pro/raw --out build/play-store/pro
python3 tool/app_store_screenshots/play_screenshots.py --raw build/app-store/pro/raw --out build/play-store/pro
```

- **Icône** `icon-512.png` : 512 × 512, PNG 32 bits opaque. C'est l'icône
  1024 de l'app Pro (`AppIcon-pro.appiconset`, pas celle de l'app client),
  réduite. Elle est carrée, sans coins arrondis : Play applique son propre
  masque.
- **Bannière** `feature-graphic-1024x500.png` : 1024 × 500, PNG 24 bits sans
  alpha.
  - Le symbole, « MyWeli Pro », la description courte, et la capture
    « Ma journée » dans la carte des cadres App Store.
  - **La barre d'état de l'iPhone est coupée** (« 09:41 », réseau,
    batterie) : elle n'a rien à faire sur une fiche Android.

### 1.3 Captures de téléphone — les 8 cadres approuvés, au format de Play

- **Pourquoi pas les cadres App Store tels quels :** ils font 1206 × 2622, et
  la console exige des captures « en 16:9 ou 9:16 » (sa règle d'import, lue
  dans le formulaire le 2026-10-28). La page d'aide de Google dit encore « le
  grand côté au plus deux fois le petit » : un premier jet en 1080 × 2160,
  conforme à la page, aurait été refusé par la console.
- **Les cadres de Play** font **1080 × 1920** (9:16), en PNG 24 bits sans
  alpha.
  - Mêmes titres, mêmes captures, mêmes masques que l'App Store
    (`screens.json`).
  - La barre d'état de l'iPhone est coupée. La carte est plus étroite (777
    au lieu de 960 sur la mise en page de référence), pour que tout l'écran
    tienne.
  - Au moins 4 captures d'au moins 1080 px rendent la fiche éligible aux mises
    en avant de Play : les 8 le sont.
- **Ordre** : 01 Agenda · 02 Aperçu de la page · 03 Accueil · 04 Réservation ·
  05 Fiche client · 06 Prestations · 07 Disponibilité · 08 Revenus.

Ce qui reste d'iOS dans les captures, dit franchement : la flèche de retour
(‹) est celle d'iOS, celle d'Android est ←. Le reste de l'interface est la même
app Flutter.

---

## 2 · Informations de connexion (Sign-in details)

Choisir « **Tout ou partie des fonctionnalités sont restreintes** », puis
ajouter des instructions :

- **Nom d'utilisateur** : `revue@myweli.test`
- **Mot de passe** : le code à 6 chiffres. Il est dans Secret Manager,
  **jamais dans ce repo ni dans le chat**. Le lire sur ton poste au moment de
  remplir :

  ```bash
  gcloud secrets versions access latest --secret=DEMO_PROVIDER_CODE --project=myweli
  ```

  C'est **le même code que pour la revue Apple**. Aucune rotation tant
  qu'Apple n'a pas rendu sa décision (B0.1).
- **Ce que Google exige :** des identifiants qui marchent toujours, de
  partout, réutilisables, sans code à usage unique, en anglais. Le compte démo
  a un code **fixe qui n'expire pas** : c'est exactement ce que Google demande.

- **Nom** de l'ensemble (60 caractères au plus) : `Demo salon (shared review account)`

**Instructions supplémentaires** (coller tel quel — en anglais, comme Google le demande ; dans « Toute autre information requise pour accéder à votre appli », **500 caractères au plus**, retours à la ligne compris — celui-ci en fait 463) :

> Sign-in is an e-mail and a 6-digit code. The demo code is FIXED and never expires: it is the password above.
> 1. On « Espace Pro », type revue@myweli.test in « Votre e-mail ».
> 2. Tap « Continuer avec e-mail ». No e-mail is sent.
> 3. Type the code in « Code à 6 chiffres », tap « Se connecter ».
> Three actions are disabled on this shared demo salon and say « Compte de démonstration — cette action est désactivée. »: publishing, inviting staff, deleting the account.

Une ligne de citation = une ligne collée. Le reste de ce que disent les notes
App Store (paiements, pièces d'identité, modération, position) ne tient pas
dans 500 caractères. Il n'est pas nécessaire pour se connecter, et le reste du
formulaire le dit.

- **Pourquoi « trois actions »** : la suppression du compte démo est bloquée
  en production depuis le 2026-10-14. C'est la ligne datée d'app-store-forms
  §8, que `app_review_notes_test.dart` relit.
- **Ce texte remplace les deux blocs français** (« en vigueur » et
  « amendé »), qui ne sont plus à coller.
- **Les étapes 1 à 3 citent les libellés de l'écran de connexion Pro**, et le
  test les relit dans `pro_login_screen.dart`.

---

## 3 · Classification du contenu (questionnaire IARC)

Catégorie **« Utilitaire, productivité, communication ou autre »** :

| Question | Réponse |
|---|---|
| Violence, contenu sexuel, langage grossier, substances, jeux d'argent | **Non** partout |
| L'app permet-elle aux utilisateurs d'interagir ou d'échanger du contenu ? | **Oui.** Le salon publie sa page (photos, textes) ; les clients publient des avis, que l'app Pro affiche. Pas de messagerie entre utilisateurs : l'envoi de confirmations est un stub local (`MockMessagingService`, aucun envoi). |
| Partage-t-elle la position actuelle de l'utilisateur avec d'autres ? | **Non** — le point d'un salon est une adresse d'établissement, placée volontairement (« Utiliser ma position »), pas la position en temps réel d'une personne |
| Achats numériques dans l'app ? | **Non** — aucun paiement dans l'app ; l'acompte se règle hors app, au salon, par Mobile Money ; « Mon abonnement » n'affiche que l'état de l'offre |
| Contenu généré par les utilisateurs : modération | Les avis exigent une visite terminée, les clients les signalent, un administrateur peut masquer un avis ou suspendre un salon (notes de revue App Store, « USER CONTENT ») |

Résultat attendu : **Tout public / PEGI 3**, avec la mention « Interaction
entre utilisateurs ».

*2026-10-05 :* l'app Pro Android ne propose plus de choix d'offre non plus
([pro-companion-path.md](pro-companion-path.md) §11 Q3) — une seule conduite
sur les deux stores, cohérente avec « Achats numériques : Non ».

---

## 4 · Sécurité des données (Data safety) — MyWeli Pro

**Les questions générales :**

- **Collecte ou partage de données requises** : **Oui**.
- **Toutes les données sont-elles chiffrées en transit ?** **Oui** : tout
  passe en HTTPS.
- **Les utilisateurs peuvent-ils demander la suppression de leurs données ?**
  **Oui**.
  - URL : `https://myweli.com/suppression-compte`, qui répond 200 et couvre
    les comptes professionnels (lu le 2026-10-28).
  - Dans l'app : Profil → « Supprimer mon compte ».
- **« Partagées » au sens de Play** (transférées à un tiers pour SES fins) :
  **Non, pour toutes les données.** Google Cloud, Firebase, Sentry, Resend et
  Cloudflare traitent pour notre compte, sur nos instructions : Play les
  classe en « collecte », pas en « partage ». Nous ne vendons ni ne louons
  rien.
- **Aucune donnée n'a la finalité** « Publicité ou marketing »,
  « Personnalisation » ni « Communications du développeur ».

**Les données collectées.** Aucune n'est partagée, aucune n'est traitée de
façon éphémère seulement.

| Catégorie → type Play | Obligatoire ? | Finalités | Ce que c'est, dans l'app Pro |
|---|---|---|---|
| Informations personnelles → **Nom** | Obligatoire | Fonctionnalités de l'appli · Gestion du compte | le nom du pro (Google, Apple, profil) ; les noms des clients saisis par le salon |
| Informations personnelles → **Adresse e-mail** | Obligatoire | Fonctionnalités de l'appli · Gestion du compte | l'e-mail de connexion ; l'e-mail des membres invités |
| Informations personnelles → **ID utilisateur** | Obligatoire | Fonctionnalités de l'appli · Gestion du compte | l'identifiant du compte (le `sub` du jeton) — *ajouté le 2026-10-28* |
| Informations personnelles → **Adresse** | Facultatif | Fonctionnalités de l'appli | l'adresse du salon, saisie dans « Profil du salon », publiée sur sa page |
| Informations personnelles → **Numéro de téléphone** | Facultatif | Fonctionnalités de l'appli | « Téléphone du salon », WhatsApp, les téléphones des clients saisis par le salon |
| Informations personnelles → **Autres infos** | Facultatif | Fonctionnalités de l'appli · Prévention des fraudes, sécurité et conformité | pièces KYC — identité, photo du visage, RCCM, justificatif d'adresse : stockage privé, jamais publiées, lues par un administrateur |
| Informations financières → **Autres infos financières** | Facultatif | Fonctionnalités de l'appli | le numéro **Mobile Money de réception** des acomptes, publié sur la page du salon |
| Position → **Position exacte** | Facultatif | Fonctionnalités de l'appli | le point du salon (« Utiliser ma position ») — latitude et longitude envoyées et **publiques** |
| Photos et vidéos → **Photos** | Facultatif | Fonctionnalités de l'appli · Prévention des fraudes, sécurité et conformité | galerie, logo, avant/après, photos d'équipe (publiques) ; images KYC (privées) |
| Fichiers et documents → **Fichiers et documents** | Facultatif | Fonctionnalités de l'appli · Prévention des fraudes, sécurité et conformité | les pièces KYC envoyées en PDF (`pro_kyc_screen.dart` accepte jpg, png, webp et **pdf**) — *ajouté le 2026-10-28* |
| Activité dans les applis → **Historique des recherches via une appli** | Facultatif | Fonctionnalités de l'appli | le texte cherché dans « Clients » (`?query=`), gardé 30 jours dans les journaux de requêtes de Google Cloud — *ajouté le 2026-10-28* |
| Activité dans les applis → **Autre contenu généré par l'utilisateur** | Facultatif | Fonctionnalités de l'appli | prestations et tarifs, descriptions, horaires, notes clients, notes de réservation |
| Infos et performances des applis → **Journaux de plantage** | Obligatoire | **Analyses** | Sentry — utilisateur, fil d'Ariane, requête et extras retirés avant envoi (`beforeSend`) |
| Infos et performances des applis → **Diagnostics** | Obligatoire | **Analyses** | les blocages (app hangs) que Sentry envoie quand il en survient |
| Appareil ou autres ID → **Appareil ou autres ID** | Obligatoire | Fonctionnalités de l'appli | l'ID d'installation Firebase et le jeton FCM (`device_tokens`) — le SDK FCM crée l'ID d'installation à l'initialisation |

**Non collectées**, et pourquoi :

- **Position approximative** : « Près de moi » choisit la commune **sur
  l'appareil** ; seule la commune part, dans l'adresse.
- **Historique des achats, infos de paiement** : rien ne s'achète dans l'app ;
  le prix d'une réservation manuelle est calculé par le serveur.
- **Interactions avec l'appli** : aucun SDK d'analyse ; le tableau de bord
  admin compte des lignes opérationnelles, pas des événements de comportement.
- **Messages, contacts, agenda, santé, fichiers audio, navigation Web,
  applis installées, identifiant publicitaire** (aucun `AD_ID` dans le
  manifeste) : **Non**.

**Avant de valider** : Play affiche un aperçu de la section. Le relire à côté
de `/politique-confidentialite` et de l'étiquette App Store relue le
2026-10-28 (app-store-forms §7) : les trois doivent raconter la même histoire.
Les deux taxonomies ne se recoupent pas une pour une. Apple range les
plantages sous « App Functionality », Google sous « Analyses ». Chacun suit sa
propre définition, et c'est voulu.

---

## 5 · Les autres déclarations du « Contenu de l'application »

| Déclaration | Réponse | Pourquoi |
|---|---|---|
| Politique de confidentialité | `https://myweli.com/politique-confidentialite` | aussi liée dans l'app (Profil → « À propos ») |
| Annonces | **Non, l'app ne contient pas d'annonces** | aucun SDK publicitaire |
| Identifiant publicitaire | **Non, l'app ne l'utilise pas** | aucun `com.google.android.gms.permission.AD_ID` dans le manifeste fusionné (lu le 2026-10-28) |
| Classification du contenu | le questionnaire du §3 | |
| Public cible et contenu | **18 ans et plus** ; pas destinée aux enfants | un outil de gestion pour des professionnels |
| Applications d'actualités | **Non** | |
| Applications gouvernementales | **Non** | |
| Fonctionnalités financières | **Aucune** de la liste | aucun paiement traité ; l'acompte va du client au salon, hors app |
| Applications de santé | **Aucune** fonctionnalité de santé | la beauté n'est pas la santé au sens de Play |
| COVID-19 (si la console la propose encore) | **Non** | |
| Informations de connexion | le §2 | |
| Déclarations de permissions (photos, alarmes exactes, service au premier plan, localisation en arrière-plan…) | **aucune n'est due** | aucune de ces permissions dans le manifeste fusionné (§0) |

---

## 6 · Le test fermé — la porte de la production (compte personnel)

Un compte personnel créé après le 13 novembre 2023 doit tenir un **test fermé
avec au moins 12 testeurs inscrits sans interruption pendant 14 jours** avant
de pouvoir demander l'accès à la production. Les testeurs qui se désinscrivent
ne comptent plus. L'examen de la demande prend en général 7 jours ou moins.
([aide Play 14151465](https://support.google.com/googleplay/android-developer/answer/14151465),
lu le 2026-10-28.) Le **test interne ne compte pas**
([mobile-external-testing.md](mobile-external-testing.md) §4).

Ce que cela veut dire pour MyWeli Pro :

1. **La section Sécurité des données est exigée dès le test fermé** (seul le
   test interne en est dispensé) : les §2 à §5 se remplissent avant.
2. **Un build signé** (AAB, `tool/release_build.sh`) et la clé d'importation
   **sauvegardée** (LAUNCH §6.3) précèdent le premier envoi.
3. **Les 12 testeurs, c'est toi qui les trouves.** Ce sont 12 comptes Google
   qui installent et gardent l'app 14 jours. Idéalement des salons : ils ont
   un compte MyWeli Pro (inscription sur myweli.com) ou une invitation
   d'équipe. Le compte démo reste réservé aux relecteurs.

---

## 7 · Après la saisie

1. Chaque formulaire est relu à l'écran avant d'être enregistré ; à la fin,
   l'aperçu de la Sécurité des données est relu contre la politique.
2. LAUNCH §6.3 : « Data safety form completed » se coche alors, avec la date.
3. **La page de suppression de compte doit nommer l'app ou le développeur
   exactement comme la fiche** (aide Play 13327111). Elle dit « MyWeli » et
   couvre les professionnels. Le nom de développeur du compte Play est à
   comparer pendant la saisie.

---

## 8 · MyWeli (client) — plus tard, à ré-auditer avant la soumission

**Pas maintenant** (décision 51) : la production n'a aucun salon public. Les
textes ci-dessous sont ceux du 2026-08-28. **Avant de les saisir, refaire
l'audit de ce document**, sur le binaire et sur Play à ce moment-là. Points déjà
connus :

- **La description** dit « Vous êtes un salon ? Téléchargez MyWeli Pro… ».
  Depuis B0.11, l'app Pro ne crée plus de compte. À dire : « inscrivez-vous sur
  myweli.com, puis gérez… avec MyWeli Pro ».
- **Les instructions de connexion** doivent être en anglais. Elles doivent
  aussi citer l'étape obligatoire « Votre numéro de téléphone » : tout numéro
  valide, de n'importe quel pays ; 10 chiffres après +225 ; aucun SMS envoyé,
  `MESSAGING_PROVIDER=disabled`.
- **La Sécurité des données** suit les mêmes corrections que le §4 :
  - les plantages ont la finalité « Analyses » ;
  - « ID utilisateur » est à ajouter ;
  - la photo de profil, l'avatar du client, entre dans « Photos » ;
  - la recherche de salons (`?q=`) est gardée 30 jours dans les mêmes journaux
    de requêtes.

### 8.1 Fiche (texte du 2026-08-28)

- **Nom** : `MyWeli — Beauté & rendez-vous`
- **Description courte** :
  `Réservez coiffure, tresses, onglerie et spa près de chez vous, 24h/24.`
- **Description complète** : celle du 2026-08-28 (historique git de ce
  fichier), à reprendre en texte brut avec la correction ci-dessus.
- **Catégorie** : Beauté.

### 8.2 Sécurité des données (table du 2026-08-28, à corriger comme dit plus haut)

| Type Play | Collecté ? | Facultatif ? | Finalité |
|---|---|---|---|
| Nom | Oui | Non (compte) | Gestion du compte |
| E-mail | Oui | Non | Gestion du compte |
| N° de téléphone | Oui | Non (contact réservation) | Fonctionnement |
| Position (approximative ET précise) | **Non collectée** — uniquement sur l'appareil | — | — |
| Photos | Oui — photos d'avis, preuve d'acompte | Oui | Fonctionnement |
| Contenu généré par l'utilisateur | Oui — avis, notes de réservation | Oui | Fonctionnement |
| Journaux de plantage, Diagnostics | Oui (Sentry) | Non | **Analyses** |
| Appareil ou autres ID | Oui — FCM | Oui | Fonctionnement |
| Infos financières | **Non** — la preuve d'acompte est une image (Photos) | — | — |
