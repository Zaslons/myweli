# Play Console — les formulaires, réponse par réponse

| | |
|---|---|
| **Status** | **2026-11-19 et 20, l'étape 8 : le test fermé est actif.** La piste « Tests fermés - Alpha » vise 178 pays et régions, ses testeurs sont le groupe de Testers Community, et la version 788 y est promue ; envoyée à l'examen, elle est publiée le 19 novembre, « Disponible pour certains testeurs » (§0.5). **2026-11-19, dans la console (l'étape 7 d'[android-play-release.md](android-play-release.md)) : la description, les instructions des relecteurs et la Sécurité des données enregistrées et relues ; le statut de professionnel déclaré pour le compte, puis pour MyWeli Pro et MyWeli ; l'e-mail public du développeur devient `support@myweli.com` ; rien n'est envoyé pour examen (§0.4).** **2026-11-19 : l'inscription revient dans l'app Android (B0.17, décisions 116 à 123)** — la description, les instructions des relecteurs, la sécurité des données et le test fermé ; ce qui a changé est au §0.3. **2026-11-11 : mis à jour après la sortie iOS (décisions 110 à 115)** — l'ordre de la sortie Android, du build à la production, est dans [android-play-release.md](android-play-release.md) ; ce qui a changé ici est au §0.2. **Ré-audité le 2026-10-28 (BACKLOG B0.10)** contre le binaire, la politique publiée, l'étiquette App Store relue ce jour-là et les règles Play en vigueur. **MyWeli Pro seule pour l'instant** (décision 51) ; la saisie se fait dans le volet navigateur, formulaire par formulaire, montré au propriétaire avant chaque enregistrement (décision 53) ; les images, que le volet ne peut pas joindre, importées dans Chrome. **Dans la console le 2026-10-28 : tout le « Contenu de l'application » et la fiche, images comprises, enregistrés et relus ; rien envoyé pour examen (§0.1).** Historique : rédigé 2026-08-28 ; corrigé 2026-09-24 (libellés de connexion, adresse et numéro Mobile Money) ; 2026-10-05 (plus de choix d'offre dans l'app Pro Android) ; 2026-10-13 (texte d'accès amendé, verrou de suppression du compte démo) ; **2026-11-14 (B0.19) : l'URL de suppression devient `https://myweli.com/pro/suppression-compte`, en ligne et lue ce jour-là (§4) ; rien n'est encore saisi dans la console, c'est l'étape 7 d'android-play-release.** |
| **Portée** | **MyWeli Pro** (`com.myweli.pro`) maintenant. MyWeli (`com.myweli.app`) au §8, à ré-auditer avant sa soumission. |
| **Source de vérité** | La politique de confidentialité publiée (`/politique-confidentialite`) et le binaire — un formulaire qui les contredit est un rejet ET une exposition légale (LAUNCH.md §6.3) |
| **Règle** | Chaque réponse ci-dessous est dérivée du code, du binaire ou de la politique, jamais inventée. En cas de doute en saisissant : STOP, on vérifie. |
| **Garde-fous** | `mobile/test/infra/play_store_forms_test.dart` (longueurs du §1 contre les limites de Play ; le texte de connexion du §2 sous les 500 caractères que compte la console, et ses libellés contre l'écran de connexion Pro) · `mobile/test/infra/app_review_notes_test.dart` (la phrase du compte démo, le verrou de suppression) · le même test, §1 : la seule phrase qui diffère de l'App Store (décision 121) ; §2 : la consigne « do not create a salon » ; §6 : les libellés cités aux testeurs (écran de connexion Pro, carte d'invitation, écrans d'inscription Android), dans les deux guides, et la version d'Android, les jours d'invitation et d'essai, les places, lus dans le code · `web/tests/pro-account-deletion-page.test.tsx` et `web/tests/e2e/pro-account-deletion.spec.ts` (la page de l'URL de suppression du §4) |

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
      l'app renvoie. *(Note du 2026-11-19, sans réécrire ce relevé : le
      compte se crée désormais aussi dans l'app Android, avec les mêmes
      méthodes, §4 et §0.3.)*
    - L'URL de suppression : `https://myweli.com/suppression-compte`.
      *(Note du 2026-11-14, sans réécrire ce relevé : cette page est celle des
      comptes clients ; l'URL à saisir pour MyWeli Pro est désormais
      `https://myweli.com/pro/suppression-compte` (B0.19, §4), à l'étape 7.)*
      *(Saisie le 2026-11-19, §0.4.)*
    - Aperçu relu : « Aucune donnée partagée avec des tiers ».
- **Paramètres de la fiche** : catégorie **Professionnel**, e-mail
  `support@myweli.com`, site `https://myweli.com`, pas de téléphone.
  - Ces coordonnées sont « publiées » aussitôt, sur l'accord du propriétaire.
  - Le site, d'abord enregistré en `http://` (le « https:// » du champ était
    une indication, pas un préfixe), a été corrigé et relu.
- **Fiche par défaut (fr-FR) : enregistrée, avec ses images.** La console
  l'affiche « Prête à être envoyée pour examen ».
  - **Textes** : nom, description courte, description complète (29/30, 70/80,
    996/4000). Chacun est identique au §1, empreinte SHA-256 comparée dans la
    page. *(2026-11-11 : la description complète du §1 a changé, décision 113 ;
    celle de la console est encore l'ancienne.)* *(Remplacée dans la console
    le 2026-11-19, §0.4.)*
  - **Images** : l'icône, la bannière et les 8 captures du §1.2–§1.3,
    importées par Claude dans Chrome (le volet navigateur ne peut pas joindre
    de fichier), sur la demande du propriétaire.
    - Les 8 captures arrivent dans l'ordre où l'import se termine. Elles ont
      été remises dans l'ordre 01→08 à la souris, l'ordre relu après chaque
      déplacement.
    - **Relu après rechargement de la page** : icône 1/1, bannière 1/1,
      captures 8/8, dans l'ordre 01→08. Les originaux conservés par Google ont
      la même taille et la même empreinte SHA-256 que les fichiers de
      `build/play-store/pro/`, pour chacun des 10.
  - **« Déclaration relative aux éléments d'IA »** : une question nouvelle à
    l'étape « Avis », avant l'enregistrement. Réponse : **« Ne pas signaler
    les éléments »** (propriétaire, décision 59).
    - Les cadres sont composés par nos scripts à partir de vraies captures de
      l'app, sans IA.
    - La photo du salon (capture 02, « trouvée en ligne », libre de droits
      selon le propriétaire) et l'icône ne viennent pas d'un générateur
      d'images IA, d'après le propriétaire. Ce n'est pas vérifiable d'ici.
