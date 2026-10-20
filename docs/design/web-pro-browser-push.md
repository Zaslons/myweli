# Web Pro — les notifications du navigateur : prévenu·e sur l'ordinateur, onglet fermé — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-20** sur `feat/web-pro-browser-push` (au-dessus de #649) ; ce qui a été vu : §11. Validé le même jour — Q1 : **seul un push de l'app remplace l'e-mail** ; Q2 : **comme l'app** (le bandeau une fois, puis la page Notifications) ; Q3 : **ordinateur seulement** ; Q4 : **les mots tels qu'écrits** (§9, §10) · **Mergé (#662) le 2026-10-20** — web en production à la fusion ; serveur en production : révision `myweli-api-00042-468` (image `9f320d4`, `sha256:498778da…`), 100 % du trafic, le 2026-10-20 — **invisible tant que les cinq variables Firebase ne sont pas dans Vercel** (§7, propriétaire) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-20 |
| **PRD ref / phase** | FR-NOTIF-001 (canal push) · parité web ↔ app Pro · V1 |
| **Module** | web Pro — `/pro` (Accueil), `/pro/notifications` (Préférences), la déconnexion ; un service worker ; backend `PushService`, `SalonNotifier`, `FcmV1PushProvider` |
| **Origine** | décision du propriétaire (2026-10-19) : **« les deux, l'e-mail d'abord »** — l'e-mail est construit ([salon-email-alerts.md](salon-email-alerts.md), #649) ; voici le second canal. Audit de parité §3 n° 5 |
| **Dépend de** | #649 (les alertes par e-mail : la règle « aucun push → e-mail », la section « Préférences » de la page Notifications) — cette branche part de la sienne |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-backend-guardrails ✓ · myweli-dev-guardrails ✓ |

## 1. Le constat — relu sur le vrai chemin de code

- **L'app Pro** (`dashboard_screen.dart`, `push_registration.dart`) : à la
  **première visite de l'Accueil**, une seule fois, une feuille « Activer les
  notifications » — « Soyez prévenu·e dès qu’un client réserve, reporte,
  annule ou envoie son acompte, et ne manquez aucune demande. » — « Activer »
  (puis la demande du système) / « Plus tard ». Jamais redemandé. Refusé au
  niveau du téléphone : la page Notifications le dit (« Notifications
  désactivées pour l’appareil » + « Ouvrir les réglages »). À la connexion,
  si c'est déjà permis, l'appareil se réinscrit ; à la déconnexion, il se
  désinscrit. Au premier plan, la notification s'affiche quand même. Un
  toucher ouvre la fiche dans le bon salon.
- **Le web Pro** n'a **rien** de tout cela : ni service worker, ni Firebase,
  ni demande de permission. Onglet fermé, il n'apprend rien ; avec #649, il
  reçoit l'e-mail.
- **Le serveur est prêt à moitié** : `POST/DELETE /me/devices` accepte déjà
  `platform: web` ; `FcmV1PushProvider` envoie à n'importe quel jeton FCM ;
  le `data` du push porte `appointmentId` et `providerId`.
