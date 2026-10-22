# Un ancien membre réinvité retrouve son invitation au lieu d'être déconnecté — spec UX

| | |
|---|---|
| **Statut** | **Approuvé par le propriétaire le 2026-10-14** (« yes » aux trois choix du §9) — **construit le 2026-10-15, fusionné** (#600 ; app Pro + web Pro). Côté app : part avec le prochain build (0.0.2), pas avec le 587 en revue. Côté web : en ligne. Ce qui a été construit, et où cela s'écarte du texte ci-dessus : §10. |
| **Module** | `access` (équipe) — app Pro et web Pro |
| **Origine** | [backend-team-reinvite.md](backend-team-reinvite.md) §11.1 ; le propriétaire, le 2026-10-14 : « do as you think is better ». |
| **Backend** | **Aucun changement.** `GET /me/provider/invitations` et `POST /me/provider/invitations/{id}/accept|decline` marchent déjà pour une session sans adhésion active. |

## 1. Le problème

Une personne qui a été membre d'un salon (Manager, Réception, Collaborateur),
puis révoquée, a un compte MyWeli. Quand le propriétaire la **réinvite**
(possible depuis #596), elle reçoit l'e-mail « connectez-vous avec cette
adresse — votre invitation vous attend », se connecte… et **l'app la
déconnecte** aussitôt : `GET /me/provider` répond `403 not_a_member` (elle a
une ligne, aucune active), et l'app comme le web traitent ce code par
« Votre accès a été retiré » + déconnexion. Elle ne voit jamais l'invitation.
Le pont d'invitation de la connexion ne l'aide pas : il ne s'ouvre que pour
une adresse **sans** compte.

Le même mur existe aujourd'hui pour un ancien membre invité dans **un autre**
salon.

Et un défaut voisin, vu en cartographiant : dans l'app, un compte révoqué
**sans** invitation qui se connecte n'arrive pas sur la page de connexion avec
le bandeau, mais sur l'écran verrouillé du tableau de bord (« Veuillez vous
connecter ») — le bandeau n'apparaît qu'au tap suivant.

## 2. La règle — la même dans l'app et sur le web

Sur `403 not_a_member`, **tant que la session est encore valide** :

1. demander `GET /me/provider/invitations` ;
2. **une invitation ou plus** → l'écran **« Invitations »** (§3). La session
   est gardée ; le contexte du salon perdu est vidé (son agenda, ses clientes
   ne restent pas en mémoire) ;
3. **aucune**, ou la requête échoue (hors ligne, erreur) → **comme
   aujourd'hui** : déconnexion, page de connexion, bandeau « Votre accès à
   {salon} a été retiré. » — on **échoue fermé** : en cas de doute, on ne garde
   pas une session sans salon ;
4. avant toute déconnexion décidée sur une liste vide, **revérifier une fois**
   `GET /me/provider` : si une acceptation vient d'aboutir (la liste est vide
   *parce que* l'invitation est devenue active), on entre dans l'app au lieu de
   déconnecter.

La règle s'applique aux trois chemins où `not_a_member` arrive : **après une
connexion** (le cas principal), **au démarrage** (session restaurée), **en
cours de session** (révoqué pendant qu'on utilise l'app).

## 3. L'écran « Invitations » (mode « réadmission »)

Réutilise l'écran et les cartes d'invitation qui existent déjà (app :
`ProInvitationsScreen` + `InvitationCard` ; web : `ProInvitationsCard`), dans
un mode où l'on ne peut aller nulle part ailleurs :

```
┌──────────────────────────────────────┐
│ Invitations                Déconnexion│   ← pas de retour, pas d'onglets
├──────────────────────────────────────┤
│ ⓘ Votre accès à Beauté Divine a été  │   ← seulement si le nom du salon
│   retiré.                             │     est connu (démarrage / en cours)
│                                       │
│ Vous êtes invité(e)                   │
│                                       │
│ ┌──────────────────────────────────┐ │
│ │ Beauté Divine vous invite comme   │ │
│ │ Réception                         │ │
│ │ Expire le 21 octobre              │ │
│ │ [ Rejoindre ]   Refuser           │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

Pas de cloche, pas de profil, pas de menu : rien de l'ancien salon n'est
atteignable depuis cet écran.

## 4. Tous les états

| # | Situation | Ce que voit la personne |
|---|---|---|
| S1 | Une ou plusieurs invitations | L'écran ci-dessus, sans spinner (la liste est déjà chargée). |
| S2 | « Rejoindre » réussit | Indicateur de chargement plein écran, puis l'app **du salon rejoint** (espace Collaborateur, ou tableau de bord) et « Vous avez rejoint {salon} ». |
| S3 | « Rejoindre » — invitation expirée ou retirée entre-temps | La carte disparaît ; « Cette invitation a expiré. Demandez au salon de la renvoyer. » ou « Introuvable. Actualisez et réessayez. ». S'il n'en reste aucune → S6. |
| S4 | « Rejoindre » hors ligne | « Pas de connexion. Réessayez. » — la carte reste, le bouton redevient actif. |
| S5 | « Rejoindre » refusé (`forbidden`) | « Invitation impossible à accepter. » (pas le texte destiné aux propriétaires). |
| S6 | « Refuser » la dernière carte (ou S3 sur la dernière) | Déconnexion, page de connexion, bandeau « Votre accès à {salon} a été retiré. ». La ligne redevient « révoquée » côté serveur (#596). |
| S7 | « Refuser » une carte parmi plusieurs | La carte disparaît ; l'écran reste. Échec → « Refus impossible. ». |
| S8 | « Déconnexion » | Comme S6. |
| S9 | Démarrage de l'app alors que la personne est dans ce cas | L'écran « Invitations » (un bref passage par l'ancien écran est possible si le réseau est lent — accepté). |
| S10 | Notification touchée pendant ce temps | Retenue, puis rejouée une fois la personne entrée dans un salon. |
| S11 | Connexion d'un compte révoqué **sans** invitation | La page de connexion **avec le bandeau**, directement (corrige l'écran verrouillé d'aujourd'hui). |

Textes : **tous existent déjà** dans l'app ou sur le web ; aucun nouveau texte
n'est inventé, sauf, sur le web, « Invitation impossible à accepter. » (repris
de l'app).

## 5. Ce qui change, où

- **App** — `ProAuthProvider` : un seul point de décision pour `not_a_member`
  (aujourd'hui deux, qui peuvent se croiser), l'état « réadmission en
  attente », l'entrée et la sortie de cet état ; l'écran de démarrage et la
  page de connexion y conduisent ; les notifications attendent ;
  `ProInvitationsScreen` gagne le mode « réadmission » ; le bandeau de la page
  de connexion devient un composant partagé.
- **Web** — `ProMembershipContext` : la même règle avant la déconnexion ; une
  page intermédiaire « Invitations » à la place du tableau de bord ;
  `ProInvitationsCard` retire une carte expirée (comme l'app) et ne reste plus
  bloqué hors ligne.
- **Mock de l'app et stub du web** : les invitations du compte connecté, un
  ancien membre réinvité.

## 6. Sécurité

Rien de nouveau côté serveur : chaque route résout l'adhésion à chaque requête
(T38), la session d'un compte révoqué était déjà valide, et l'écran
« Invitations » n'expose ni cloche, ni fil de notifications, ni profil.
L'acceptation exige toujours la bonne adresse e-mail.

## 7. Tests (vus rouges d'abord)

- App, unitaires : une invitation garde la session et passe en réadmission ;
  aucune → déconnexion avec le nom du salon ; un échec de la requête →
  déconnexion ; deux `not_a_member` simultanés → une seule requête ; la
  revérification sauve une acceptation qui a croisé la liste vide ; connexion
  Google/e-mail d'un compte révoqué sans invitation → reste sur la connexion.
- App, widgets : connexion révoquée sans invitation → bandeau ; avec
  invitation → écran, « Rejoindre » → espace Collaborateur ; refus de la
  dernière → connexion + bandeau ; démarrage → écran ; notification retenue.
  Une image de référence de l'écran (générée sur Linux).
- Web : Vitest du contexte (invitation → page intermédiaire, rien → déconnexion,
  erreur → déconnexion, « Rejoindre » → tableau de bord + message) ; e2e : un
  ancien membre rejoint, un autre refuse.

## 8. Hors périmètre

- Un membre **actif ailleurs** qui reçoit une invitation : il n'est jamais
  bloqué ; il la voit dans Profil → Invitations (app) ou sur « Aujourd'hui »
  (web). Un badge sur le tableau de bord de l'app viendrait plus tard.
- L'acceptation publique qui crée un compte nu avant d'accepter (voir
  [backend-team-invite-caps.md](backend-team-invite-caps.md) §10.2, PR #597).

## 9. À valider

1. La règle du §2, et surtout **« échouer fermé »** (hors ligne au mauvais
   moment → déconnexion, comme aujourd'hui) plutôt qu'un écran d'erreur.
2. L'écran du §3 : réutiliser « Invitations » plutôt qu'un écran nouveau.
3. S6 : refuser la dernière invitation **déconnecte** (on ne garde pas une
   session qui ne mène à aucun salon).

## 10. Ce qui a été construit (2026-10-15)

**App** (`mobile/`) — un seul point de décision pour `not_a_member`
(`_onNotAMember`, partagé par `refreshMembership` et `checkMembershipAlive`,
qui ne s'exécute qu'une fois même si deux réponses arrivent ensemble) ;
l'état « réadmission » (`rejoinPending`, ses invitations, le salon perdu) ;
l'entrée vide le salon perdu (adhésion, cache, sélection, liste des salons,
données par salon) ; la sortie (`completeRejoin`) ne lève la réadmission
qu'**une fois** le routeur dans le salon rejoint, pour qu'une notification
retenue ne se rejoue pas par-dessus l'écran ; démarrage, connexion et
notifications y conduisent. `ProInvitationsScreen` a son mode « réadmission »
(décidé à l'ouverture), et le bandeau de la connexion devient un composant
partagé (`RevokedAccessBanner`). Le défaut S11 (connexion révoquée → écran
verrouillé) est corrigé : le bandeau s'affiche sur place.

**Web** (`web/`) — la même règle dans `ProMembershipContext` ; une page
intermédiaire `ProRevokedInvitations` ; `ProInvitationsCard` retire une carte
expirée ou retirée, ne reste plus bloqué hors ligne, et « Refuser » devient un
vrai bouton de 48px ; après « Rejoindre » depuis une page profonde, la page
attend `/pro` pour ne pas monter un instant une page de l'ancien rôle.

**Écarts au texte, assumés** :
- « Déconnexion » est une **icône** avec cette info-bulle (app) : §13.3 et le
  registre §21 ligne 79 demandent une icône dans une barre d'app à 200 %.
- La **revérification** de `GET /me/provider` précède aussi une déconnexion
  décidée sur un **échec** de la liste, pas seulement sur une liste vide : elle
  ne peut garder qu'une session que le serveur rattache à un salon ;
  l'échec fermé tient.
- Le bandeau « Votre accès à {salon} a été retiré. » n'apparaît sur l'écran que
  quand le salon perdu est connu (en cours de session, au démarrage) ; après
  une connexion, il est omis, comme le prévoit §3.
- Web : le message de succès reprend celui de l'app, sans point final.
- `ApiAuthService.cacheProviderMembership(null)` ne vidait rien (l'app réelle
  aurait gardé l'ancienne adhésion en cache) : corrigé, dans son propre commit.

**Trouvé en regardant l'image** (règle §20.1) : la première image Linux de
l'écran montrait « **Rejoind/re** » à 360dp × 2 — la carte d'invitation
partagée (`InvitationCard`, aussi dans Profil → Invitations et à l'étape
« invitations » de la connexion) gardait ses deux actions côte à côte.
Elle les **empile** maintenant, chacune pleine largeur, quand « Rejoindre » ne
tient pas entier à côté de « Refuser » — mesuré avec le style et les marges des
boutons ; à 1×, rien ne change (les 51 autres images sont identiques à
l'octet).

**Tests, chacun vu rouge d'abord** — app : 22 unitaires
(`pro_auth_rejoin_test.dart`), 12 d'écran (`pro_rejoin_gate_test.dart`), le
démarrage, la notification retenue, le cache ; 20 mutations sur du code
commité, toutes rouges. Web : 16 Vitest du contexte, 11 de la carte, 6 de
parité des textes, 2 e2e Playwright (un ancien membre rejoint ; un autre
refuse — avec axe, cibles de 48px et un passage à 320px) ; 9 mutations, toutes
rouges. L'image de référence `pro_rejoin_gate_w360_x2.png`, générée sous Linux.

### 10.1 Après la revue adverse (2026-10-15)

Une revue en quatre angles (états et courses de l'app, web, UX et parité,
session) a trouvé 17 défauts, tous confirmés par un sceptique ; deux
correcteurs les ont fermés (chacun vu rouge d'abord, 20 mutations par surface),
un vérificateur a relu chaque correction, et ses deux nouvelles remarques sont
fermées aussi. Ce que cela change à la spec :

**Les deux surfaces**
- **Plus aucune sortie sans revérification** : « Refuser » la dernière carte,
  ou une dernière carte refusée comme expirée ou introuvable, revérifie
  `GET /me/provider` avant de déconnecter (§2.4). Si la personne a déjà
  rejoint ailleurs (autre appareil, réponse perdue), elle entre dans le salon,
  sans message. Le motif (« Cette invitation a expiré. … » / « Introuvable. … »)
  n'est montré que si l'on déconnecte — sur la page de connexion.
- **Une réponse à la fois, la sortie comprise** : « Déconnexion » /
  « Se déconnecter » attend pendant un « Rejoindre » ou un « Refuser » ; une
  acceptation qui répond après une déconnexion ne mène nulle part (et le web
  relance la déconnexion, au cas où la réponse aurait remis des cookies).
- **Une session morte** (le serveur refuse le renouvellement) quitte l'écran
  pour la connexion. App : sans le bandeau « accès retiré » (aucun accès n'a été
  retiré), avec « Veuillez vous reconnecter. » (texte existant). Web : avec le
  motif, comme les autres sorties de l'écran. **Un renouvellement qui échoue
  faute de réseau n'est pas une session morte** : l'app la garde et dit
  « Pas de connexion. Réessayez. » (trouvé par la vérification).
- Les textes d'échec sont ceux de S5/S7 sur les deux surfaces : « Invitation
  impossible à accepter. » / « Refus impossible. » pour un refus ou une erreur
  serveur, la phrase hors ligne sinon.

**Web**
- **Une déconnexion ratée n'est jamais montrée comme faite** : le bouton reste,
  se réactive et dit « Pas de connexion. Réessayez. » ou « Une erreur est
  survenue. Réessayez. ». La déconnexion automatique (S6, S8, 401) qui échoue
  s'arrête sur une page verrouillée (« Espace Pro », le bandeau, l'erreur,
  « Se déconnecter »).
- La revérification précède aussi une déconnexion décidée sur une liste en
  **échec**, comme l'app.
- Après un « Rejoindre » dont le `/me` échoue, la barre latérale garde son
  squelette — jamais un menu tiré d'une adhésion absente — et le fournisseur
  **redemande** avec une pause croissante (1, 2, 4, 8, 16 s, puis 30 s) jusqu'à
  ce qu'un profil arrive (trouvé par la vérification).
- Le focus suit : la carte suivante prend le focus sur son « Rejoindre » quand
  une carte part ; chaque attente place le focus sur le titre de la page.
- Le motif d'une dernière carte expirée ou introuvable voyage jusqu'à la page
  de connexion (`&raison=invitation-expiree|invitation-introuvable`, lu
  seulement avec `motif=acces-retire`, deux valeurs fermées).
- Refuser la dernière carte affiche l'attente pendant la déconnexion.

**App**
- Au démarrage, l'entrée dans l'écran vide les données du salon perdu **avant**
  de lever l'état « réadmission » : l'écran ne peut plus s'ouvrir sur des
  cartes effacées.
- `ApiProTeamService` répond `unauthorized` quand aucune session n'est
  stockée (au lieu d'un « Non connecté » sans code).

**Écart assumé — web, après un rechargement** : la ligne « Votre accès à
{salon} a été retiré. » n'apparaît que pour une révocation vue dans le même
onglet. Après une connexion, un rechargement ou un nouvel onglet, le web ne
connaît pas le salon perdu : le 403 ne porte pas de nom, `/me/salons` ne liste
que les adhésions actives, le cookie de sélection ne garde qu'un identifiant —
et aucun stockage côté client n'a été ajouté pour cela. L'app, elle, garde le
nom en cache et l'affiche aussi au démarrage.

**Restes, antérieurs, non traités ici** : une erreur serveur dont le corps
n'est pas du JSON (une page HTML d'erreur de la porte d'entrée) s'affiche
« Erreur » dans l'app ; la carte « Invitations » de la page « Aujourd'hui »
(hors écran de réadmission) ne quitte pas la page sur un 401 ; un `/me` en
échec au tout premier affichage (sans écran de réadmission) garde le menu
d'avant.