- **Rien n'est envoyé pour examen.** Après l'enregistrement, la console
  propose « Vue d'ensemble de la publication » ; réponse : « Pas maintenant ».
  - Sur cette page, « Envoyer l'appli pour examen » est verrouillé tant que
    le tableau de bord n'est pas fini.
  - « Publication gérée » est désactivée : une fois une modification
    approuvée par Google, elle est publiée sans autre clic.
- **Ce que le tableau de bord demande encore** (lu le 2026-10-28) : la
  section de configuration a disparu, il ne reste que le test fermé (§6).
  1. Choisir les pays et les régions du test fermé.
  2. Choisir les testeurs.
  3. Créer une version : l'AAB signé.
  4. Ensuite seulement, deux étapes encore verrouillées : prévisualiser et
     confirmer la version, puis l'envoyer à Google pour examen.
  5. Puis la demande d'accès à la production, après les 14 jours.

## 0.2 · Le 2026-11-11 — après la sortie iOS

Les décisions 110 à 115 du propriétaire (« Valider tel quel »), et ce qui était
devenu faux depuis le 2026-10-28 :

- **La description (§1)** est maintenant celle de l'App Store, mot pour mot
  (décision 113), et le test n'admet plus d'écart. La console garde l'ancienne
  jusqu'à l'étape 7 d'[android-play-release.md](android-play-release.md).
- **Le code démo (§2)** : Apple a rendu sa décision ; la règle « aucune
  rotation avant la décision d'Apple » est tombée. Le même code sert aux deux
  stores.
- **Deux déclarations nouvelles (§5)** : la localisation précise, obligatoire
  le 2027-01-27, et le statut de professionnel, avant le 2027-02-01. « Aucune
  déclaration de permission n'est due » était vrai le 2026-10-28 ; plus depuis
  l'annonce de Google du 2026-10-29.
- **Le compte d'organisation (§6)** : un compte personnel peut être converti.
  Ce document disait le contraire.
- **Les iPhone (§6.1)** : MyWeli Pro est sur l'App Store depuis le 2026-11-10.
- **La clé d'importation et l'empreinte de Play (§6.2)** existent depuis le
  2026-08-26 ; les étapes 3 et 4 deviennent des vérifications.
- **Les pays (§6.2)** : le test fermé en Côte d'Ivoire et dans les pays des
  testeurs ; la production dans tous les pays possibles (décision 114).
- **L'audit du binaire (§0)** date du 2026-10-28, sur Flutter 3.44.9. Il est
  refait sur l'AAB réel (étape 5 du même document).

## 0.3 · Le 2026-11-19 — l'inscription revient dans l'app Android

L'app Pro Android crée de nouveau le compte d'un salon (B0.17, décisions 116
à 123, [pro-android-signup.md](pro-android-signup.md)) ; l'app iPhone reste en
connexion seule. Ce qui change ici (la PR C de cette spec, §9.2 là-bas) :

- **La description (§1)** prend une phrase propre à Play (décision 121).
  L'App Store garde le texte qu'Apple a approuvé, et le test admet cette seule
  différence.
- **Les instructions des relecteurs (§2)** leur demandent d'utiliser le
  compte démo et de ne pas créer de salon (R6).
- **La sécurité des données (§4)** : le compte se crée dans l'app Android et
  sur le Web ; le téléphone et l'adresse deviennent obligatoires, comme
  l'inscription les demande.
- **Le test fermé (§6)** : les salons s'inscrivent dans l'app ; des testeurs
  payés de Testers Community (décision 117), dans tous les pays disponibles ;
  le salon d'essai des proches devient facultatif ; le guide a une version
  anglaise.

**La console garde les anciennes réponses** jusqu'à l'étape 7
d'[android-play-release.md](android-play-release.md), sur le oui du
propriétaire. *(Saisies le 2026-11-19, §0.4.)*

## 0.4 · Dans la console, le 2026-11-19 — l'étape 7

Saisi dans le volet navigateur, le propriétaire connecté, sur son oui pour
chaque formulaire. Chaque formulaire est relu après rechargement de la page.
Avant la première saisie, le propriétaire a dit avoir relu les deux pages
d'aide de Play que demande l'étape 7 (la politique des paiements et l'aide
10281818).

- **La fiche (fr-FR), description complète** : le texte du §1, 1 100
  caractères (996 avant), SHA-256 `f06e5d7e…35335bdf`, identique au §1 de
  `main` (`f17270ea`). La « Déclaration relative aux éléments d'IA », reposée
  à l'enregistrement : « Ne pas signaler les éléments » (décision 59).
- **Informations de connexion** : le texte du §2, 478 caractères sur 500 (463
  avant), SHA-256 `93a54201…c4cbcdd0`, identique au §2. L'identifiant, le mot
  de passe (jamais lu), la case « accès complet » et les tests automatiques ne
  changent pas.
- **Sécurité des données** : quatre changements, chacun relu dans sa fenêtre :
  1. l'URL de suppression devient `https://myweli.com/pro/suppression-compte` ;
  2. « Adresse » devient obligatoire ;
  3. « Numéro de téléphone » devient obligatoire et gagne « Gestion des
     comptes » ;
  4. « Historique des recherches » gagne « Prévention des fraudes, sécurité et
     conformité », et reste facultatif.
  - **L'aperçu de Play, relu ligne à ligne** : les 15 types du §4, « Aucune
    donnée partagée avec des tiers », le chiffrement en transit, la
    suppression possible.
  - **Relu à côté des deux pages en ligne**, `/politique-confidentialite` et
    `/pro/suppression-compte` (200 toutes deux, mises à jour le 14 novembre) :
    les trois racontent la même histoire. Rien n'est vendu ni loué, et
    aucun tiers ne reçoit de données pour ses propres fins ; le téléphone
    sert à créer et sécuriser le compte ; les recherches faites dans « Clients » restent
    dans le journal de l'équipe, sans durée fixée ; la page de suppression
    nomme « MyWeli Pro — Gestion de salon », le nom de la fiche (§7).
  - « Contenu de l'application » affiche la Sécurité des données « Prête à
    être envoyée pour examen », modifiée le 19 nov. 2026.