- **Le piège, vu dans le code** (`salon_notifier.dart`, #649) : l'e-mail part
  quand `delivered == 0`. Or FCM **accepte** un push vers un navigateur
  **fermé** (il le garde et le remet à la réouverture). Si un jeton du
  navigateur comptait, un salon qui a activé les notifications sur
  l'ordinateur de la boutique puis l'a éteint **ne recevrait plus l'e-mail** —
  ni rien d'autre jusqu'au lendemain (Q1).
- **Aucun lien vers l'app MyWeli Pro** dans les stores n'existe sur le web
  (`appStore.ts` ne connaît que l'app client) : sur téléphone, le web ne peut
  pas encore « pousser l'app Pro » sans promettre un téléchargement
  introuvable (la règle de `AppInstallBanner`) (Q3).

## 2. Le parcours proposé (Q2 : comme l'app)

1. **Accueil, première visite sur ce navigateur** (ordinateur, navigateur
   capable, permission « à demander ») : un bandeau **non modal** en haut de
   l'Accueil — titre, phrase, « Activer » / « Plus tard ». Une fenêtre sur la
   page d'arrivée d'un ordinateur serait une interruption ; le bandeau dit la
   même chose et ne bloque rien.
2. « Activer » → **la demande du navigateur** (jamais sans ce geste : les
   navigateurs relèguent les demandes faites d'office). Acceptée → ce
   navigateur s'inscrit ; le bandeau devient « Notifications activées sur cet
   ordinateur. » quelques secondes, puis disparaît. Refusée → le bandeau
   disparaît (la page Notifications dira comment rétablir).
3. « Plus tard », ou une réponse quelle qu'elle soit → **plus jamais ce
   bandeau sur ce navigateur** (le drapeau « demandé » de l'app, gardé dans le
   navigateur).
4. **Toujours réglable** sur `/pro/notifications`, section « Préférences »,
   **au-dessus** d'« Alertes par e-mail » : la ligne « Notifications du
   navigateur » et son interrupteur (§4).
5. **Une notification arrive** : le titre et la phrase **du push de l'app**
   (le même envoi, aucun texte nouveau), le logo MyWeli ; un clic ouvre la
   fiche **sur le web, dans le bon salon** (`/pro/rendez-vous/{id}?salon=…`),
   dans l'onglet MyWeli déjà ouvert s'il y en a un, sinon un nouvel onglet ;
   connexion demandée si la session a expiré. Onglet ouvert et visible : la
   notification s'affiche quand même (comme l'app), et la cloche relit le fil
   tout de suite au lieu d'attendre ses 60 s.
6. **Connexion** sur un navigateur déjà autorisé (et pas coupé par
   l'interrupteur) → il se réinscrit, sans rien demander (comme l'app).
   **Déconnexion** → il se désinscrit **avant** que la session parte : un
   ordinateur partagé ne reçoit plus les alertes d'un compte sorti.

## 3. Les états de la ligne « Notifications du navigateur »

| État | Ce que dit la ligne | Le contrôle |
|---|---|---|
| Lecture | (la section « Préférences » montre déjà son squelette) | — |
| Pas configuré (variables Firebase absentes) | **la ligne n'existe pas** | — |
| Navigateur incapable (pas de service worker / Push / Notification) | « Ce navigateur ne peut pas afficher de notifications. » | aucun |
| Téléphone (Q3 a) | « Sur téléphone, les notifications passent par l’app MyWeli Pro. » | aucun (un lien vers le store quand il existera) |
| À demander | le sous-titre (§9) | interrupteur **éteint** ; l'allumer → la demande du navigateur |
| Permis et inscrit | le sous-titre | interrupteur **allumé** ; l'éteindre → désinscription de ce navigateur |
| Permis, coupé ici | le sous-titre | interrupteur **éteint** ; l'allumer → inscription (sans demande) |
| Bloqué par le navigateur | « Notifications bloquées pour ce navigateur » + la marche à suivre (§9) | aucun : une page ne peut pas ouvrir les réglages du navigateur |
| En cours | — | interrupteur occupé (`aria-busy`) |
| Échec (jeton, réseau, serveur) | « L’activation a échoué. Réessayez. » (`role="alert"`) | revient à éteint |

Optimiste comme « Alertes par e-mail » ; l'interrupteur est **le même
composant** (`PrefSwitch`, 48 px, nommé par le titre). Le réglage vaut **pour
ce navigateur** (un jeton par navigateur), pas pour le compte — d'où « sur cet
ordinateur » dans les mots.

## 4. Ce que fait le serveur

- **Q1 (a) recommandé : seul un push de l'app remplace l'e-mail.**
  `DeviceTokenRepository` rend les jetons **avec leur plateforme** ;
  `PushService.sendToUser` rend deux comptes (`app`, `web`) ;
  `SalonNotifier` envoie l'e-mail quand `app == 0` (au lieu de `delivered ==
  0`). Le pied de page de l'e-mail reste vrai mot pour mot (« aucune
  notification de l’app MyWeli Pro ne vous est parvenue »). Le salon devant
  son ordinateur reçoit la notification **et** l'e-mail ; il peut couper
  l'e-mail.
- **Le push vers le web** : `FcmV1PushProvider` ajoute un bloc `webpush`
  (`headers: { Urgency: high, TTL: 86400 }`) — l'équivalent de la priorité
  haute d'Android ; au-delà d'un jour, une alerte de réservation n'aide plus
  (l'e-mail et le fil l'ont déjà dite).
- **Aucun changement de contrat REST** (`/me/devices` accepte déjà `web`) ;
  aucune migration (`device_tokens.platform` existe).

## 5. Technique (web)

- **FCM pour le web**, comme l'app : le SDK Firebase modulaire
  (`firebase/app` + `firebase/messaging`), **chargé à la demande** (au clic
  « Activer », ou à la connexion d'un navigateur déjà autorisé) — jamais sur
  les pages publiques, jamais dans le premier chargement du Pro. Le serveur
  reste inchangé côté envoi ; l'autre voie (le protocole Web Push, VAPID,
  chiffrement côté serveur en Dart) serait un second fournisseur à écrire et
  à garder.
- **Notre service worker**, `/pro/push-sw.js`, portée `/pro/` : il ne fait
  **que** `push` → `showNotification` et `notificationclick` → l'onglet. Pas
  de cache, pas d'interception de requêtes (aucun risque de page périmée).
  Le lien du clic est **construit** à partir d'`appointmentId` et
  `providerId` (identifiants vérifiés par motif) — jamais une adresse lue
  telle quelle dans le message.
- **BFF** : `POST`/`DELETE /api/pro/devices` → `/me/devices` avec la session
  Pro ; la plateforme est **fixée à `web` par le BFF**, le jeton borné
  (4 096 caractères, comme le serveur).
- **Configuration** (valeurs publiques par nature) :
  `NEXT_PUBLIC_FIREBASE_API_KEY`, `…_PROJECT_ID`, `…_APP_ID`,
  `…_MESSAGING_SENDER_ID`, `…_VAPID_KEY`. Absentes → la fonction se cache
  (pas de ligne, pas de bandeau), comme le bouton Apple sans
  `NEXT_PUBLIC_APPLE_CLIENT_ID`.
- **CSP** (Report-Only) : `worker-src 'self'` ; `connect-src` +
  `https://fcmregistrations.googleapis.com`,
  `https://firebaseinstallations.googleapis.com` — **mesurés** au build, pas
  devinés (la règle de `next.config.mjs`).

## 6. Sécurité, vie privée

- **Aucune donnée client** dans la notification (T58, inchangé : la phrase du
  push ne nomme ni client ni téléphone). Sur un ordinateur de boutique, c'est
  ce qui rend l'affichage acceptable.
- **Ordinateur partagé** : désinscription à la déconnexion ; un jeton
  réinscrit par un autre compte change de propriétaire (règle existante,
  T22) ; un membre retiré de l'équipe n'est plus destinataire (règle
  existante). Une déconnexion **ratée** (réseau) laisse le jeton — le serveur
  ne peut pas le savoir ; la session, elle, reste aussi (le verrou de
  `ProMembershipContext`), donc rien de neuf.
- **Clé d'API Firebase** : publique ; à **restreindre aux référents
  `myweli.com`** dans la console Google (propriétaire).
- **Politique de confidentialité** : elle nomme déjà Firebase Cloud Messaging
  (notifications) ; une phrase précise que le navigateur, une fois autorisé,
  reçoit un identifiant de notification (§9).
- BACKEND.md §7 : T22 (jetons `web`, ordinateur partagé), T58 (le canal du
  navigateur) mis à jour.

## 7. À faire par le propriétaire (console, pas le dépôt)

1. Dans le projet Firebase **du compte de service `FCM_*`** (le même — sinon
   `SENDER_ID_MISMATCH`), ajouter une **application Web** ; en noter la
   configuration.
2. Cloud Messaging → **Certificats Web Push** → générer la paire ; la clé
   publique = `NEXT_PUBLIC_FIREBASE_VAPID_KEY`.
3. Les cinq variables dans Vercel (Production et Preview).
4. Restreindre la clé d'API aux référents `https://myweli.com/*`.
5. Ordre de déploiement : **le serveur d'abord** (le compte `app` de Q1),
   puis le web.

## 8. Les tests (rouges d'abord)

- **Backend** : jetons avec plateforme (mémoire + Postgres) ; `sendToUser`
  compte `app` et `web` ; **un push web accepté n'empêche pas l'e-mail**, un
  push d'app accepté l'empêche ; le bloc `webpush` dans la charge ; rien ne
  change pour l'app.
- **Web, pur** : la détection (capable, téléphone, permission), l'état de la
  ligne (§3), le lien du clic construit à partir des identifiants (un
  `providerId` hostile → la liste des rendez-vous, jamais ailleurs).
- **Web, composants** : le bandeau (une seule fois, « Plus tard », jamais sur
  téléphone ni sans configuration, la demande seulement après « Activer ») ;
  la ligne dans chacun de ses états ; l'inscription au clic, la
  désinscription à l'extinction, l'échec qui revient ; la réinscription à la
  connexion ; la désinscription **avant** la déconnexion ; le BFF (session
  Pro, plateforme forcée, jeton borné).
- **Le service worker** (pur, sans navigateur) : un `push` → la bonne
  notification ; un clic → l'onglet existant ou un nouveau, au bon lien.
- **e2e** : axe, cibles et reflow sur l'Accueil avec le bandeau et sur
  Notifications avec la ligne (Firebase remplacé par une couture de test) ;
  la CSP (le test existant).
- **Vu dans un vrai navigateur** avant de dire « fait » : une vraie
  notification FCM reçue onglet fermé, un clic qui ouvre la fiche — possible
  seulement avec la configuration du §7.

## 9. Les mots (Q4)

- **Bandeau de l'Accueil** — titre « Activer les notifications » ; phrase
  (celle de l'app, avec le lieu) : « Soyez prévenu·e sur cet ordinateur dès
  qu’un client réserve, reporte, annule ou envoie son acompte, et ne manquez
  aucune demande. » ; boutons « Activer » / « Plus tard » ; après
  l'activation : « Notifications activées sur cet ordinateur. »
- **Ligne de la page Notifications** — titre « Notifications du navigateur » ;
  sous-titre : « Sur cet ordinateur, même quand MyWeli n’est pas ouvert, tant
  que votre navigateur l’est : nouvelle demande, report, annulation,
  justificatif d’acompte. »
- **Bloqué** — « Notifications bloquées pour ce navigateur » ; « Autorisez
  myweli.com dans les réglages du site (l’icône à gauche de l’adresse), puis
  rechargez la page, pour être prévenu·e des réservations, reports,
  annulations et acomptes de vos clients. »
- **Incapable** — « Ce navigateur ne peut pas afficher de notifications. »
- **Téléphone** (Q3 a) — « Sur téléphone, les notifications passent par
  l’app MyWeli Pro. »
- **Échec** — « L’activation a échoué. Réessayez. »
- **Confidentialité** — « Si vous autorisez les notifications dans votre
  navigateur, il reçoit un identifiant de notification (Firebase Cloud
  Messaging), supprimé quand vous les coupez ou vous déconnectez. »

## 10. Questions au propriétaire

- **Q1 — un navigateur prévenu remplace-t-il l'e-mail ?** (a) **Non : seul un
  push de l'app remplace l'e-mail** ; la notification du navigateur vient en
  plus (recommandé — un navigateur fermé « reçoit » quand même, et l'e-mail
  se tairait) ; (b) oui, tout push accepté remplace l'e-mail (moins de
  doublons, un salon peut ne rien voir jusqu'au lendemain).
- **Q2 — où le web demande.** (a) **Comme l'app** : une fois, à la première
  visite de l'Accueil, un bandeau ; puis la ligne de la page Notifications
  (recommandé) ; (b) seulement la ligne de la page Notifications.
- **Q3 — sur téléphone.** (a) **Ordinateur seulement** ; sur téléphone, la
  ligne dit que l'app s'en charge (recommandé : le téléphone est le terrain
  de l'app, l'e-mail y couvre le web ; un iPhone n'accepte ces notifications
  que pour un site ajouté à l'écran d'accueil) ; (b) partout où le
  navigateur le permet (Android, iPhone depuis l'écran d'accueil).
- **Q4 — les mots** (§9), tels qu'écrits ?

**Décisions (2026-10-20).** Q1 (a), Q2 (a), Q3 (a), Q4 approuvé tel qu'écrit.

## 11. Construit — ce qui a été vu

**Comme écrit**, avec ces précisions :
- Le serveur : `devicesForUser` (les jetons avec leur plateforme) et
  `PushService.sendToUserByKind` (deux envois, l'app puis les navigateurs, deux
  comptes) ; `sendToUser` rend toujours le total aux autres appelants. Le
  notifier lit **`app`** seul.
- Le web dépend de `@firebase/app` + `@firebase/messaging`, **pas** du paquet
  `firebase` : celui-ci tire Firestore et `@grpc/grpc-js`, soit quatre alertes
  `npm audit` de plus pour du code jamais appelé. Version 12.19 (la 13.0 avait
  treize jours).
- Le bandeau est aussi sur l'accueil du Collaborateur (« … — votre
  planning ») : il reçoit les alertes de son artiste.
- Une **extinction** qui échoue reprend les mots d'« Alertes par e-mail »
  (« L’enregistrement a échoué. Réessayez. ») ; l'interrupteur reste allumé,
  puisque les alertes continueraient.
- `PrefSwitch` gagne `busy` (`aria-busy`, désactivé pendant la question du
  navigateur).

**Trouvé en construisant** :
- **Firebase n'attend un service worker actif que s'il l'enregistre
  lui-même** (`registerDefaultSw` → `waitForRegistrationActive`) ; le nôtre lui
  était donné encore en installation, et `pushManager.subscribe` échoue sur un
  worker qui s'installe : **le tout premier « Activer » aurait dit
  « L’activation a échoué. »**. Lu dans la source de @firebase/messaging
  0.13.3 ; le jeton attend maintenant l'activation (bornée à 10 s). L'e2e ne
  pouvait pas le voir (son jeton est nommé avant Firebase) ; un test unitaire
  le garde, vu rouge.
- **Le `Notification.permission` de Chromium sans écran reste `denied`** —
  avant toute question, après `grantPermissions`, après que
  `requestPermission()` a répondu `granted`, après un rechargement (mesuré
  sur une page nue). Le premier passage e2e voyait « Notifications bloquées
  pour ce navigateur » partout. L'e2e fait lire à la page ce que lirait un vrai
  navigateur (`asUnaskedBrowser`, `asGrantedBrowser`).
- **Un téléphone par sa seule chaîne d'agent** : `navigator.userAgentData
  .mobile` restait `false`, et la page voyait un ordinateur — c'est ce champ
  qu'elle croit d'abord, à raison ; l'e2e émule un vrai téléphone
  (`devices['Pixel 7']`).
- Le clic cherche un onglet `/pro` ou `/pro/…` — pas `/professionnels`.
- La CSP (Report-Only) : les deux hôtes **mesurés** dans les paquets
  (`firebaseinstallations`, `fcmregistrations.googleapis.com`) et
  `worker-src 'self'`, dans la liste des origines qu'aucun parcours du code ne
  trouve.

**Mutations vues rouges** — serveur : l'e-mail qui compte les navigateurs,
les jetons web jamais envoyés, le bloc `webpush` retiré ; web : le BFF qui
transmet la plateforme du corps, le worker qui suit la `route` du message, le
lien du clic non vérifié, le bandeau qui oublie « demandé », la déconnexion
sans désinscription (unitaire **et** e2e), la connexion qui ignore « coupé
ici », un téléphone qui reçoit l'interrupteur, le jeton qui n'attend pas
l'activation.

**Vu dans un navigateur** (le volet de l'app, sur le stub) : avec la
permission telle qu'il la donne (`denied`), la ligne dit « Notifications
bloquées… » et la marche à suivre, sans interrupteur ; en lui faisant lire
`default` puis répondre oui : le bandeau à 310 px, « Activer » → le worker
**actif** à `/pro/`, `POST /api/pro/devices` 200 avec le jeton,
« Notifications activées sur cet ordinateur. », plus de bandeau ; sur
Notifications, l'interrupteur allumé (48 × 48) au-dessus d'« Alertes par
e-mail » ; éteint → `DELETE` 200, rallumé → `POST` 200 ; « Se déconnecter » →
`DELETE` **puis** la déconnexion.

**Vérifié** : backend — format et analyse propres, **1 788** tests + **79**
Postgres (base neuve) ; web — typecheck et lint propres, **1 723** tests ;
e2e (pro, axe, cibles, reflow, rôles, légal) **151** verts.

**Non vérifié** : une **vraie** notification FCM reçue onglet fermé et son clic
— il faut l'application Web Firebase et la clé Web Push (§7, propriétaire) ;
Safari et Firefox.

