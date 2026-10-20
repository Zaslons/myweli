# Pro web — le panneau « Journée » montre l'acompte, la capture et le lien vers la fiche ; « Non présenté » attend le début du rendez-vous et demande confirmation — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-19** sur `fix/web-pro-journal-panel-deposit` — validé par le propriétaire le même jour : l'UX, le texte T1–T13 mot pour mot, **Q1 = la consigne seulement en attente**, **Q2 = le retour ramène à aujourd'hui pour l'instant, le jour dans l'URL en tranche suivante** (§10). Vu rouge : 37 tests sur `main`, puis 6 mutations ; e2e des 7 fichiers touchés : 128 verts ; l'épingle d'heure de `roles.spec` vue rouge à 08:00 (§11) · **Mergé (#644) le 2026-10-20** — web en production à la fusion |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-19 |
| **PRD ref / phase** | La parité web ↔ app Pro (WEB.md, « feature parity ») · la décision sans-custody des acomptes (PRD OQ-1, mémoire `payments-no-custody-screenshot`) · V1 — tableau de bord Pro web |
| **Module** | web Pro — `/pro/rendez-vous` « Journée » (`JournalPanel`), la fiche `/pro/rendez-vous/{id}` (`ProAppointmentDetailClient`), `lib/pro/lifecycle.ts`, `proDepositScreenshotUrl`, la CSP (`img-src`) |
| **Source** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §3 n° 1 (P1) et, du §4 (P2) : « justificatif à cliquer, sans consigne, échec silencieux », « Absent proposé sur un rendez-vous futur, et sans confirmation dans le panneau » |
| **Gouverné par** | [journal-j1-grid.md](journal-j1-grid.md) §3.4 — qui promettait déjà, dans le panneau, « deposit + proof link » et « Non présenté only after start » : le panneau ne l'a jamais tenu |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · myweli-verification-guardrails (avant de dire « fait ») · aucun changement serveur, aucun contrat |

## 1. Le constat — relu sur le vrai chemin de code (`main` a91edc66)

**Le web.** Dans la Journée, un clic sur un bloc ouvre `JournalPanel`
(`JournalGrid.tsx:352` → `:187`). Le panneau montre Statut, Date, Prestations,
Total (`JournalPanel.tsx:181-191`) et, sur une demande en attente, **Accepter /
Refuser** (`:196-212`). Il ne montre **ni l'acompte annoncé, ni la capture, ni
de lien vers la fiche du rendez-vous**. La grille n'a qu'un « · ₣ » dans le bloc
(`JournalGrid.tsx:381`), et seulement quand le bloc fait plus de 34 px.
**Un salon peut donc accepter, depuis la Journée, une demande à acompte sans
voir si l'acompte a été envoyé.** La fiche, elle, n'est atteignable que par
« Liste » ou « Calendrier ».

**L'app.** Un appui sur une carte de « Ma journée » ouvre la fiche
(`pro_journal_screen.dart:290` → `/pro/appointment/{id}`), qui montre, dès que
`depositAmount > 0` (`pro_appointment_detail_screen.dart:229-260`) :
« Acompte annoncé : 5 000 FCFA », la consigne « Confirmez le rendez-vous une
fois l'acompte reçu sur votre compte Mobile Money. », puis la capture — **chargée
d'elle-même** (vignette de 140 px, un appui l'agrandit, `:410-468`), ou
« Aucune capture jointe pour le moment. », ou, si le chargement échoue,
« Capture indisponible. Réessayez plus tard. ».

**La fiche web** (`ProAppointmentDetailClient.tsx:258-290`) a « Acompte
annoncé » mais :
- la capture est derrière un bouton « Voir le justificatif » ;
- **l'échec est muet** : `proDepositScreenshotUrl` (`lib/api/pro.ts:307-312`)
  rend `null` sur tout échec — coupure, 403, 404, 5xx — et le bouton
  `setProofUrl(null)` ne change rien : on clique, rien ne se passe ;
- pas de consigne ;
- sans capture : « Justificatif d'acompte non reçu. » (l'app : « Aucune capture
  jointe pour le moment. »).