- **L'e-mail public du développeur devient `support@myweli.com`**
  (décision 149). Il se règle dans Détails du compte → « Coordonnées » →
  « Adresse e-mail du développeur » : c'est la seule coordonnée de cet onglet
  que les utilisateurs voient, le nom, l'e-mail et le téléphone de contact
  restant privés. Google a envoyé un code à cette adresse, saisi par le
  propriétaire. Relu sur une page rechargée : `support@myweli.com`,
  « Adresse e-mail validée ». Avant l'enregistrement, la même lecture montrait
  encore l'ancienne adresse.
- **Le statut de professionnel du compte : « Professionnel »** (décision 115).
  - Le parcours : Détails du compte → « À propos de vous » → « Déclarez votre
    statut de professionnel » → « Il s'agit d'un compte professionnel » → un
    écran qui fait valider par SMS le téléphone à afficher (le numéro et le
    code, saisis par le propriétaire) → l'écran de relecture.
  - **L'écran de relecture** : le statut, le nom légal et l'adresse du profil
    de paiement Google, `support@myweli.com`, le téléphone (+225). Deux cases,
    cochées par le propriétaire : l'autorisation d'afficher ces informations
    (avec le retrait possible du profil et des apps si Google ne peut pas le
    valider) et l'engagement à ne proposer que des produits ou services
    conformes aux lois locales. **Aucun document n'est demandé**, ni registre
    du commerce ni pièce : l'aide 17594752 dit cette déclaration distincte de
    la vérification d'identité du compte.
  - « Enregistrer » : « Statut de professionnel enregistré ». Relu après
    rechargement : « Professionnel », et le bandeau « Déclarez votre statut »
    a disparu.
  - **Ce qui sera affiché**, selon cet écran : partout, sous « Assistance
    pour l'appli », le nom légal, l'e-mail, l'adresse et le téléphone ; dans
    l'EEE et au Royaume-Uni seulement, sous « À propos du fournisseur », le
    statut et l'engagement. À partir du 2027-03-01, selon l'aide 17594752.
