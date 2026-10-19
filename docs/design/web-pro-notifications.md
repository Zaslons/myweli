# Web Pro — le centre de notifications du salon — spec

| | |
|---|---|
| **Statut** | **Approved le 2026-10-19** — les trois décisions du §9 telles que recommandées : nav + cloche mobile, rafraîchissement 60 s (onglet visible) + titre + annonce, le texte du §4 |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-19 |
| **PRD ref / phase** | FR-NOTIF · parité web ↔ app Pro · V1 |
| **Module** | web Pro (`/pro/notifications`, la barre latérale, la barre du haut mobile, le détail d'un rendez-vous) |
| **ROADMAP entry** | à créer au build |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · myweli-backend-guardrails : **aucun changement serveur** (lu seulement) |
| **Dépend de** | [#640](https://github.com/Zaslons/myweli/pull/640) **déployé** — l'état vide nomme les « reports » (§4.4) |

## 1. Le constat

- **L'app Pro** : une cloche avec un **compteur de non-lus** dans la barre de
  l'Accueil → `/pro/notifications` : la liste (les quatre états), un toucher
  = lu + ouvre le rendez-vous, « Tout marquer comme lu », le bandeau « notifications
  désactivées ». Un toucher sur une notification d'**un autre salon** du compte
  bascule de salon avant d'ouvrir (`?salon=`, R6).
- **Le web Pro** : **rien**. Aucune page, aucune cloche, aucun compteur. Le
  serveur écrit pourtant un fil pour chaque membre (`SalonNotifier` : nouvelle
  réservation, report — #640 —, annulation, justificatif d'acompte), et
  `GET /me/notifications` sert **tout compte connecté**, salon compris
  (`routes/me/notifications/index.dart`, rôle indifférent). Un salon qui
  travaille sur PC toute la journée — le cas que WEB-SYSTEM §9 vise — ne voit
  jamais qu'un client vient de réserver, sauf en rouvrant l'agenda.
- Le web **client** a son centre depuis la parité 5.1
  ([web-notifications-revenus.md](web-notifications-revenus.md)) — on
  réutilise sa forme, pas sa session.

## 2. Objectif et périmètre

**Dedans** : la page `/pro/notifications` ; l'entrée dans la navigation avec
le compteur ; la cloche de la barre du haut mobile ; le rafraîchissement du
compteur pendant que l'onglet est ouvert ; le passage d'un salon à l'autre
depuis une notification ; trois routes BFF.

**Dehors** : le push web (pas de service worker — décision à part) ; les
préférences (l'app Pro n'en a pas ; le push est par appareil) ; le web Pro
sans accès public (traité dans [web-pro-access.md](web-pro-access.md)).

## 3. Le parcours

### 3.1 Les entrées

| Où | Quoi | Pourquoi |
|---|---|---|
| **Barre latérale** (desktop `lg+` et tiroir mobile) | Une entrée **« Notifications »** juste après « Aujourd’hui », avec une **pastille numérique** des non-lus (« 3 », plafonnée à « 99+ ») | La navigation persistante est le patron du tableau de bord ; un nombre dit *combien* — ce que l'app dit avec son badge. Visible pour **tous les rôles** : chaque membre a son fil (le Collaborateur ne reçoit que ses rendez-vous, filtré par le serveur) |
| **Barre du haut mobile** (`< lg`) | Une **cloche** à droite, avec la même pastille | Le tiroir cache la navigation : sans la cloche, savoir qu'il y a du nouveau coûterait deux gestes. C'est la place de la cloche dans l'app (barre de l'Accueil, à droite) |

Le nom accessible porte le nombre : « Notifications, 3 non lues » ; sans
non-lu : « Notifications ». La pastille est `aria-hidden` (le nom le dit déjà).

### 3.2 Le compteur reste à jour

- Lu une fois au montage du tableau de bord, **puis toutes les 60 s tant que
  l'onglet est visible** (`document.visibilityState`), et aussitôt quand
  l'onglet redevient visible. Onglet caché → aucune requête.
- Quand le nombre **augmente**, une région `role="status"` polie annonce
  « 1 nouvelle notification » / « 3 nouvelles notifications » (WCAG 4.1.3) —
  jamais au premier chargement, jamais quand il baisse.
- Le titre de l'onglet porte le nombre : « (3) Pro — Aujourd’hui » (le patron
  de tout outil de bureau ; un salon voit l'onglet depuis un autre).
- Lire une notification sur la page met le compteur à jour sans attendre la
  minute suivante (même source d'état).

### 3.3 La page `/pro/notifications`

- `h1` « Notifications » ; à droite, **« Tout marquer comme lu »** (bouton
  secondaire) tant qu'il reste un non-lu — le libellé de l'app.
- **La liste** (≤ 50, le plus récent en haut — ce que le serveur rend) : la
  forme du centre client — pictogramme par type (`general` → cloche,
  `reschedule` → ⇄, `cancellation` → ✕, `depositReceived` → portefeuille),
  titre en gras et point « Non lu » tant que non lu, corps, date.
- **Compte à plusieurs salons** : chaque ligne porte **le nom du salon**
  (lu dans `?salon=` de sa route, nommé par la liste « Mes salons »). Le corps
  ne nomme personne (T58) ; sans le salon, « Nouvelle réservation le 28/06 à
  14:30 » ne dit pas *où*. L'app ne l'affiche pas ; le web le peut sans rien
  changer au serveur. Un compte à un seul salon ne voit pas l'étiquette.
- **Une ligne est un lien** (`<a>`, pas un bouton) vers
  `/pro/rendez-vous/{id}?salon={salon}` : clic = lu (optimiste) + ouverture ;
  ⌘/Ctrl-clic ouvre un onglet. Un lien qui *va* quelque part est un lien.
- **Si la marque « lu » échoue** : la ligne redevient non lue et dit pourquoi,
  sous elle, `role="alert"` — la règle du centre client
  ([web-consumer-optimistic-revert.md](web-consumer-optimistic-revert.md)) ;
  pareil pour « Tout marquer comme lu » (seul ce que *ce geste* a marqué
  revient non lu).

### 3.4 Ouvrir le rendez-vous d'un autre salon

Le détail (`ProAppointmentDetailClient`) lit `?salon=` : s'il nomme un autre
salon que le salon actif, il **bascule d'abord** (`switchSalon`, le même que
« Mes salons »), puis charge. Échec de bascule → l'état d'erreur du détail
avec la phrase du sélecteur (« Changement impossible — votre accès à ce salon
a peut-être été retiré. », ou « Pas de connexion. Réessayez. » sans réponse).
C'est le flux de l'app (`ProAppointmentDetailScreen(salonId:)`), et il tient
aussi pour un lien ouvert dans un nouvel onglet.

### 3.5 Les routes que le serveur écrit → le web

| Route du fil | Web |
|---|---|
| `/pro/appointment/{id}?salon={s}` | `/pro/rendez-vous/{id}?salon={s}` |
| `/pro/appointments` | `/pro/rendez-vous` |
| autre / absente | pas de lien (la ligne se marque lue au clic, sans navigation) |

## 4. Les états et le texte

| État | Rendu |
|---|---|
| Chargement | squelette de 5 lignes |
| Erreur | `ErrorState` « Notifications » + `loadFailureMessage` (« Pas de connexion. Réessayez. » sans réponse — #629) + « Réessayer » |
| 401 | `/pro/connexion` (le patron Pro) |
| Vide | `EmptyState` cloche · **« Aucune notification »** · **« Les réservations, reports, annulations et acomptes de vos clients apparaîtront ici. »** (le texte N5 de l'app — vrai une fois #640 en production) |
| Liste | §3.3 |

Texte nouveau à valider : « Notifications » (entrée de nav, `h1`) ·
« Tout marquer comme lu » · « Notifications, {n} non lues » (nom accessible ;
« 1 non lue » au singulier) · « 1 nouvelle notification » / « {n} nouvelles
notifications » (annonce) · « (n) » en tête du titre de l'onglet.

## 5. Contrat et BFF

Aucun changement serveur ni OpenAPI. Trois routes BFF, session Pro
(`callApiPro` / `respondPro`) :

| BFF | Méthode | Backend |
|---|---|---|
| `/api/pro/notifications` | GET | `GET /me/notifications` |
| `/api/pro/notifications/read-all` | POST | `POST /me/notifications/read-all` |
| `/api/pro/notifications/[id]/read` | POST | `POST /me/notifications/{id}/read` (auto-scopé) |

Le fil est **par compte**, pas par salon : pas de `salonId`.

## 6. Accessibilité

Liens et boutons ≥ 48 px ; focus visible ; nom accessible avec le nombre ;
la pastille ne porte pas seule le sens (le nom le dit, le titre est en gras
*et* marqué « Non lu ») ; annonce polie de l'augmentation ; la région existe
avant le texte (WEB-SYSTEM §7) ; page dans les matrices axe et reflow
(320/375/1280).

## 7. Performance et sécurité

- Une requête de ≤ 50 lignes par minute et par onglet **visible** ; aucune
  sinon. Pas de PII nouvelle : les corps sont ceux du serveur (T58).
- Session httpOnly ; le serveur est l'autorité (le fil est auto-scopé ; la
  bascule de salon est refusée par le serveur pour un salon révoqué — T55).

## 8. Tests (rouges d'abord)

- Unitaires : `webRouteFor` Pro (les trois lignes du §3.5), le nom du salon
  depuis `?salon=`, le compteur (« 99+ », singulier/pluriel), la règle
  d'annonce (augmente → annonce ; premier chargement / baisse → rien).
- RTL : la page (quatre états, lien + `?salon=`, « Tout marquer comme lu »,
  retour non-lu sur échec) ; la nav (entrée + pastille + nom accessible) ;
  la cloche mobile ; le détail qui bascule de salon (succès, refus, réseau) ;
  le minuteur (visible → requête ; caché → aucune).
- BFF : les trois routes, 401 sans session.
- e2e / a11y : la page dans axe et la matrice de reflow.

## 9. Décisions à valider

1. L'entrée : nav « Notifications » + pastille, **et** cloche mobile (recommandé).
2. Le rafraîchissement : 60 s onglet visible + titre d'onglet + annonce (recommandé).
3. Le texte du §4.