**« Non présenté ».** Le serveur accepte `pending|confirmed → noShow` **sans
condition d'heure** (`pro_appointment_service.dart:112-119`), et l'état est
terminal : un clic de trop sur un rendez-vous de demain enregistre le client
comme absent — **son compteur d'absences dans ce salon monte** (le badge de
chacun de ses rendez-vous, rouge à partir de 2).
- l'app (fiche) ne propose « Marquer comme absent » qu'une fois l'heure de
  début passée (`:351`, `!appointmentDate.isAfter(now)`), **avec** une
  confirmation (`:357-368`) ;
- le web, fiche : proposé sur **tout** rendez-vous confirmé, même futur
  (`lifecycle.ts:22-31`), avec une confirmation ;
- le web, panneau : proposé sur tout rendez-vous confirmé, **sans**
  confirmation (`JournalPanel.tsx:230-236`).

**Deux faits vus en relisant, qui changent la conception :**

1. **Un Collaborateur ne peut pas voir la capture.** Le serveur ne la signe que
   pour `journal.view.all` (`deposit_service.dart:165-171`) ; le Collaborateur
   n'a que `journal.view.own` (`capabilities.dart:91`). Charger la capture
   pour lui, c'est un 403 garanti — l'app le fait et affiche « Capture
   indisponible », ce qui est faux (elle existe). Le web ne la demande pas pour
   lui, comme il ne demande déjà pas la mini-fiche client sans `clients.view`
   (`JournalPanel.tsx:62-74`).
2. **La CSP ne nomme pas l'hôte de la capture.** L'URL signée est sur
   `https://<compte>.r2.cloudflarestorage.com` (`dependencies.dart:205-211`,
   `storage_service.dart:468`), présent dans `connect-src` (les envois) mais
   **pas dans `img-src`** (`next.config.mjs:153`). La CSP est aujourd'hui en
   *Report-Only* (`:202-226`), donc l'image s'affiche — mais chaque affichage
   envoie un rapport de violation, et **le passage en mode bloquant casserait
   la capture sans bruit**. Le test `csp.test.ts` (« les origines qu'aucune
   lecture de source ne trouve ») est aveugle à ce cas, comme il l'était aux
   envois.

## 2. Ce qu'on construit

### 2.1 Le panneau « Journée » (`JournalPanel`)

Ordre, de haut en bas (le reste du panneau ne bouge pas) :

```
Détails du rendez-vous                                   ✕
─────────────────────────────────────────────────────────
Koffi  [2 absences]
07 •• •• •• 01
┌ 3 visites · 45 000 FCFA · 2 absences ┐
│ « Cheveux fragiles »                  │
│ Voir la fiche                         │
└───────────────────────────────────────┘
Statut            En attente
Date              lun. 20 oct. 2026, 09:00
Prestations       Tresses
Total             15 000 FCFA
Acompte annoncé    5 000 FCFA          ← NOUVEAU (si depositAmount > 0)
Confirmez le rendez-vous une fois       ← NOUVEAU (en attente seulement — Q1)
l'acompte reçu sur votre compte
Mobile Money.
┌──────────┐
│ capture  │  ← NOUVEAU : vignette 144 px, chargée d'elle-même ;
│ (144 px) │     un clic l'agrandit (Lightbox)
└──────────┘
Voir le rendez-vous                     ← NOUVEAU : lien vers /pro/rendez-vous/{id}
─────────────────────────────────────────────────────────
[Accepter] [Refuser]
[Reprogrammer]
```