- **Le statut de professionnel de chaque app** (« Contenu de l'application »
  → « Statut de professionnel et conditions d'utilisation au niveau de
  l'appli »), **pour MyWeli Pro et pour MyWeli** (décision 150) : « Oui, mon
  statut de professionnel s'applique à cette appli », déjà choisi par héritage
  du compte, et les conditions d'utilisation `https://myweli.com/cgu`. Chacun
  relu après rechargement.
  - `/cgu` est en ligne (200, mise à jour le 14 novembre) et a une section
    « 7. Pour les professionnels ». L'écran d'inscription Android de l'app Pro
    y renvoie (`LegalConsentText`, `AppConfig.termsUrl`). La page nomme
    « l'application et le site MyWeli », jamais « MyWeli Pro ».
- **La localisation précise : toujours aucun formulaire** dans le « Contenu
  de l'application » de MyWeli Pro, avec le build 788 sur la piste interne
  (§5).
- **Rien n'est envoyé pour examen.** Après chaque enregistrement, la console
  propose « Vue d'ensemble de la publication » ; réponse : « Pas maintenant ».
  - MyWeli Pro : « Envoyer 9 modifications pour examen », les 8 d'avant et le
    statut de professionnel de l'app ; non cliqué. Le statut de chaque app
    part donc avec la première demande d'examen (étape 8).
  - MyWeli : deux modifications attendent, la fiche et le statut de
    professionnel ; « Envoyer l'appli pour examen » reste verrouillé par son
    tableau de bord.
- **Pas encore lu** : « Validation des développeurs Android », listé dans
  « Gérer le compte ».

## 0.5 · Dans la console, le 2026-11-19 et le 20 — l'étape 8, le test fermé

Dans le volet navigateur, sur le oui du propriétaire pour chaque action ;
chaque formulaire relu après rechargement de la page.

- **La piste « Tests fermés - Alpha »** existait déjà : inactive, sans
  version, sans pays, sans testeurs.
- **Pays/Régions** : les 178 lignes, soit 177 pays (Côte d'Ivoire comprise)
  et « Reste du monde » (décision 117). Relu : « Ciblé(s) (178) ».
- **Testeurs** :
  - **les deux modes s'excluent** : « Listes de diffusion » ou « Groupes ».
    D'abord la liste « OG TESTER » (le propriétaire seul), en attente ; puis
    « Groupes » → `testers-community@googlegroups.com`, comme le demande la
    page de Testers Community que le propriétaire a collée (« under Google
    Groups on the Testers tab, not Email lists »). L'adresse du §6.1 est donc
    confirmée ;
  - **commentaires** : `support@myweli.com` (décision 61) ;
  - **les liens de participation** : sur Android
    `https://play.google.com/store/apps/details?id=com.myweli.pro`, sur le Web
    `https://play.google.com/apps/testing/com.myweli.pro`. C'est lui qui
    remplace `[LIEN DU TEST]` (§6.2, §6.5) ;
  - **changer les testeurs est une modification à envoyer à Google**, comme
    le reste. Un groupe à nous, pour des salons ou des proches, s'ajoute dans
    le même champ « Groupes », puis part à l'examen.
- **Testers Community** : commandé par le propriétaire (l'offre Pro, 20 $),
  et leur formulaire envoyé par lui avant l'envoi à l'examen (rapporté par
  le propriétaire ; le lien qu'il y a mis n'est pas relu ici).
- **La version** : la 788 (0.0.2), promue depuis le test interne
  (« Promouvoir la release » → « Tests fermés » → « Tests fermés - Alpha » ;
  ce sous-menu ne s'ouvre qu'avec la flèche droite du clavier). Le même app
  bundle : API 24 et plus, cible 36, 3 ABI ; nom « 788 (0.0.2) » ; pas de
  notes de version, comme en test interne ; 12,4 Mo à installer ; aucune
  erreur à l'écran de vérification de la version.
- **La vérification rapide de Play a bloqué l'envoi** : « Les déclarations de
  fonctionnalités matérielles requises limitent la disponibilité de votre
  appli », pour `android.hardware.screen.portrait` (le verrou portrait de
  #682). Sur la décision du propriétaire (décision 151), le problème est
  ignoré avec la seule raison « La résolution de ce problème est déjà
  prévue ». Corrigé depuis dans #815, pour le prochain AAB.
- **« Envoyer 16 modifications pour examen »** : les 9 de l'étape 7, les
  réglages de la piste et la version. La console a demandé confirmation
  (« Habituellement, l'examen est effectué sous sept jours »).
  - Les vérifications rapides sont passées, puis « Vos modifications sont en
    cours d'examen ».
  - **Lu le 2026-11-20 à 00:14 UTC : publié.** La vue d'ensemble dit
    « Dernière publication le 19 novembre 2026 », sans modification en
    attente. La piste est « Actif », 178 pays/régions, et la 788 « Disponible
    pour certains testeurs », sortie le « 19 nov. 23:16 ». Le bandeau du nom
    temporaire (« com.myweli.pro (unreviewed) ») a disparu.
  - « Publication gérée » est désactivée : l'approbation a publié aussitôt.
- **Le gel de la décision 140** : `/pro/suppression-compte` n'a pas changé
  pendant l'examen ; aucune PR ouverte ne touchait le site.
- **La suite, l'étape 9** : 12 testeurs inscrits sans interruption pendant
  14 jours. L'aide 14151465, relue le 2026-11-20, vise les comptes
  **personnels** créés après le 13 novembre 2023. Le statut de professionnel
  n'y change rien : le type de compte reste « Personnel » (relu le même
  jour).

## 1 · Fiche du Play Store (Store listing) — MyWeli Pro

Limites de Play (aide Play, « Add product details ») : nom 30 caractères,
description courte 80, description complète 4 000. Le test les relit.

- **Nom de l'app** : `MyWeli Pro — Gestion de salon` (29 caractères ; le nom
  de l'App Store, §4 d'[app-store-forms.md](app-store-forms.md))
- **Description courte** :
  `L'agenda, la clientèle et les réservations de votre salon, en une app.`
- **Description complète** — la même que sur l'App Store, mot pour mot, en
  texte brut (Play n'interprète pas le Markdown : un `**` collé s'afficherait
  tel quel). *2026-11-11, décision 113 : Play prend le texte publié sur l'App
  Store, avec ses quatre changements du 2026-11-03 (décisions 74 et 79 :
  « sur myweli.com » retiré, la phrase sur les salons qui ont déjà un compte,
  « semaine » et « à domicile, » retirés ;
  [app-review-round-2.md](app-review-round-2.md) §7). La console garde
  l'ancien texte (996 caractères) jusqu'à l'étape 7
  d'[android-play-release.md](android-play-release.md). Le test exige
  l'égalité, sans écart.* *2026-11-19, décision 121 : une phrase diffère.
  Sur l'App Store, « MyWeli Pro s’adresse aux salons qui ont déjà un compte MyWeli et à leur équipe. » ; sur
  Play, où l'app Android crée le compte d'un salon : « MyWeli Pro s’adresse aux salons et à leur équipe : créez le compte de votre salon dans l’application, ou rejoignez l’équipe qui vous invite. » Le test
  admet cette seule différence.* :

**Description complète** (coller tel quel) :

```text
L'outil de gestion des salons de beauté de Côte d'Ivoire : recevez des réservations en ligne et pilotez votre activité au quotidien. MyWeli Pro s’adresse aux salons et à leur équipe : créez le compte de votre salon dans l’application, ou rejoignez l’équipe qui vous invite.

VOTRE AGENDA, TENU TOUT SEUL
Les clients réservent sur vos créneaux réels ; vous ajoutez les rendez-vous pris au téléphone ou au comptoir en quelques gestes. Vue journée et par membre d'équipe.

VOTRE VITRINE EN LIGNE
Photos, avant/après, logo, prestations et tarifs, horaires avec modèles prêts à l'emploi : votre page publique se remplit depuis l'app.

VOTRE CLIENTÈLE, ENREGISTRÉE D'ELLE-MÊME
Chaque réservation crée ou retrouve la fiche client — historique de visites, notes, étiquettes.

VOS ACOMPTES, SANS INTERMÉDIAIRE
Le client paie l'acompte sur VOTRE Mobile Money et joint sa preuve ; vous confirmez. MyWeli ne touche jamais vos fonds.

VOTRE ÉQUIPE
Invitez manager, réception et collaborateurs, chacun avec les accès de son rôle.

Conçu pour les réalités d'ici : FCFA, communes, réseaux lents et petits téléphones.
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

  C'est **le même code que pour la revue Apple**. *2026-11-11 : Apple a rendu
  sa décision sur la 0.0.1 ; la règle « aucune rotation avant la décision »
  (B0.1) vaut de nouveau pendant chaque revue, chez Apple comme chez Google.
  Une rotation met à jour les deux consoles le même jour.*
- **Ce que Google exige :** des identifiants qui marchent toujours, de
  partout, réutilisables, sans code à usage unique, en anglais. Le compte démo
  a un code **fixe qui n'expire pas** : c'est exactement ce que Google demande.

- **Nom** de l'ensemble (60 caractères au plus) : `Demo salon (shared review account)`

**Instructions supplémentaires** (coller tel quel — en anglais, comme Google le demande ; dans « Toute autre information requise pour accéder à votre appli », **500 caractères au plus**, retours à la ligne compris — celui-ci en fait 478 ; 463 avant le 2026-11-19) :

> Please use this demo account; do not create a salon. The 6-digit code is FIXED and never expires: it is the password above.
> 1. On « Espace Pro », type revue@myweli.test in « Votre e-mail ».
> 2. Tap « Continuer avec e-mail ». No e-mail is sent.
> 3. Type the code in « Code à 6 chiffres », tap « Se connecter ».
> Three actions are disabled on this shared demo salon and say « Compte de démonstration — cette action est désactivée. »: publishing, inviting staff, deleting the account.

Une ligne de citation = une ligne collée. Le reste de ce que disent les notes
App Store (paiements, pièces d'identité, modération, position) ne tient pas
dans 500 caractères. Il n'est pas nécessaire pour se connecter, et le reste du
formulaire le dit.

- **Pourquoi « do not create a salon »** (R6, 2026-11-19) : sur Android,
  l'app crée de nouveau le compte d'un salon ([pro-android-signup.md](pro-android-signup.md)).
  Un salon créé par un relecteur serait une vraie ligne en production. Il ne
  deviendrait jamais public, parce que MyWeli valide chaque salon avant sa
  mise en ligne (B0.18), et ses lignes ne sont supprimées que sur le mot du
  propriétaire. La première ligne a été raccourcie pour tenir dans les 500
  caractères : les étapes 1 à 3 disent déjà que la connexion est un e-mail
  puis un code.
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
  - URL : `https://myweli.com/pro/suppression-compte` (B0.19, décisions 137
    à 140), la page d'un compte MyWeli Pro : supprimer son compte sur le web,
    sans l'app, ce qui est supprimé, ce que devient le salon, ce qui est
    conservé, et support@myweli.com pour qui ne peut plus se connecter. Lue en
    ligne le 2026-11-14 : 200, indexée. ~~`https://myweli.com/suppression-compte`,
    qui répond 200 et couvre les comptes professionnels (lu le 2026-10-28)~~ :
    elle renvoie au « Mon compte » des clients.
  - Dans l'app : Profil → « Supprimer mon compte ».
- **La création de compte** (*écrite le 2026-11-19*, §0.3) : un compte MyWeli
  Pro se crée **dans l'app Android** (« Créer le compte de mon salon », sous
  « Espace Pro ») **et sur le Web** (`/pro/inscription`), par Google ou par un
  code reçu par e-mail. Les méthodes à cocher ne changent pas : « Nom
  d'utilisateur et autre authentification » et « OAuth » (§0.1). L'app iPhone
  ne crée pas de compte.
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
| Informations personnelles → **Adresse** | Obligatoire | Fonctionnalités de l'appli | l'adresse du salon, demandée à l'inscription (dans l'app Android et sur le Web) et modifiable dans « Profil du salon », publiée sur sa page — *Facultatif jusqu'au 2026-11-19* |
| Informations personnelles → **Numéro de téléphone** | Obligatoire | Fonctionnalités de l'appli · Gestion du compte | « Téléphone du salon », demandé à l'inscription (dans l'app Android et sur le Web) ; WhatsApp ; les téléphones des clients saisis par le salon — *Facultatif, sans « Gestion du compte », jusqu'au 2026-11-19* |
| Informations personnelles → **Autres infos** | Facultatif | Fonctionnalités de l'appli · Prévention des fraudes, sécurité et conformité | pièces KYC — identité, photo du visage, RCCM, justificatif d'adresse : stockage privé, jamais publiées, lues par un administrateur |
| Informations financières → **Autres infos financières** | Facultatif | Fonctionnalités de l'appli | le numéro **Mobile Money de réception** des acomptes, publié sur la page du salon |
| Position → **Position exacte** | Facultatif | Fonctionnalités de l'appli | le point du salon (« Utiliser ma position ») — latitude et longitude envoyées et **publiques** |
| Photos et vidéos → **Photos** | Facultatif | Fonctionnalités de l'appli · Prévention des fraudes, sécurité et conformité | galerie, logo, avant/après, photos d'équipe (publiques) ; images KYC (privées) |
| Fichiers et documents → **Fichiers et documents** | Facultatif | Fonctionnalités de l'appli · Prévention des fraudes, sécurité et conformité | les pièces KYC envoyées en PDF (`pro_kyc_screen.dart` accepte jpg, png, webp et **pdf**) — *ajouté le 2026-10-28* |
| Activité dans les applis → **Historique des recherches via une appli** | Facultatif | Fonctionnalités de l'appli · Prévention des fraudes, sécurité et conformité | le texte cherché dans « Clients » (`?query=`) : gardé 30 jours dans les journaux de requêtes de Google Cloud, **et** enregistré dans le journal des actions de l'équipe du salon (`provider_audit_log`, action `clients.list`, avec le filtre d'étiquette et la page), qui sert à savoir qui a consulté quel client (T39, T46), **sans durée fixée à ce jour**, y compris après la suppression du compte (décision 138 ; une purge sera décidée par B0.24) — *ajouté le 2026-10-28 ; corrigé le 2026-11-14 (B0.23, décisions 137 et 143)* |
| Activité dans les applis → **Autre contenu généré par l'utilisateur** | Facultatif | Fonctionnalités de l'appli | prestations et tarifs, descriptions, horaires, notes clients, notes de réservation |
| Infos et performances des applis → **Journaux de plantage** | Obligatoire | **Analyses** | Sentry — utilisateur, fil d'Ariane, requête et extras retirés avant envoi (`beforeSend`) |
| Infos et performances des applis → **Diagnostics** | Obligatoire | **Analyses** | les blocages (app hangs) que Sentry envoie quand il en survient |
| Appareil ou autres ID → **Appareil ou autres ID** | Obligatoire | Fonctionnalités de l'appli | l'ID d'installation Firebase et le jeton FCM (`device_tokens`) — le SDK FCM crée l'ID d'installation à l'initialisation |

> **2026-11-13 — la ligne « Historique des recherches » était incomplète**
> (décisions 137 et 143). Le texte cherché dans « Clients » est aussi
> enregistré dans `provider_audit_log` (action `clients.list`), le journal
> d'accès aux fiches clients (T39, T46), lié au compte qui cherche, **sans
> durée fixée**, y compris après la suppression du compte. **2026-11-14 : la
> ligne ci-dessus est réécrite par la PR de B0.23**, finalité « Prévention des
> fraudes, sécurité et conformité » comprise
> ([web-privacy-pro-deletion.md](web-privacy-pro-deletion.md) §5). **La
> console garde l'ancienne réponse** : elle gagne cette finalité à l'étape 7,
> sur le oui du propriétaire. L'étiquette App Store déclare la même donnée
> (décision 144, app-store-forms §7.3). *(2026-11-19 : la console a cette
> finalité, avec les trois autres changements de ce jour, §0.4.)*

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
propre définition, et c'est voulu. *2026-11-19 : une seule différence de fond,
voulue elle aussi :* l'app Android crée le compte d'un salon, l'app iPhone non
(décision 116). Le téléphone et l'adresse sont donc demandés **dans l'app**
sur Android seulement. La politique de confidentialité décrit ces données
(la fiche du salon : nom, adresse, téléphone…) sans dire où le compte se
crée : elle reste vraie (relue dans le code de la page le 2026-11-19).

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
| **Localisation précise** (`ACCESS_FINE_LOCATION`) — *nouvelle, obligatoire le 2027-01-27 (annonce de Google du 2026-10-29)* | **à remplir** à l'étape 7 d'[android-play-release.md](android-play-release.md), une fois le formulaire lu. La justification : « Utiliser ma position », dans « Profil du salon », est une action ponctuelle lancée par l'utilisateur ; le point devient la position publique du salon sur sa page et sa carte ; une position approximative le placerait à des kilomètres ; le bouton de localisation d'Android n'existe qu'à partir d'Android 17 | Google : l'app qui garde `ACCESS_FINE_LOCATION` doit justifier « why coarse location or the location button is insufficient » ; nous ciblons l'API 36. L'emplacement du formulaire et ses questions ne sont pas encore lus (même document, §7.1). *2026-11-19 : toujours aucun formulaire dans la console (§0.4).* |
| **Statut de professionnel** (le compte, puis chaque app) — *avant le 2027-02-01* | **Professionnel** (décision 115), **confirmé par le propriétaire le 2026-11-11** (« Rester professionnel »), en sachant que, pour un compte personnel, Google affiche alors son numéro de téléphone et son adresse, partout dans le monde, à partir du 2027-03-01. **Déclaré le 2026-11-19 (§0.4)** : le compte, puis MyWeli Pro et MyWeli (décision 150), avec les conditions d'utilisation `https://myweli.com/cgu` ; l'e-mail affiché est `support@myweli.com` (décision 149) | aide Google 17594752 ; même document, §3.6 et §7.2. Sans déclaration : blocage des mises à jour et retrait du Play Store dans le monde entier |

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
3. **Les 12 testeurs.** Ce sont 12 comptes Google qui installent et gardent
   l'app 14 jours. *Depuis le 2026-11-19 (décision 117, §0.3) :* des testeurs
   payés de Testers Community, et des salons si tu en trouves. Un salon crée
   son compte **dans l'app** sur Android, ou sur myweli.com ; un membre
   d'équipe arrive par son invitation. Le compte démo reste réservé aux
   relecteurs. Où les trouver, et ce qu'on leur envoie : §6.1 à §6.5.

**Une seule façon d'y échapper : un compte développeur d'organisation.** La
règle ne vise que les comptes personnels (aide 14151465). *Corrigé le
2026-11-11 :* un compte personnel **peut** être converti en compte
d'organisation (aide Google 16260648, relevée le 2026-11-01) : site Web
vérifié de l'organisation, numéro D-U-N-S, profil de paiement
d'organisation, parfois des documents. Aucune page de Google ne dit que la
conversion dispense une app déjà créée du test des 12 testeurs. Et il faut
une société immatriculée, ce qui vient après le lancement. Le test fermé se
fait donc maintenant. Le passage à un compte d'organisation reste à
envisager avant MyWeli (client) : la page de Google parle d'un test « pour
leur appli », ce qui laisse penser qu'il en faudra un second pour elle.

### 6.1 Qui recruter (décisions 60 à 62, 2026-10-28)

- **Uniquement des téléphones Android.** L'app s'installe depuis le Play
  Store, sur Android 7.0 ou plus récent (`minSdkVersion` 24, lu dans l'APK de
  version), avec un compte Google.
  - Un utilisateur d'iPhone peut s'inscrire au test sur le Web, mais ne pourra
    jamais ouvrir l'app. Or Google demande, avant la production, si les
    testeurs ont utilisé l'app.
  - Les salons sur iPhone installent MyWeli Pro depuis l'App Store, où elle
    est publiée depuis le 2026-11-10. *(Ce point disait « TestFlight »
    jusqu'au 2026-11-11.)*
- **Viser 15 à 20 personnes.** Au moment de la demande d'accès à la
  production, 12 doivent être inscrites depuis 14 jours sans interruption.
  Celle qui quitte le test ne compte plus.
- **D'abord des salons**, les futurs clients de MyWeli Pro.
  - Ils créent leur compte dans l'app (« Créer le compte de mon salon », sous
    « Espace Pro ») ou sur `myweli.com/pro/inscription`, et utilisent l'app
    pour leur vrai salon. *(Jusqu'au 2026-11-19 : sur le site seulement.)*
  - C'est l'usage que Google demande de décrire : toutes les fonctionnalités
    utilisées, un usage qui ressemble à celui de vrais utilisateurs, un résumé
    des retours et la façon de les recueillir (aide 14151465).
- **Puis des proches, dans l'équipe d'un salon d'essai** (décision 60),
  *facultatif depuis la décision 117*, pas dans le salon démo :
  - le salon démo est celui où travaillent les relecteurs d'Apple et de
    Google. Ce que des proches y changeraient resterait sous leurs yeux
    jusqu'à la réinitialisation des 7 jours ;
  - tous partageraient un seul compte, donc ses plafonds horaires (rendez-vous,
    clients, catalogue), au risque de bloquer un relecteur ;
  - et l'invitation d'équipe y est désactivée.
- ~~**Pas de testeurs achetés.** Des installations payées ne répondent pas aux
  questions de Google sur l'usage. Les groupes d'échange de tests (on teste
  leurs apps, ils testent la nôtre) peuvent compléter le nombre, sans
  remplacer les salons.~~ **Des testeurs payés** (décision 117, 2026-11-12) :
  Testers Community. Ses testeurs rejoignent la piste par son groupe Google,
  `testers-community@googlegroups.com` *(confirmée le 2026-11-19 par leur
  page, §0.5)*, et vivent dans plusieurs pays. Ils
  reçoivent le guide en anglais (§6.5). **Le risque accepté :** les questions
  de Google sur l'usage réel, avant la production, seront peut-être plus
  difficiles à remplir avec eux (NON VÉRIFIÉ).
- **Le salon d'un testeur payé reste privé.** Il crée un vrai salon, en
  production, et peut demander sa mise en ligne. MyWeli ne le valide pas : il
  le refuse avec « Salon de test » (B0.18), et le salon ne devient jamais
  public. Il ne reçoit pas non plus les 90 jours d'essai, qui partent de la
  validation (décision 120). Ses lignes restent en brouillon ; rien n'est
  supprimé sans le mot du propriétaire. Pour les reconnaître, le guide anglais
  leur demande de commencer le nom du salon par « TEST » (choix du
  propriétaire, 2026-11-19, en approuvant le plan de la PR C).
- **Les retours** (décision 61) : par e-mail à `support@myweli.com`, ou en
  avis privé sur la page Play de l'app (la console les montre sous
  « Commentaires des testeurs »).
- **Ce qu'on promet aux salons** (décision 62) : l'accès avant la sortie, et
  les 90 jours d'essai gratuit que tout salon reçoit. Aucun prix, aucune autre
  promesse. *2026-11-19 :* l'essai démarre quand MyWeli valide le salon
  (décision 120), et le message le dit.

### 6.2 Avant le premier message — à faire par le propriétaire, dans l'ordre

Les libellés de Google Groups et des pages de test de Play ne sont pas relus
d'ici : ils sont décrits, pas cités.

1. **Le groupe Google.** Sur groups.google.com, un groupe (par exemple
   `myweli-pro-testeurs`) que tout le monde peut rejoindre sans validation.
   - Son adresse `…@googlegroups.com` va dans la liste des testeurs de la
     piste fermée.
   - Son lien `https://groups.google.com/g/…` remplace `[LIEN DU GROUPE]`
     dans le guide (§6.5).
   - *2026-11-19 (décision 117) :* ajouter aussi, dans la liste des testeurs
     de la piste fermée, le groupe de Testers Community,
     `testers-community@googlegroups.com`. Le nôtre reste pour les salons et
     les proches ; les testeurs payés ne le rejoignent pas.
2. **La piste de test fermé** (tableau de bord → « Tests fermés »).
   - **Pays** : par défaut, la piste reprend ceux de la production, qui n'en a
     aucun. Ajouter la Côte d'Ivoire, et les pays où vivent des testeurs
     ([mobile-external-testing.md](mobile-external-testing.md) §4.1). La
     production, elle, ira dans tous les pays possibles (décision 114), après
     la déclaration de statut de professionnel (§5). *2026-11-19 (décision
     117 (1)) : la piste fermée aussi, dans tous les pays disponibles. Un
     testeur hors de ses pays ne peut pas installer l'app, et ceux de Testers
     Community vivent dans plusieurs pays.*
   - **Testeurs** : le groupe Google.
   - **Commentaires** : `support@myweli.com`, si la console demande une
     adresse.
   - **Le lien d'inscription** que la console affiche (de la forme
     `https://play.google.com/apps/testing/com.myweli.pro`) remplace
     `[LIEN DU TEST]` dans le guide. *(2026-11-19 : c'est exactement ce lien ;
     la piste est configurée et publiée, §0.5.)*
3. **La version.** *2026-11-11 :* la clé d'importation existe depuis le
   2026-08-26 ; sa sauvegarde est vérifiée à l'étape 4
   d'[android-play-release.md](android-play-release.md). L'AAB signé
   (`tool/release_build.sh`, LAUNCH §6.3) passe d'abord par le test interne
   et la vérification sur téléphone (même document, §5). C'est **la même
   version** qui est ensuite promue dans la piste fermée, puis envoyée à
   l'examen de Google.
4. **L'empreinte SHA-1 de Play, avant toute invitation.** *Fait le 2026-08-26 :
   `94be494a…`, lue sur l'APK installé depuis Play
   (`infra/mobile/signing-manifest.json`). C'est désormais une vérification,
   que `release_build.sh` refait avant chaque build.* Play re-signe l'app
   avec sa propre clé. Tant que l'empreinte de cette clé n'est pas enregistrée
   sur le client OAuth Android de `com.myweli.pro`, « Continuer avec Google »
   répond « Connexion Google impossible. » sur l'app installée depuis Play.
   La connexion par e-mail, elle, marche sans
   ([mobile-external-testing.md](mobile-external-testing.md) §5.1).
5. **Le salon d'essai des proches** (décision 60). *Facultatif depuis la
   décision 117 : seulement si des proches testent.*
   - Une adresse e-mail dédiée que vous lisez, pas celle de votre futur vrai
     salon : hors offre Réseau, un compte ne tient qu'un salon.
   - Sur `myweli.com/pro/inscription` : un nom (par exemple Salon d'essai
     MyWeli), un téléphone, une adresse, et l'inscription **par e-mail**
     (« Recevoir un code », puis « S’inscrire »). *Depuis le 2026-11-19, ou
     dans l'app sur Android : « Créer le compte de mon salon », puis
     l'inscription par e-mail.*
   - **C'est aussi l'essai de l'e-mail.** Rien d'ici ne prouve que les codes
     arrivent : la demande répond 202 dans tous les cas, et l'envoi n'est pas
     journalisé (lu le 2026-10-28). Le code doit arriver dans la boîte de
     réception, pas dans les spams
     ([mobile-external-testing.md](mobile-external-testing.md) §5.5).
   - « Abonnement » → Business → « Choisir cette offre » : 90 jours d'essai,
     15 places, vous compris, donc 14 invités au plus. Inviter demande une
     offre active.
   - **Ne jamais le mettre en ligne** : il reste invisible du public.
   - « Équipe » → « + Inviter un membre », rôle **Manager**, une invitation
     par proche, avec l'adresse qu'il vous a donnée. **Seulement une fois la
     version disponible** : une invitation expire au bout de 7 jours.
6. **Le test interne.** L'accueil de la console affiche « Tests internes »
   pour MyWeli Pro. Une personne inscrite au test interne ne peut pas
   rejoindre le test fermé avant de l'avoir quitté : vérifier sa liste.
7. **Envoyer** le message (§6.3 ou §6.4), puis le guide (§6.5).

### 6.3 Message aux salons

WhatsApp ou e-mail, envoyé depuis votre numéro ou votre adresse : votre nom
est déjà visible, le message n'en porte pas.

**Message aux salons** (coller tel quel) :

```text
Bonjour,

Je lance MyWeli Pro, une application pour gérer votre salon : l'agenda et les rendez-vous, la fiche de chaque client, vos prestations et vos tarifs, et votre page de réservation en ligne sur myweli.com.

Avant sa sortie sur le Play Store, je cherche quelques salons pour la tester pendant 2 semaines sur un téléphone Android. Vous l'utiliseriez pour votre vrai salon, et vos remarques m'aideront à l'améliorer.

Ce que vous y gagnez : l'accès avant tout le monde, et les 90 jours d'essai gratuit que reçoit chaque salon, à partir de sa validation par MyWeli.

Je vous envoie juste après le guide : vous installez l'app, puis vous créez le compte de votre salon directement dedans.

Merci !
```

### 6.4 Message aux proches

**Message aux proches** (coller tel quel) :

```text
Salut !

J'ai besoin de ton aide pour lancer MyWeli Pro, mon application de gestion pour les salons de beauté. Pour la publier sur le Play Store, Google demande qu'au moins 12 personnes la testent pendant 14 jours d'affilée.

Il te faut un téléphone Android et un compte Google (Gmail). Tu vas recevoir par e-mail une invitation de MyWeli Pro à rejoindre l'équipe d'un salon d'essai : rien n'y est réel, tu peux tout essayer.

Envoie-moi l'adresse e-mail que tu veux utiliser (ton Gmail, de préférence). Je t'envoie ensuite le guide : quelques minutes pour installer, puis tu ouvres l'app de temps en temps pendant 2 semaines et tu me dis ce qui ne va pas.

Merci mille fois !
```

### 6.5 Le guide du testeur

Le même pour tous, envoyé après le message. Remplacer `[LIEN DU GROUPE]` et
`[LIEN DU TEST]` (§6.2). Chaque libellé entre guillemets est un texte de
l'écran qu'il nomme ; le test le vérifie.

**Guide du testeur** (coller tel quel) :

```text
MyWeli Pro : tester l'app en 5 étapes

Il vous faut un téléphone Android (version 7 ou plus récente) avec le Play Store, et votre compte Google.

1. Rejoignez le groupe des testeurs, avec le compte Google de votre téléphone : [LIEN DU GROUPE]

2. Ensuite seulement, acceptez le test, avec le même compte Google : [LIEN DU TEST]

3. Installez MyWeli Pro depuis la page Play Store indiquée par ce lien. Si l'app n'apparaît pas tout de suite, réessayez un peu plus tard.

4. Ouvrez l'app.
- Votre salon n'a pas encore de compte : sous « Pas encore de compte ? », touchez « Créer le compte de mon salon ». Remplissez « Votre salon », puis « Continuer avec Google », ou « Votre e-mail », « Continuer avec e-mail », le code reçu dans « Code à 6 chiffres », et « Créer mon compte ».
- Votre salon a déjà un compte, créé sur myweli.com : connectez-vous. Avec Google : « Continuer avec Google ». Par e-mail : « Votre e-mail », « Continuer avec e-mail », le code reçu dans « Code à 6 chiffres », puis « Se connecter ».
- Invité(e) dans une équipe : avec l'adresse qui a reçu l'invitation. « Votre e-mail », « Continuer avec e-mail », le code, « Se connecter », puis « Rejoindre ». L'invitation est valable 7 jours.
Pas de code ? Regardez dans les spams, puis touchez « Renvoyer le code ».

5. Utilisez l'app pendant 14 jours : ajoutez des rendez-vous, ouvrez la fiche d'un client, modifiez une prestation ou des horaires. Ne quittez pas le test et gardez l'app jusqu'à la fin.

Une remarque, un bug ? Écrivez à support@myweli.com, ou laissez un avis privé sur la page Play Store de l'app. Merci !
```

*2026-11-19 :* l'étape 4 dit comment créer le compte d'un salon dans l'app
(décision 116) ; la connexion d'un salon déjà inscrit reste la deuxième ligne.

**Le guide en anglais, pour les testeurs payés** (décision 117 (3)). L'app et
le guide français sont en français ; ceux de Testers Community lisent celui-ci.
Les libellés restent en français, entre guillemets, tels qu'à l'écran : le
test les vérifie comme ceux du guide français. Remplacer `[LIEN DU TEST]`
(§6.2) ; ces testeurs n'ont pas de `[LIEN DU GROUPE]`, ils arrivent par le
groupe de Testers Community.

**Guide du testeur, en anglais** (coller tel quel) :

```text
MyWeli Pro: test the app in 5 steps

MyWeli Pro is a management app for beauty salons in Côte d'Ivoire. The app is in French: this guide quotes each button in French, exactly as it appears on screen.

You need an Android phone (version 7 or later) with the Play Store, and your Google account.

1. Accept the test with the Google account on your phone: [LIEN DU TEST]

2. Install MyWeli Pro from the Play Store page that link opens. If the app does not appear yet, try again a little later.

3. Create a test salon in the app. On the first screen, under « Pas encore de compte ? », tap « Créer le compte de mon salon ».
- Start the salon's name with TEST, for example: TEST Salon Awa.
- Fill in « Votre salon ». In « Téléphone du salon », you can pick your country. The commune can stay empty.
- Then tap « Continuer avec Google ». Or type your e-mail in « Votre e-mail », tap « Continuer avec e-mail », type the code you receive in « Code à 6 chiffres », and tap « Créer mon compte ».
No code? Check your spam folder, then tap « Renvoyer le code ».

4. Use the app for 14 days: complete your salon's profile, add services and opening hours, add appointments, open a client's record. Your test salon stays private: MyWeli does not publish test salons.

5. Do not leave the test, and keep the app installed until the end.

Feedback or a bug? Write to support@myweli.com (English is fine), or leave private feedback on the app's Play Store page. Thank you!
```

---

## 7 · Après la saisie

1. Chaque formulaire est relu à l'écran avant d'être enregistré ; à la fin,
   l'aperçu de la Sécurité des données est relu contre la politique.
2. LAUNCH §6.3 : « Data safety form completed » se coche alors, avec la date.
   *(2026-11-19 : le formulaire est rempli et relu (§0.4). La case reste
   ouverte : elle dit aussi « consistent with the iOS privacy answers ». Or
   l'étiquette App Store ne déclare « Search History » qu'après l'étape du
   propriétaire de la décision 144 (app-store-forms §7.3), qu'aucune lecture
   n'a encore constatée.)*
3. **La page de suppression de compte doit nommer l'app ou le développeur
   exactement comme la fiche** (aide Play 13327111). Elle dit « MyWeli » et
   couvre les professionnels. Le nom de développeur du compte Play est à
   comparer pendant la saisie. *(2026-11-19 : l'URL saisie est désormais
   `/pro/suppression-compte`, qui nomme « MyWeli Pro — Gestion de salon »,
   le nom de la fiche mot pour mot (§0.4).)*

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
