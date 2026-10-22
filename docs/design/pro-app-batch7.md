# L'app Pro, lot 7 : contraste, textes à 200 %, états vides, vérité et parité — spec

| | |
|---|---|
| **Statut** | **PR A construite le 2026-10-22** sur `fix/pro-app-batch7-truth` (#682 — B7.3, B7.5, B7.7, B7.9, B7.11, B7.14 — §9) ; PR B et C à suivre. **Validé le 2026-10-22** — relu sur main (`fa8910ed`). Q1 (décision 23) : **la carte sur « Accueil » et la « Journée »** ; Q2 (décision 24) : **facultatif tant qu'aucun choix n'est enregistré** ; Q3 (décision 26) : **portrait sur Android et iPhone, l'iPad inchangé** ; Q4 (décision 25) : **le bouton flottant « Nouveau »** ; Q5 : **selon « le compte possède un salon »** ; Q6 : **le reste tel qu'écrit** |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-22 |
| **PRD ref / phase** | App Pro (V1) — parité avec le web Pro · SYSTEM.md §13 (contraste, 200 %, sémantique), §12 (les quatre états), §15 (retours), §17 (les mots), §21 (le registre) |
| **Module** | `mobile/` (app Pro, app client pour B7.11, console admin pour B7.13) ; `web/` pour B7.3 et B7.7 — **aucun changement serveur ni de contrat** |
| **Origine** | [BACKLOG.md](../BACKLOG.md) lot 7 : B7.1–B7.14 (décisions 23–26) |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-web-guardrails ✓ |

## 1. Le constat — relu sur le vrai chemin de code (main `fa8910ed`)

Les quatorze points sont **réels**. Six ont besoin d'une correction par
rapport au BACKLOG :
- **B7.2** : le titre « Abandonner ? » casserait encore à côté de l'icône.
- **B7.4** : le Calendrier n'a pas de second bouton ; seule « Ma journée » en
  a deux.
- **B7.8** : le web exporte un *nombre* de transactions, pas une liste.
- **B7.11** : c'est **plus grave** qu'annoncé.
- **B7.12** : il n'y a pas de `TextSpan` ; ce qui manque, c'est la preuve.
- **B7.14** : la correction proposée par le BACKLOG casserait la porte de
  « rejoindre ».

| # | Défaut | Où |
|---|---|---|
| B7.1 | « Propriétaire » en `gold` (#B5830A, 11 px) sur une teinte or à 12 % : **2,97:1** sur la carte blanche, 2,79:1 sur le fond — sous le plancher de 4,5:1 du texte. Le web écrit `textPrimary` sur la teinte (15:1). Le test de contraste ne couvre pas cette puce | `widgets/team/team_role_chip.dart:18-43` ; SYSTEM §21 ligne 28 |
| B7.2 | À 200 % sur 360 dp : « Mard/i » (et « Mercred/i », « Vendred/i ») dans les lignes de pause — environ 60 dp restent pour le jour, il en faut 72 à 110 ; le titre « Abandonner les modifications ? » casse aussi : 232 dp à côté de l'icône, « modifications » en demande 272 et « Abandonner » 241. `expectNoMidWordBreak` ne nomme aucun jour ni titre | `widgets/provider/weekly_hours_editor.dart:123-147` ; `widgets/common/myweli_date_picker.dart:274` ; `confirm_dialog.dart:125-139` |
| B7.3 | Le dialogue de suppression dit « Votre salon sera retiré de MyWeli » à tout le monde, membre compris ; le web choisit selon le salon affiché — le serveur, lui, retire les salons **possédés** | `screens/provider/profile/pro_profile_screen.dart:377` ; `web/components/pro/CompteDangerSection.tsx:222` |
| B7.4 | Le jour vide du Calendrier est fait à la main (sans la marge ni le centrage d'`EmptyState`) et sa dernière ligne ne passe pas sous le bouton flottant ; « Ma journée » vide offre la même action deux fois (« Nouveau » flottant + « + Nouvelle réservation »), qui se touchent à 200 % ; l'onglet Liste fait aussi son état vide à la main | `appointment_calendar_view.dart:129-177` ; `pro_journal_screen.dart:112-190` ; `appointment_list_screen.dart:219-246` ; SYSTEM §21 lignes 80–81 |
| B7.5 | La ligne d'un membre révoqué s'ouvre encore ; son menu n'a que « Changer le rôle », que le serveur refuse (409 `member_revoked`, sans phrase dans l'app) | `screens/provider/team/team_screen.dart:180, 344` |
| B7.6 | Une invitation en attente n'apparaît que dans Profil (une ligne et un compteur) ; « Accueil » et la « Journée » du collaborateur n'en disent rien — le web montre une carte avec « Rejoindre » / « Refuser » | `pro_profile_screen.dart:206` ; `web/components/pro/ProInvitationsCard.tsx` |
| B7.7 | « Acompte & annulation » est coché pour tous les salons : le serveur répond toujours 200 avec des valeurs par défaut, et l'app comme le web prennent « une réponse » pour « un choix » | `providers/pro_onboarding_provider.dart:92` ; `web/components/pro/GoLiveCard.tsx:57` ; `web/lib/pro/onboarding.ts:119` |
| B7.8 | L'export de l'app n'a pas les revenus (cinq lectures) ; il lit `transactions` avec indulgence (une liste absente devient vide), contre la règle de #630 | `screens/provider/profile/pro_data_export_screen.dart:84` ; `core/utils/data_export.dart:86-157` ; `services/interfaces/pro_service_interface.dart:74` |
| B7.9 | Android : aucune orientation fixée, les deux apps tournent ; l'iPhone est en portrait, l'iPad libre | `android/app/src/main/AndroidManifest.xml:25-33` ; `ios/Runner/Info.plist:112-122` |
| B7.10 | Les montants des jeux de test plafonnent à 25 000 ; les cinq endroits de SYSTEM §21 ligne 96 sont *calculés*, jamais vus cassés ; `reportGluedTokenBreaks` n'affirme rien, et deux des cinq endroits lui échappent (une date sans espace insécable, les tableaux admin hors du test) | `test/a11y/_a11y.dart:481` ; `_fixtures.dart:52` ; SYSTEM §21 ligne 96 |
| B7.11 | Quatre boutons « Appeler » : deux demandent d'abord `canLaunchUrl(tel:)`, qui répond « non » sur Android 11+ (et probablement sur iOS) faute de déclaration — **sans un mot** ; un autre n'attend pas la réponse | `screens/providers/provider_detail_screen.dart:786, 1220` ; `appointment_detail_screen.dart:82` ; `screens/provider/clients/client_detail_screen.dart:306` |
| B7.12 | Deux liens séparés existent bien (`Semantics(link: true)`), mais rien ne prouve qu'un lecteur d'écran trouve deux nœuds | `widgets/common/legal_consent_text.dart` ; SYSTEM §21 ligne 49 |
| B7.13 | `AdminSegmentedControl` : segments inactifs sans bord, piste #F5F5F5 sur fond #F6F7F9 ; la modération en a une copie à la main, avec un libellé lu deux fois | `screens/admin/widgets/admin_segmented_control.dart:25-60` ; `admin_moderation_screen.dart:289-358` ; SYSTEM §21 ligne 26 |
| B7.14 | Après un repli sur le salon par défaut, `_refreshMembership` ne vide jamais les magasins par salon, et `checkMembershipAlive` seulement si la relecture réussit : les données de l'ancien salon s'affichent sous le nom du nouveau | `providers/pro_auth_provider.dart:323-366` |

## 2. Ce qui change

### 2.1 « Propriétaire » lisible (B7.1)
- Le libellé passe en **`textPrimary`** sur la teinte or, comme le web. La
  teinte et le bord ne changent pas : l'or reste la couleur de la puce, il
  cesse seulement d'être celle du texte.
- **Contraste** : la puce entre dans `contrast_test.dart`, mesurée sur la
  carte blanche **et** sur le fond, la teinte mélangée avec
  `Color.alphaBlend`.
- **Photos** : celles de l'équipe sont refaites sur Linux.
- La ligne 28 de §21 se ferme.

### 2.2 Plus de mot coupé à 200 % (B7.2)
- **Les horaires** (`WeeklyHoursEditor`, aussi dans la fiche d'un employé) :
  la mesure `TextFit`, déjà utilisée sur la fiche client et l'accueil. Quand
  le jour, le bouton d'horaire et l'interrupteur ne tiennent pas sur une
  ligne, le jour passe **au-dessus**, sur sa propre ligne, et le bouton et
  l'interrupteur restent ensemble dessous.
- **Les titres de dialogue** (`ConfirmDialog`) : l'icône va **au-dessus**
  du titre quand le mot le plus long ne tient pas à côté d'elle, ce qui
  libère 264 dp à 200 %. Seul « Abandonner les modifications ? » dépasse
  encore (« modifications » demande 272 dp). Il devient « Abandonner ? »,
  et le message dit le reste.
- **Les tests** :
  - `expectNoMidWordBreak` nomme les sept jours, et **chaque titre de
    dialogue de l'app** (dix-sept aujourd'hui), à 200 % sur 360 dp.
  - Un test de source vérifie que la liste des titres testés suit celle des
    titres du code.

### 2.3 La suppression d'un compte dit vrai à un membre (B7.3)
- **Aujourd'hui** :
  - **App** : `pro_profile_screen.dart:377` dit à tout le monde « Votre salon
    sera retiré de MyWeli. Pensez à exporter vos données avant. »,
    collaborateur compris. Aucun test de rôle.
  - **Web** : `CompteDangerSection.tsx:222` choisit selon `salon.publish` dans
    le salon **affiché**.
  - **Le serveur**, lui, retire les salons que le compte **possède**, tous
    (`provider_account_service.dart:104-140`).
  - Les deux clients se trompent donc dans un cas : un propriétaire qui
    regarde un salon où il n'est que gérant lit la phrase du membre, alors
    que son propre salon sera retiré.
- **Ce qui change** (Q5) : la phrase du propriétaire s'affiche dès que le
  compte **possède un salon**, comme le serveur l'entend (dans « Mes
  salons », un salon où il est Propriétaire, ou son salon lié). Sinon, la
  phrase du membre : « Cette action est définitive. Votre compte MyWeli Pro
  sera supprimé. » Même règle sur le web. Le reste du dialogue ne change pas
  (« SUPPRIMER » à taper, l'export proposé au propriétaire seulement).

### 2.4 Les jours vides, et ce qu'un écran doit au bouton flottant (B7.4, décision 25)
- **Une règle d'abord, que SYSTEM n'avait pas** (§21, ligne 80 : « §13 ne
  dit pas ce qu'une vue qui défile doit à un bouton flottant ») :
  - Toute vue qui défile sous un bouton flottant se termine par
    **`AppTheme.fabClearance`** (96 dp : le bouton étendu, sa marge et un
    peu d'air).
  - Le jeton entre dans SYSTEM §5, avec la règle.
  - Le `96` écrit à la main dans « Ma journée » devient ce jeton.
- **Le Calendrier** et **la Liste** utilisent l'`EmptyState` partagé, avec
  sa marge et son centrage, à la place de leurs états vides faits à la main.
  Les deux réservent `fabClearance` en bas.
- **« Ma journée »** (Q4) : **un seul contrôle**, le bouton flottant
  « Nouveau ». Le « + Nouvelle réservation » de l'état vide disparaît : le
  bouton flottant est toujours là, et l'état vide dit simplement qu'il n'y a
  rien.
- **Les deux boutons flottants ne disent pas la même chose** : « Ajouter »
  sur le Calendrier et la Liste, « Nouveau » dans « Ma journée ». Ils
  disent désormais tous les deux « Nouveau ».
- **Tests** :
  - Disposition à 200 % sur un téléphone de 360 × 780, bouton flottant
    compris, pour les trois écrans vides.
  - Le bas de la dernière ligne doit pouvoir défiler au-dessus du bouton.
  - Les lignes 80 et 81 de §21 se ferment.

### 2.5 Un membre révoqué n'a plus de menu (B7.5)
- **Aujourd'hui** (`team_screen.dart:180`) : la ligne d'un membre révoqué
  s'ouvre encore (avec un chevron). Son menu ne contient que « Changer le
  rôle », et le serveur répond **409 `member_revoked`** depuis le lot 6. Ce
  code n'a pas de phrase dans l'app : le message est générique. Le mock
  accepte le changement.
- **Ce qui change** : la ligne d'un membre révoqué ne s'ouvre plus et perd
  son chevron, comme sur le web (« — » à la place du menu). Elle garde
  « Accès révoqué ». `member_revoked` reçoit sa phrase (« Ce membre n'a
  plus accès au salon. »), au cas où un écran resté ouvert l'enverrait. Le
  mock refuse comme le serveur.

### 2.6 Les invitations sur « Accueil » et sur la « Journée » (B7.6, décision 23)
- **Aujourd'hui** : une invitation en attente n'apparaît que dans Profil,
  sous forme de ligne avec un compteur (`pro_profile_screen.dart:206`).
  « Accueil » et la « Journée » du collaborateur n'en disent rien. Le web,
  lui, affiche une carte « Invitations d'équipe » sur « Aujourd'hui », avec
  « Rejoindre » et « Refuser ».
- **Ce qui change** (Q1) : la même carte, en haut d'« Accueil » et de la
  « Journée » du collaborateur.
  - **Chargement** : `ProTeamProvider.loadMyInvitations()`, au montage et
    au tirage pour rafraîchir. Un échec reste silencieux, comme sur le web :
    la carte ne s'affiche pas.
  - **La carte** : un titre, « Invitations d'équipe », puis un
    `InvitationCard` par invitation (« {Salon} vous invite comme {rôle} »,
    « Expire le … »), comme sur le web. Elle est déjà mesurée à 200 %.
  - **Vide** : rien du tout, ni titre ni place réservée.
  - **Une action à la fois** : pendant qu'une réponse est en cours, tous les
    boutons attendent.
  - **« Rejoindre »** : la carte disparaît, « Vous avez rejoint {salon} »
    s'affiche (la phrase de l'écran Invitations), et **« Mes salons » est
    rechargé**. Aujourd'hui, un « Rejoindre » hors connexion ne le recharge
    pas : le nouveau salon manque au sélecteur jusqu'au prochain chargement.
    Corrigé dans le fournisseur, donc partout.
  - **« Refuser »** : la carte disparaît. Pas de confirmation : sur le web
    non plus.
  - **Expirée, ou introuvable** : la carte disparaît avec la phrase du
    serveur. **Pas de connexion** : la phrase hors connexion, et la carte
    reste.
  - **Profil** garde sa ligne avec le compteur. Les deux lisent la même
    liste.
- **Vu au passage** : `ProTeamProvider.resetForSalonSwitch` vide les
  invitations à chaque changement de salon, alors qu'elles appartiennent au
  compte. La porte de « rejoindre » s'appuie sur cette remise à zéro, qui
  précède le remplissage de ses cartes. **On n'y touche donc pas** : la
  carte recharge la liste à chaque fois qu'« Accueil » ou la « Journée »
  s'affiche pour un salon, changement de salon compris.

### 2.7 « Acompte & annulation » n'est coché qu'après un choix (B7.7, décision 24)
- **Aujourd'hui** : l'étape est cochée pour tous les salons. Le serveur
  répond toujours 200 avec des valeurs par défaut (`depositRequired: false`,
  `depositPercentage: 0`), et l'app (`pro_onboarding_provider.dart:92`) comme
  le web (`GoLiveCard.tsx:57`, `onboarding.ts:119`) prennent « une réponse »
  pour « un choix ».
- **Ce qui change** (Q2) :
  - L'étape est **faite** dès qu'un choix est enregistré, c'est-à-dire un
    acompte actif ou un pourcentage enregistré au-dessus de 0. Un premier
    enregistrement, même acompte désactivé, envoie le pourcentage du
    formulaire (30 % par défaut). Le signal sépare donc bien « jamais
    choisi » de « choisi ».
  - Sinon, l'étape est **facultative** : le statut `optional` existe déjà
    des deux côtés et ne compte pas dans la progression. Le libellé
    secondaire dit « facultatif ».
  - L'étape ne bloque pas la mise en ligne, et ça ne change pas.
  - L'app et le web changent ensemble.

### 2.8 L'export de l'app contient les revenus (B7.8)
- **Aujourd'hui** : l'export du salon dans l'app (« Mes données ») fait cinq
  lectures : le salon, les prestations, l'équipe, les rendez-vous et les
  clients. Il n'y a pas les revenus, alors que le web les met
  (`web/lib/pro/export.ts:63`). L'app lit aussi `transactions` avec
  indulgence : une liste absente devient vide
  (`pro_service_interface.dart:74`). C'est contraire à la règle de #630
  (une réponse 200 sans sa liste est une lecture échouée).
- **Ce qui change** :
  - **Une sixième lecture** : `getEarnings`, sur toute la période, comme le
    web.
  - **La section** `ProExportSection.earnings`, et la clé `earnings` avec
    **la forme exacte du web** : `{ totalEarnings, transactions: <nombre> }`.
    C'est un compte, pas la liste. Le BACKLOG disait « une liste » ; le web
    écrit un nombre, et la parité l'emporte.
  - **La ligne** « Revenus » dans le récapitulatif de l'écran.
  - **La lecture devient stricte** : `transactions` absent ou qui n'est pas
    une liste, ou `totalEarnings` qui n'est pas un nombre, donne une lecture
    échouée. L'export est alors refusé, comme pour les cinq autres lectures.
    L'écran « Revenus », qui lit la même réponse, affiche déjà son état
    d'erreur dans ce cas.

### 2.9 L'orientation (B7.9, décision 26)
- **Aujourd'hui** :
  - **Android** : aucune orientation n'est fixée sur `MainActivity`, et
    `configChanges` contient `orientation`. Les deux apps tournent donc
    librement sur Android.
  - **iPhone** : portrait seulement (`Info.plist:112`).
  - **iPad** : les quatre orientations, sans `UIRequiresFullScreen`. L'app
    client vise l'iPad, l'app Pro non.
  - **Dart** : aucun appel à `setPreferredOrientations`.
- **Ce qui change** (Q3) :
  - `android:screenOrientation="portrait"` sur `MainActivity`, pour les deux
    apps (une seule activité les porte).
  - Un test d'infrastructure fixe cette valeur, comme celui d'iOS fixe déjà
    la liste de l'iPhone.
  - Un essai sur un émulateur de tablette.
  - **Sur Android 16 et plus**, le verrou est ignoré sur les grands écrans :
    c'est la règle du système. L'app doit donc rester utilisable en paysage
    sur tablette. Ce qui le prouve, c'est l'essai sur tablette, pas le
    verrou.
  - **L'iPad** reste tel quel : verrouiller exigerait `UIRequiresFullScreen`,
    qui retire le multitâche.

### 2.10 Les grands montants à grand texte (B7.10)
- **Les jeux de test** reçoivent des montants à 7 chiffres :
  - **1 250 000 FCFA** pour un total de revenus ;
  - **450 000 FCFA** pour une prestation.
  Ils vont dans les données fictives (`mock_data.dart`) **et** dans les
  données des tests d'accessibilité (`_fixtures.dart`). Les photos qui les
  montrent sont refaites.
- **Les cinq endroits** de §21, ligne 96 :
  - les lignes de l'historique des visites ;
  - le total et les lignes des revenus ;
  - le champ de date de la réservation manuelle ;
  - les lignes de prix de la Liste et du Calendrier ;
  - les tableaux de la console admin.
  Chacun est **vu**, à 200 % sur 360 dp, avec ces montants. Ceux qui cassent
  passent à `TextFit`, la règle déjà écrite (la valeur passe sous son
  libellé quand elle ne tient pas à côté). Ceux qui tiennent sont notés
  comme tenant.
- **`reportGluedTokenBreaks` devient une assertion** : `expect(…, isEmpty)`
  au lieu d'un compte-rendu imprimé.
- **Ses deux angles morts** sont couverts à part :
  - la date de la réservation manuelle, par un `expectNoMidWordBreak` qui la
    nomme ;
  - les tableaux admin, par un sujet de mise en page à eux.
- La ligne 96 de §21 se ferme.

### 2.11 « Appeler » marche partout, et dit quand il ne peut pas (B7.11)
- **Aujourd'hui**, quatre boutons « Appeler », et c'est **plus grave que le
  BACKLOG** :
  - Les deux de la page d'un salon (app client,
    `provider_detail_screen.dart:786`, `:1220`) demandent d'abord
    `canLaunchUrl(tel:)`.
    - **Sur Android 11 et plus**, cette question répond « non » pour tout
      schéma absent des `<queries>` du manifeste. Or `tel` en est exclu,
      volontairement : le commentaire le dit.
    - **Sur iOS**, `tel` manque aussi à `LSApplicationQueriesSchemes`.
    - Ces deux boutons ne font donc **probablement rien sur la plupart des
      téléphones**, sans un mot. Seul un vrai appareil peut le confirmer.
      C'est ajouté à la liste B0.2.
  - Celui d'un rendez-vous dit « Impossible d'ouvrir l'application. ».
  - Celui de la fiche client (app Pro) n'attend même pas la réponse.
- **Ce qui change** :
  - Un seul `callPhone(context, numéro)`, construit sur `openExternalUrl`
    (`core/utils/external_link.dart`, qui a déjà le try/catch et le message).
    Il ouvre `tel:` **sans** `canLaunchUrl`, retire les espaces du numéro et
    affiche « Impossible d'ouvrir l'application. » quand rien ne s'ouvre.
  - Les quatre boutons passent par lui.
  - Un test de source interdit tout `launchUrl` avec `tel:` en dehors de
    lui.
  - `tel` rejoint aussi les `<queries>` d'Android. Ce n'est plus nécessaire
    une fois `canLaunchUrl` retiré, mais c'est sans risque, et le commentaire
    du manifeste le dit.

### 2.12 Les deux liens de la phrase de consentement, pour un lecteur d'écran (B7.12)
- **Aujourd'hui** : `legal_consent_text.dart` contient déjà deux liens
  séparés (`Semantics(link: true)` sur chacun, sans `TextSpan`), à
  l'intérieur d'un `Semantics(container: true)`. Le BACKLOG supposait des
  `TextSpan`. Il manque **la preuve** : rien ne vérifie que le lecteur
  d'écran trouve deux nœuds-liens (SYSTEM §21, ligne 49 : « la moitié
  sémantique n'est pas vérifiée »).
- **Ce qui change** : un test de sémantique attend deux nœuds, chacun
  `isLink` avec son action de tap et son libellé. S'il échoue, on ajoute
  `explicitChildNodes: true`, et la ligne 49 se ferme.

### 2.13 Les segments de la console admin ont un bord (B7.13)
- **Aujourd'hui** :
  - `AdminSegmentedControl` existe déjà, utilisé sur trois écrans.
  - Ses segments inactifs n'ont **aucun bord**, et sa piste (`surfaceVariant`
    #F5F5F5) se confond avec le fond de la console (#F6F7F9).
  - La modération en a une copie à la main (`_Segments`) :
    - même défaut ;
    - un libellé lu deux fois par TalkBack, ce que le composant partagé
      avait corrigé ;
    - deux paramètres morts.
  - SYSTEM §21, ligne 26 : « Unselected segments have no boundary ».
- **Ce qui change** :
  - Les segments inactifs prennent le bord `borderStrong`, le jeton prévu
    pour « la seule limite d'un contrôle interactif ».
  - La modération utilise le composant partagé, et sa copie disparaît.
  - Les tests d'accessibilité de la console couvrent la modération.
  - Les photos de la console sont refaites, et la ligne 26 se ferme.

### 2.14 Repli sur le salon par défaut : les magasins de l'ancien salon sont vidés (B7.14)
- **Aujourd'hui** : quand le salon choisi refuse la session (accès retiré),
  l'app se replie sur le salon par défaut. Mais `_refreshMembership` ne
  remet **jamais** les magasins à zéro, et `checkMembershipAlive` ne le fait
  que si la relecture réussit.
  - **Le cas concret** : révoqué du salon B pendant que A ne répond pas.
    L'écran « salon non chargé » s'affiche ; « Réessayer » réussit. Les
    rendez-vous, les clients, la journée et l'équipe de B s'affichent alors
    sous le nom de A, jusqu'au prochain rechargement de chaque écran.
- **Ce qui change, et ce n'est pas la correction du BACKLOG** :
  - Le BACKLOG proposait `ProSalonScope.resetAll()` *dans*
    `_clearSalonSelection()`. Or `_enterRejoin` appelle cette fonction
    *après* ses `await`, et sa remise à zéro doit précéder le premier
    `await`, sinon elle vide les cartes que la porte vient de remplir (le
    spinner S9). La correction du BACKLOG aurait cassé la porte, et le test
    `pro_auth_rejoin_test.dart:102` (`expect(scoped.resets, 1)`).
  - La remise à zéro se fait donc **aux deux endroits du repli** : dans
    `_refreshMembership` après le repli, et dans `checkMembershipAlive`
    **même si la relecture échoue**.
  - Les tests utilisent `_ResetSpy` (`multi_salon_test.dart`).

## 3. Le contrat

**Aucun changement** : ni route, ni forme, ni code d'erreur.
- B7.5 s'appuie sur le 409 `member_revoked` du lot 6.
- B7.6 utilise les routes d'invitation existantes : `GET
  /me/provider/invitations`, puis `…/accept` et `…/decline`.
- B7.8 lit `GET /providers/{id}/earnings`, tel qu'il est.

## 4. Le système de dessin (SYSTEM.md)

- **Nouveau jeton** : `AppTheme.fabClearance` (96 dp). Une **nouvelle
  règle**, en §13.3 : une vue qui défile sous un bouton flottant s'arrête à
  `fabClearance` du bas.
- **Lignes du registre (§21) fermées** :
  - 26 (segments sans bord) ;
  - 28 (« Propriétaire ») ;
  - 49 (consentement, la moitié sémantique) ;
  - 80 et 81 (jours vides) ;
  - 96 (grands montants).
- **`ConfirmDialog`** : la règle de l'icône au-dessus du titre est écrite
  dans le catalogue des composants (§11.1).

## 5. Les tests (rouges d'abord)

- **Contraste** : la puce « Propriétaire » sur la carte et sur le fond.
- **200 %** :
  - les sept jours et les dix-sept titres de dialogue ;
  - les trois écrans vides avec leur bouton flottant ;
  - les cinq endroits de la ligne 96 ;
  - `reportGluedTokenBreaks` qui affirme.
- **Widgets** :
  - le dialogue de suppression : propriétaire, membre, propriétaire qui
    regarde un salon où il n'est que membre ;
  - la ligne d'un révoqué, qui ne s'ouvre plus ;
  - la carte d'invitations : vide, rejoindre (« Mes salons » rechargé),
    refuser, expirée, hors connexion, une action à la fois, sur « Accueil »
    et sur la « Journée » ;
  - « Acompte & annulation » : jamais choisi, choisi désactivé, choisi
    actif ;
  - l'export avec les revenus, et refusé quand `transactions` manque ;
  - « Appeler » quand rien ne s'ouvre ;
  - les deux nœuds-liens du consentement ;
  - les segments de la console.
- **Logique** : le repli sur le salon par défaut vide les magasins, que la
  relecture réussisse ou non. Et la porte de « rejoindre » ne se vide
  **qu'une fois** (son test existant reste vert).
- **Web** :
  - la phrase de suppression selon « possède un salon » ;
  - « Acompte & annulation » facultatif.
- **Infrastructure** :
  - l'orientation portrait d'Android est fixée par un test ;
  - aucun `tel:` n'est ouvert en dehors de `callPhone`.
- **Mutations** sur le travail enregistré, comme toujours.

## 6. La livraison

**Trois PR**, toutes des apps (et du web pour B7.3 et B7.7), **sans
déploiement du serveur**. Le web part à la fusion ; l'app part avec la
prochaine version des stores (0.0.2, lot 0).

- **(A) Dire vrai** :
  - B7.3 (app et web) ;
  - B7.5 ;
  - B7.7 (app et web) ;
  - B7.9 ;
  - B7.11 ;
  - B7.14.
- **(B) Lire à 200 %, et voir les bords** : B7.1, B7.2, B7.4, B7.10, B7.12,
  B7.13. Elle change les photos.
- **(C) La parité** : B7.6, B7.8.

## 7. Les mots

- **B7.3, membre** : « Cette action est définitive. Votre compte MyWeli Pro
  sera supprimé. »
- **B7.3, propriétaire** : inchangé.
- **B7.5** : la phrase de `member_revoked`, « Ce membre n'a plus accès au
  salon. »
- **B7.6** :
  - le titre « Invitations d'équipe » ;
  - « {Salon} vous invite comme {rôle} » et « Expire le … » (la carte
    existante) ;
  - « Rejoindre », « Refuser » ;
  - après « Rejoindre », « Vous avez rejoint {salon} ».
- **B7.7** : « facultatif ».
- **B7.2** : « Abandonner ? »
- **B7.4** : « Nouveau » pour les trois boutons flottants.
- **B7.11** : « Impossible d'ouvrir l'application. » (la phrase existante).
- **B7.8** : « Revenus », dans le récapitulatif de l'export.

## 8. Questions au propriétaire

- **Q1 (décision 23)** — Les invitations : **la carte du web**, avec
  « Rejoindre » / « Refuser », **sur « Accueil » et sur la « Journée » du
  collaborateur** (recommandé), ou seulement le compteur de Profil ?
- **Q2 (décision 24)** — « Acompte & annulation » : **facultatif tant
  qu'aucun choix n'est enregistré** (recommandé ; l'acompte ne conditionne
  pas la mise en ligne), ou obligatoire ?
- **Q3 (décision 26)** — L'orientation : **portrait sur Android et sur
  iPhone, pour les deux apps, l'iPad inchangé** (recommandé), ou un travail
  de mise en page paysage pour l'app client ?
- **Q4 (décision 25)** — « Ma journée » vide : **garder le bouton flottant
  « Nouveau »** (recommandé), ou garder « + Nouvelle réservation » dans la
  page ?
- **Q5** — La phrase de suppression : **selon « le compte possède un
  salon »**, comme le serveur l'entend (recommandé), ou selon le rôle dans
  le salon affiché, comme le web aujourd'hui ?
- **Q6** — Le reste, tel qu'écrit : les trois PR, les mots du §7, les
  corrections au BACKLOG (B7.2, B7.11, B7.14), les montants à 7 chiffres ?

**Décisions (2026-10-22).** Q1 à Q6 : les recommandations, telles qu'écrites.

## 9. PR A construite (B7.3, B7.5, B7.7, B7.9, B7.11, B7.14) — ce qui a été vu

**Comme écrit**, avec ces précisions :
- **B7.3** :
  - **L'app** : la règle vit dans `ProAuthProvider.ownsASalon` (le salon
    lié du compte, ou un salon dont il est Propriétaire dans « Mes
    salons »).
  - **Le web** : la même règle, `ownsASalon(profil, salons)` dans
    `lib/pro/team.ts`, que la section lit avec « Mes salons » du contexte du
    tableau de bord.
  - **Les mots** : la phrase du propriétaire reste entière (« Pensez à
    exporter… »), même quand il regarde un salon qu'il ne fait que gérer. Il
    peut exporter depuis le sien, et l'app dit la même chose.
  - **Un garde-fou existant l'a vu** : le balayage des lectures de
    `.providerId` (`multi_salon_test`) exige que chaque lecture soit
    justifiée. Celle-ci l'est : elle dit si le compte *possède* un salon,
    jamais dans quel salon agir.
- **B7.5** :
  - Le menu d'un révoqué n'existe plus.
  - `member_revoked` a sa phrase.
  - Le mock refuse comme le serveur.
- **B7.7** :
  - `depositChosen` existe des deux côtés : `core/utils/deposit.dart` dans
    l'app, `lib/pro/deposit.ts` sur le web.
  - Le libellé secondaire est « Facultatif » : une majuscule, comme les
    autres libellés secondaires de la liste.
  - **Le test du web en place figeait le défaut lui-même**. La carte « En
    ligne » était testée avec les valeurs par défaut du serveur et attendait
    « 6 étapes sur 8 ». Il est corrigé.
- **B7.9** :
  - `android:screenOrientation="portrait"` sur `MainActivity`, et un test
    d'infrastructure le fixe.
  - Un second test vérifie qu'aucune autre activité n'existe, donc qu'un
    seul verrou couvre les deux apps.
- **B7.11** :
  - `callPhone` est construit sur `openExternalUrl`.
  - Les quatre boutons « Appeler » passent par lui.
  - `tel` est déclaré dans les `<queries>`.
  - Un test de source interdit tout `tel:` ailleurs.
  - **Seul un vrai appareil peut confirmer** que les deux boutons de la page
    d'un salon étaient morts. C'est ajouté à la liste des essais sur
    appareil (B0.2).
- **B7.14** : la remise à zéro a lieu aux deux endroits du repli,
  **avant** la relecture, quelle que soit sa réponse. Le test de la porte
  de « rejoindre » (`expect(scoped.resets, 1)`) reste vert.

**Vérifié** : `dart analyze` et `flutter analyze` à zéro (un import inutile, vu par
l'analyse complète, retiré) ; format propre ; serveur avec Postgres
(2 161 tests, 2 ignorés — rien n'y a changé) ; web (2 181) ; app (2 583) ;
e2e entier sur deux workers (269).
- **Mutations vues rouges : 26.**
  - **Une a d'abord survécu** : `ownsASalon` qui ignorait « Mes salons ».
    Elle a demandé un test, un compte sans salon lié mais Propriétaire d'un
    salon par une adhésion.
  - **Ce test a d'abord échoué pour une raison à lui** : la liste
    « Mes salons » du mock lit aussi les offres, qui n'étaient pas branchées
    dans le test ; et la connexion lance son propre chargement, qu'il faut
    attendre en temps réel.
- **Sur un émulateur Android 16** (API 36) :
  - **Le manifeste construit** porte `screenOrientation=1` et la
    déclaration `tel` (`aapt2`).
  - **En téléphone** (360 × 800 dp), le paysage demandé ne tourne pas
    l'écran : l'app reste en portrait (`ROTATION_0`, `MainActivity` au
    premier plan).
  - **En dimensions de tablette** (`wm size` 1600 × 2560 à 320 dpi, soit
    800 dp de plus petite largeur), Android 16 dit
    `ignoreOrientationRequest=true`. Quand on tourne l'appareil, l'écran
    passe en paysage (`ROTATION_270`, 2560 × 1600). L'app y reste
    utilisable : une colonne centrée, rien ne déborde, aucune erreur dans le
    journal.
  - **Pourquoi pas une vraie tablette émulée** : le disque de la machine
    n'avait que 4,7 Go libres, et l'émulateur tablette en demandait 7,2. Le
    téléphone réglé en dimensions de tablette passe par la même règle
    d'Android (la plus petite largeur de l'écran).