- **L'acompte** : une ligne de plus dans la liste des faits, même forme que
  « Total » : « Acompte annoncé » · montant formaté dans la devise du salon
  (`formatFcfa(…, currency)`, multi-pays MP3). Affichée dès que
  `depositAmount > 0`, quel que soit le statut (comme l'app).
- **La consigne** (texte de l'app, mot pour mot) sous la ligne, en petit
  (`text-bodySmall text-textTertiary`). **Q1** : seulement tant que le
  rendez-vous est **en attente** (recommandé) — c'est là qu'elle sert : elle
  dit quand appuyer sur « Accepter » ; sur un rendez-vous confirmé ou terminé
  elle demande de faire ce qui est déjà fait. L'app la montre toujours.
- **La capture** — le statut de l'acompte, c'est elle (comme dans l'app : il
  n'y a pas d'autre « statut d'acompte » ; MyWeli ne détient pas l'argent, le
  salon confirme la réception en acceptant) :

  | Cas | Ce qui s'affiche |
  |---|---|
  | `depositScreenshotUrl` absent | « Aucune capture jointe pour le moment. » |
  | chargement | un `<Skeleton>` 144 px (la forme est connue — §12 : squelette, pas de spinner) |
  | chargée | la vignette (`h-36`, `object-cover`, coins `rounded-lg`, bordure) dans un `<button>` — « Agrandir le justificatif d'acompte » — qui ouvre la `<Lightbox>` existante (piège de focus, Échap, retour du focus) |
  | coupure (statut 0) | « Pas de connexion. Réessayez. » + bouton « Réessayer » (la règle de #629) |
  | tout autre échec — 404, 5xx, ou l'image elle-même qui ne se charge pas (l'URL signée expire au bout de 5 min, `deposit_service.dart:45` : un panneau resté ouvert, puis un clic) | « Capture indisponible. Réessayez. » + bouton « Réessayer » |
  | membre sans `journal.view.all` (Collaborateur) | **rien** sous la ligne « Acompte annoncé » — ni consigne (il ne peut pas accepter), ni capture (le serveur la lui refuse) ; aucune requête |

  « Réessayer » redemande une URL signée neuve (pas seulement l'image), ce qui
  couvre aussi l'expiration.
- **« Voir le rendez-vous »** : un lien texte souligné, de la même forme que
  « Voir la fiche » (`text-textTertiary underline`, cible ≥ 48 px de haut),
  vers `/pro/rendez-vous/{id}`. Pour tous les rôles (un Collaborateur ne voit
  que ses rendez-vous, et sa fiche s'ouvre).
  **Q2 — le retour** : la Journée garde son jour dans l'état React, pas dans
  l'URL (`RendezVousClient.tsx:57`). Depuis la fiche, « ← Rendez-vous » ou le
  bouton Précédent ramène donc **à aujourd'hui**, pas au jour qu'on regardait.
  Recommandé : l'accepter dans cette tranche (le panneau porte désormais tout
  ce qu'il faut pour accepter ou refuser — le détour par la fiche devient
  rare) et faire « le jour dans l'URL » en tranche suivante (§9).

### 2.2 « Non présenté » — dans le panneau **et** sur la fiche

- **Proposé seulement une fois l'heure de début passée** (`appointmentDate ≤
  maintenant` — deux instants, indépendants du fuseau), comme la fiche de
  l'app. Avant, le bouton n'est pas là (pas grisé : l'app le cache aussi).
- **Toujours confirmé**, au même endroit qu'aujourd'hui sur la fiche web : un
  encadré à la place du bouton (pas une modale — le panneau est déjà un
  dialogue non modal, et la fiche fait déjà ainsi) :

  ```
  ┌─────────────────────────────────────────────┐
  │ Client absent ?                             │
  │ Le client ne s'est pas présenté.            │
  │ L'acompte est conservé selon votre          │  ← seulement si depositAmount > 0
  │ politique d'annulation.                     │
  │ [Annuler]  [Marquer absent]                 │
  └─────────────────────────────────────────────┘
  ```

  Le texte est celui du dialogue de l'app (`:357-368`), mot pour mot, avec une
  seule différence : la phrase sur l'acompte n'apparaît **que s'il y a un
  acompte** (l'app la dit à tous, y compris sans acompte). « Marquer absent »
  n'est pas rouge (SYSTEM.md §15 : le rouge est pour la destruction ; l'app
  fait de même, `isDestructive: false`).
- Les libellés des boutons ne changent pas : « Non présenté » dans le panneau
  (le mot de « Ma journée »), « Marquer comme absent » sur la fiche (le mot de
  la fiche de l'app).

### 2.3 La fiche `/pro/rendez-vous/{id}` — alignée

- La capture **se charge d'elle-même** (le même composant que le panneau, §5) :
  plus de bouton « Voir le justificatif », plus d'échec muet.
- La consigne, aux mêmes conditions que dans le panneau (Q1).
- Sans capture : « Aucune capture jointe pour le moment. » remplace
  « Justificatif d'acompte non reçu. ».
- Un Collaborateur : comme dans le panneau, ni consigne ni capture.
- « Marquer comme absent » : §2.2.

### 2.4 La CSP

`https://*.r2.cloudflarestorage.com` entre dans `img-src`, avec sa ligne dans
la table `RUNTIME_ONLY` de `csp.test.ts` (« l'URL de la capture est signée par
l'API — jamais un littéral du dépôt »). Rien d'autre ne change dans la
politique.

## 3. Le texte — à valider mot pour mot

| # | Où | Texte | D'où il vient |
|---|---|---|---|
| T1 | panneau + fiche, ligne | **Acompte annoncé** | déjà sur la fiche web ; l'app |
| T2 | panneau + fiche, consigne | **Confirmez le rendez-vous une fois l'acompte reçu sur votre compte Mobile Money.** | l'app, mot pour mot |
| T3 | panneau + fiche, sans capture | **Aucune capture jointe pour le moment.** | l'app, mot pour mot (remplace « Justificatif d'acompte non reçu. » sur la fiche) |
| T4 | bouton autour de la vignette (nom accessible) | **Agrandir le justificatif d'acompte** | nouveau |
| T5 | la Lightbox (nom du dialogue) + `alt` de l'image | **Justificatif d'acompte** | déjà sur la fiche web |
| T6 | échec, coupure | **Pas de connexion. Réessayez.** | `NO_CONNECTION_MESSAGE` (#629) |
| T7 | échec, autre | **Capture indisponible. Réessayez.** | l'app dit « Capture indisponible. Réessayez plus tard. » ; ici il y a un bouton, d'où « Réessayez. » (la forme de toutes les erreurs web : phrase + « Réessayer ») |
| T8 | bouton d'échec | **Réessayer** | `ErrorState` |
| T9 | panneau, lien | **Voir le rendez-vous** | nouveau (pendant de « Voir la fiche ») |
| T10 | confirmation absent, titre | **Client absent ?** | l'app, mot pour mot |
| T11 | confirmation absent, phrase | **Le client ne s'est pas présenté.** | l'app, mot pour mot (remplace « Le client ne s'est pas présenté ? » sur la fiche web) |
| T12 | confirmation absent, si acompte | **L'acompte est conservé selon votre politique d'annulation.** | l'app, mot pour mot — juste en sans-custody : c'est le salon qui a reçu l'acompte et qui le garde ; MyWeli n'y touche pas |
| T13 | confirmation absent, boutons | **Annuler** · **Marquer absent** | l'app (« Confirmer » sur la fiche web aujourd'hui) |

Apostrophes typographiques (’) dans le code, comme le reste de l'interface.
Aucun de ces textes ne parle de paiement en ligne (#639, l'épingle
`promise-honesty-pin.test.ts`).

## 4. États et cas limites

- **Les quatre états** de la capture : chargement (squelette), vide (T3),
  erreur (T6/T7 + T8), succès (vignette). Le reste du panneau n'attend pas la
  capture : les faits et les boutons s'affichent tout de suite.
- **Changement de bloc** pendant un chargement : le panneau est remonté sur le
  nouveau rendez-vous (`appt.id`) ; une réponse arrivée pour l'ancien est
  ignorée (le drapeau `active` du `useEffect`, le motif de la mini-fiche).
- **Le panneau se repeint** après un rafraîchissement de la Journée (il lit
  le rendez-vous à jour, pas une copie — `pro.spec.ts:425-435`) : la capture n'est pas
  redemandée tant que `appt.id` et `depositScreenshotUrl` ne changent pas.
- **Une capture jointe pendant que le panneau est ouvert** : visible au
  prochain rafraîchissement de la Journée (comme aujourd'hui pour le statut).
- **« Non présenté » qui devient disponible** pendant que le panneau est ouvert
  (l'heure passe) : visible au prochain rendu — pas de minuterie. Le serveur
  ne vérifie pas l'heure (§1) : la garde est côté client, comme dans l'app.
- **Un client arrivé** (« Client arrivé » enregistré) reste « Non présenté »
  possible une fois l'heure passée, comme dans l'app — voir §9.
- **Texte à 200 %, 320 px** : la vignette est de taille fixe en hauteur et
  `max-w-full` en largeur ; les phrases passent à la ligne ; le panneau défile
  (`overflow-auto`, déjà là).
- **Lecteur d'écran** : la zone de la capture est une région polie qui existe
  dès l'ouverture (WEB-SYSTEM §7 : la région précède son texte), donc T6/T7
  sont annoncés ; le squelette est `aria-hidden`.

## 5. Architecture

- **`lib/api/pro.ts`** — `proDepositScreenshotUrl(id)` rend
  `{ status: number; url?: string }` (la forme des autres lectures : statut 0
  quand rien d'utilisable ne revient, un 2xx sans `url` compris). Sa ligne dans
  `pro-api-network.test.ts` passe de `url` à `read`. Seul appelant aujourd'hui :
  la fiche.
- **`components/pro/ProDepositProof.tsx`** (nouveau) — la ligne n'y est pas ;
  le composant porte la consigne, la capture et ses états, la Lightbox.
  Props : `appointmentId`, `hasProof`, `pending` (pour Q1), `canView`
  (`journal.view.all`). Utilisé par le panneau et par la fiche — un seul
  endroit pour le texte et les états.
- **`lib/pro/lifecycle.ts`** — `hasStarted(appointmentDate, now)` (pur) ;
  `actionsFor` / `actionsForMembership` prennent `{ started }` et n'offrent
  `no-show` que si `started` ; le texte de confirmation (T10–T13) y vit, avec
  la phrase d'acompte selon `depositAmount`. Le panneau lit les mêmes
  définitions pour « Non présenté » (sa confirmation est la même).
- **`next.config.mjs`** — `img-src` (§2.4).
- **Aucun changement serveur, aucun changement de contrat** (`openapi.yaml`) :
  `depositAmount`, `depositScreenshotUrl` et `GET
  /appointments/{id}/deposit-screenshot` existent déjà et sont déjà typés.

## 6. Sécurité

- La capture reste privée : le web ne voit qu'une URL signée de 5 min, demandée
  par le BFF Pro (cookie httpOnly) — rien n'est stocké côté navigateur.
- Aucune requête de capture pour un membre sans `journal.view.all` (le serveur
  la refuserait de toute façon — T40 / module `access` R1).
- `img-src` s'élargit à un seul hôte, déjà autorisé en `connect-src`, et
  l'objet n'est lisible qu'avec la signature.

## 7. Performance

Une requête de plus (l'URL signée) et une image, **seulement** à l'ouverture
d'un panneau dont le rendez-vous a une capture. La vignette est affichée à
144 px de haut ; l'image source est celle que le client a envoyée (la même
que la fiche affiche aujourd'hui).

## 8. Tests — vus rouges d'abord

- **RTL, panneau** (`pro-journal-panel-deposit.test.tsx`, nouveau) : la ligne
  « Acompte annoncé » ; T2 en attente seulement ; la vignette se charge sans
  clic ; T3 sans capture ; T6 sur une coupure, T7 sur un 404/5xx et sur une
  image qui ne se charge pas, « Réessayer » redemande une URL ; aucune requête
  pour un Collaborateur ; le lien T9 vers `/pro/rendez-vous/{id}` ; « Non
  présenté » absent avant l'heure, présent après, et **aucun appel
  `no-show` sans « Marquer absent »** ; T12 seulement avec un acompte.
- **RTL, fiche** (`pro-appointment-detail-deposit.test.tsx`, nouveau) : la
  capture sans clic ; l'échec n'est plus muet ; T3 ; « Marquer comme absent »
  absent sur un rendez-vous futur.
- **Unitaires** : `pro-lifecycle.test.ts` (`hasStarted`, `no-show` seulement
  si `started`) ; `pro-api-network.test.ts` (la nouvelle forme) ;
  `csp.test.ts` (R2 dans `img-src`).
- **e2e** : le bouchon gagne un rendez-vous du jour **en attente, avec acompte
  et capture** dans la Journée ; `pro.spec.ts` ouvre son panneau et voit la
  ligne, la vignette et le lien ; `axe.spec.ts` gagne un **scan d'état** du
  panneau ouvert avec la capture (un panneau n'existe qu'après un clic — un
  parcours de routes ne le voit jamais) ; `type-overflow.spec.ts` gagne une
  entrée « le panneau Journée avec acompte » à 375×812, 320×512, 320×256.
- Chaque nouveau test est **vu rouge sur `main`** avant le correctif, et le
  rouge est consigné dans la PR.

## 9. Hors périmètre — vu en passant

- **Le jour de la Journée dans l'URL** (Q2), pour que le retour de la fiche
  ramène au même jour.
- **L'app** : « Ma journée », appui long, propose « Non présenté » sur tout
  rendez-vous confirmé, sans confirmation ni condition d'heure
  (`pro_journal_screen.dart:416-420`) — l'écart que ce spec ferme côté web
  existe aussi dans l'app. Et sa fiche affiche « Capture indisponible » à un
  Collaborateur (§1, fait 1).
- **Le serveur** ne vérifie pas l'heure d'un `no-show` (§1).
- **La grille** : le « ₣ » n'est pas dans le nom accessible du bloc
  (`JournalGrid.tsx:353`) — un lecteur d'écran n'apprend pas qu'il y a un
  acompte.
- **« Non présenté » après « Client arrivé »** : possible dans l'app comme ici.

## 10. Questions au propriétaire — tranchées le 2026-10-19

Réponse : « Approved: text T1–T13 word for word, Q1 = guidance only while
pending, Q2 = back to today for now, day in the URL as a follow-up. »


- **Q1** — la consigne T2 : **seulement en attente** (recommandé) ou toujours
  (l'app) ?
- **Q2** — le retour depuis la fiche ramène à aujourd'hui : **accepté pour
  cette tranche, le jour dans l'URL ensuite** (recommandé), ou dans cette
  tranche ?
- **Le texte T1–T13** (§3), mot pour mot.

## 11. Ce qui a été vu

- **Rouge d'abord** : 37 tests unitaires/RTL rouges sur `main` (commit des
  tests seuls), chacun pour la bonne raison (texte absent, bouton présent avant
  l'heure, hôte absent d'`img-src`, `null` au lieu d'un statut).
- **Mutations, chacune vue rouge puis annulée** : la garde Collaborateur
  levée ; la consigne montrée à tout statut ; la région polie retirée ;
  « Réessayer » qui réutilise l'URL ; la phrase d'acompte toujours dite ; le
  focus de la confirmation retiré.
- **Unitaires** : typecheck et lint propres, toute la suite web verte.
- **e2e** (`pro`, `axe`, `type-overflow`, `tap-targets`, `roles`, `z-layers`,
  `account`) : 128 verts, sur un port à part (le 3000 de la machine était pris
  par un autre projet). La vignette est **décodée** (`naturalWidth > 0`), le ✕
  de la capture agrandie est **celui qu'on touche** (test de visée — la
  Lightbox vit dans le panneau, sans portail), Échap ne ferme qu'elle et rend
  le focus à la vignette.
- **L'épingle d'heure de `roles.spec`** : passée à 08:00, « Marquer comme
  absent » disparaît et le test échoue — la garde marche dans un vrai
  navigateur, et sans l'épingle ce test serait rouge avant 09:00 UTC.
- **Pas vu** : le Report-Only de la CSP en production (aucun salon réel n'a
  encore de capture) ; l'écran à 200 % de texte dans un navigateur (couvert par
  la matrice de reflow à 320 px, pas par un zoom réel).
