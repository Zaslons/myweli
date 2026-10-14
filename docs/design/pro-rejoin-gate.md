# Un ancien membre réinvité retrouve son invitation au lieu d'être déconnecté — spec UX

| | |
|---|---|
| **Statut** | **Proposition, à valider par le propriétaire avant construction** (UX d'abord). Rien n'est construit. |
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
