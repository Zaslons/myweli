# Pro web — sur une coupure, l'erreur dit « Pas de connexion » — spec

| | |
|---|---|
| **Statut** | **Brouillon, 2026-10-16** — la suite de [web-pro-network-failure.md](web-pro-network-failure.md) §9 (« le mot de l'app »). Le sélecteur de salon : §5, question ouverte |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | Les quatre états de chaque page (SYSTEM.md §12, WEB-SYSTEM §12) · la parité web ↔ app · V1 — tableau de bord Pro web |
| **Module** | web Pro — l'état d'erreur de chargement des 16 pages, la section Journée, le sélecteur de salon |
| **ROADMAP entry** | [2026-10-16-pro-no-connection-copy.md](../roadmap/entries/2026-10-16-pro-no-connection-copy.md) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ (aucun changement serveur, aucun contrat) · myweli-verification-guardrails (avant de dire « fait ») |
| **Dépend de** | [#619](https://github.com/Zaslons/myweli/pull/619) (les wrappers de `lib/api/pro.ts` rendent le statut 0 quand rien ne répond), lui-même après [#616](https://github.com/Zaslons/myweli/pull/616) |

## 1. Le constat

Après #619, une coupure réseau ne laisse plus aucune page Pro sur son
squelette : chaque lecture qui n'obtient pas de réponse rend le **statut 0**,
et la branche « pas 200 » de la page affiche son `ErrorState` avec
« Réessayer ». Mais la phrase ne dit pas pourquoi :

- 12 pages : la phrase par défaut du composant partagé, « Une erreur est
  survenue. Réessayez. » ;
- 4 pages, leur propre phrase : « Impossible de charger les avis. » (Avis),
  « Chargement impossible. » (Revenus, Vérification), « Impossible de charger
  l'aperçu. » (Aperçu du salon) ;
- la Journée (section de `/pro/rendez-vous`) : la phrase par défaut ;
- le sélecteur de salon : « Changement impossible — votre accès à ce salon a
  peut-être été retiré. » — sur une coupure, la phrase soupçonne un accès
  retiré qui n'y est pour rien.

**L'app** nomme le réseau : quand la requête n'a pas de réponse, le service
rend une erreur qui le dit, et l'écran montre ce texte dans son état d'erreur
(`client_list_screen.dart` `description: clients.error`,
`pro_journal_screen.dart` `description: journal.error`, les avis et les
revenus par `res.error`). Sur un 5xx, elle dit autre chose (le message du
code d'erreur, ou « Erreur… »).

**Vu en relisant : l'app a deux phrases pour ce même cas.** La plupart des
services (`api_pro_clients_service`, `_team_`, `_kyc_`, `_subscription_`,
`_artist_`, `api_review_service`, …) disent « Pas de connexion. Réessayez. » ;
les plus anciens (`api_pro_service` — `/me`, la Journée, le changement de
salon —, `api_auth_service`, `api_appointment_service`) disent « Connexion
au serveur impossible ». Le web n'en prend **qu'une** : « Pas de connexion.
Réessayez. », celle qu'il dit déjà à deux endroits par le statut 0 — la carte
d'invitations et la connexion Pro (#619 §3) — `NO_CONNECTION_MESSAGE`
(`lib/pro/team.ts`). Ce qui compte pour la parité est que les deux nomment
le réseau ; aligner l'app sur une seule phrase est consigné (§9).

**Ce que le statut 0 veut dire ici** : le lien navigateur → BFF n'a rien
rendu d'utilisable — pas de réseau, une connexion coupée au milieu du corps,
un 2xx illisible (WEB.md §3, « a browser → BFF wrapper never throws »). Quand
c'est l'API qui ne répond pas au BFF, le BFF répond un 5xx (son `fetch`
côté serveur lève, la route rend 500) : la connexion de la personne marche,
et ce n'est **pas** « Pas de connexion ». Le statut 0 est donc exactement le
cas de l'app (`res == null`).

## 2. Décision : la page garde *pourquoi* sa lecture a échoué

L'état d'erreur de chaque page est aujourd'hui un booléen (`error`,
`loadError`, `journalError`). Il devient **la raison de l'échec** :

```ts
// lib/pro/load-failure.ts
export type LoadFailure = 'offline' | 'failed';
export function loadFailure(...statuses: number[]): LoadFailure;     // 0 parmi eux → 'offline'
export function loadFailureMessage(f: LoadFailure, message?: string): string | undefined;
//   'offline' → NO_CONNECTION_MESSAGE ; 'failed' → message (undefined = la phrase par défaut d'ErrorState)
```

- Le même vocabulaire que `logoutPro` (`'offline' | 'failed'`,
  `logoutErrorMessage`) : la session distingue déjà ces deux cas.
- Dans chaque page : `useState<LoadFailure | false>(false)`. `false` reste
  « pas d'erreur », chaque `setError(false)` et chaque `if (error)` restent
  tels quels ; seuls les `setError(true)` changent, en
  `setError(loadFailure(<les statuts des lectures qui viennent d'échouer>))`.
  **Le compilateur trouve chacun** : `true` n'est plus du type — aucun site
  oublié. Une chaîne est vraie, donc pas le piège d'un statut 0 « faux ».
- L'`ErrorState` reçoit `message={loadFailureMessage(error, <la phrase de la
  page>)}`. Pour les 12 pages sans phrase propre, `undefined` sur un 5xx →
  la valeur par défaut du composant, qui **ne change pas** — ni son texte, ni
  sa signature, ni ses autres appelants (le web client, `DataTable`).
- **Plusieurs lectures** (Aujourd'hui et Rendez-vous : `/me` + rendez-vous ;
  Vérification : `/me` + KYC) : `loadFailure(me.status, appts.status)` —
  si l'une d'elles n'a rien reçu, c'est la connexion. Un statut 200 parmi
  eux ne compte pas (il n'est pas 0).
- **Un 200 sans la donnée attendue** (`me.status === 200 && !me.profile`) :
  depuis #619 un corps illisible est déjà le statut 0 ; un 200 lisible sans
  profil est une réponse du serveur → `'failed'`, la phrase générique.

**Écartés** :
- *Un booléen `offline` à côté de l'erreur* — deux états à tenir ensemble à
  chaque échec ; le compilateur n'en voit pas l'oubli.
- *Garder le statut lui-même* (`number | null`) — 0 est faux en JS : un
  `if (error)` le lirait comme « pas d'erreur » et la page s'afficherait
  vide. Chaque `setError(false)` changerait aussi.
- *Une prop `offline` sur `ErrorState`* — le composant partagé (web client
  compris) apprendrait le vocabulaire Pro (`lib/pro/team.ts`) ; la consigne
  est de ne pas toucher sa valeur par défaut pour les autres échecs.

## 3. Les sites — les 16 pages et la Journée

| Page | Composant | Échec de chargement | Phrase sur un 5xx (inchangée) |
|---|---|---|---|
| Disponibilités | `DisponibilitesClient` | `/me` | défaut |
| Profil | `ProfilClient` | `/me` | défaut |
| Médias | `MediasClient` | `/me` | défaut |
| Mon abonnement | `AbonnementClient` | `/me` ; abonnement (≠ 404) | défaut |
| Catalogue | `CatalogueClient` | `/me` | défaut |
| Fiche client | `ClientCardClient` | `/me` ; fiche (≠ 404) | défaut |
| Clients | `ClientsClient` | `/me` ; liste (arrivée, recherche, filtre, « Charger plus ») | défaut |
| Équipe | `EquipeClient` | `/me` ; membres | défaut |
| Rendez-vous | `RendezVousClient` | `/me` + rendez-vous | défaut |
| Aujourd'hui | `AujourdhuiClient` | `/me` + rendez-vous | défaut |
| Avis | `AvisClient` | `/me` ; avis | « Impossible de charger les avis. » |
| Revenus | `RevenusClient` | `/me` ; la période | « Chargement impossible. » |
| Vérification | `VerificationClient` | `/me` + KYC | « Chargement impossible. » |
| Aperçu du salon | `SalonPreviewClient` | `/me` | « Impossible de charger l'aperçu. » |
| Détail d'un rendez-vous | `ProAppointmentDetailClient` | `/me` ; rendez-vous (≠ 404) | défaut |
| Acompte | `AcompteClient` | `/me` ; la politique (après #616) | défaut |
| **Journée** (section) | `RendezVousClient` `loadJournal` | le jour (≠ 200, ≠ 401) | défaut |

Sur le statut 0, toutes disent « Pas de connexion. Réessayez. » — **y compris
les quatre pages à phrase propre** : leur phrase ne dit pas la cause, et
l'app, sur ces écrans-là, dit le réseau (les avis et les revenus par
`res.error` ; l'aperçu et la KYC disent « Vérifiez votre connexion et
réessayez. » pour tout échec — le web, lui, ne le dit que quand c'est vrai).

**Inchangés** : les 401 (→ la connexion), les 404-états (pas encore d'offre,
fiche introuvable, rendez-vous absent), « Réessayer » et ce qu'il recharge,
le h1 de chaque page dans l'état d'erreur.

## 4. UX et texte

Aucun composant, aucun jeton, aucune phrase nouvelle : « Pas de connexion.
Réessayez. » est celle de l'app, déjà `NO_CONNECTION_MESSAGE`. Même place
(le `role="alert"` de l'`ErrorState`), même « Réessayer ». Accessibilité
inchangée : l'alerte est annoncée comme avant, avec un texte plus juste.

## 5. Le sélecteur de salon — question ouverte

`ProSidebar.pick` → `switchSalon` (`ProMembershipContext`) →
`selectSalon`. `switchSalon` rend un booléen : tout échec, une coupure
comprise, affiche « Changement impossible — votre accès à ce salon a
peut-être été retiré. ».

**Constat en lisant l'app** : `ProAuthProvider.switchSalon` rend aussi un
booléen (`catch (_) → false`), et `salon_picker_sheet.dart` dit **la même
phrase** pour tout échec, réseau compris. Ici, pas d'écart de parité : le
changer côté web seul mettrait le web en avance sur l'app.

Options (posée à la session qui a ouvert la tâche) :

- **A (recommandée)** — les deux côtés : `switchSalon` dit pourquoi
  (`'switched' | LoadFailure`) ; la phrase devient « Pas de connexion.
  Réessayez. » sur le statut 0 — et sur un 2xx dont le profil s'est perdu
  (#619 §2 : une écriture reste `ok` sans sa charge utile ; rien d'utilisable
  n'est revenu, et un nouvel essai est sans danger, la sélection est
  idempotente) ; le reste garde la phrase d'aujourd'hui. Côté app :
  `switchSalon` rend la raison, la feuille choisit la phrase, un test de
  widget.
- **B** — le web seul, l'app consignée comme suite.
- **C** — ne rien changer au sélecteur (la parité tient déjà).

## 6. Contrat, sécurité, performance

Aucun changement d'API, de contrat, de serveur ni de BFF. Sécurité : rien ne
bouge — un 401 reste un 401, aucune donnée nouvelle n'est affichée.
Performance : nulle.

## 7. Tests (rouges d'abord)

- **`tests/pro-network-pages.test.tsx`** (les 16 pages) : les cas « tout
  rejette » et « `/me` répond, la lecture propre rejette » attendent
  désormais « Pas de connexion. Réessayez. » ; **une nouvelle table 5xx** —
  tout répond 500, puis `/me` 200 et la lecture propre 500 — attend la phrase
  d'aujourd'hui (celle de la page, ou le défaut). C'est elle qui garde « ne
  pas toucher le défaut » : une page qui dirait « Pas de connexion » sur un
  500 tombe rouge.
- **`tests/pro-journal-error.test.tsx`** : le 500 → la phrase par défaut ; la
  coupure et le changement de jour coupé → « Pas de connexion. Réessayez. ».
- **Clients, « Charger plus » / la recherche** et **Revenus, une période
  choisie** passent par le même état — un cas chacun, coupé après une
  arrivée réussie.
- **`lib/pro/load-failure.ts`** : la table de `loadFailure` /
  `loadFailureMessage` (0 seul, 0 parmi des 200, 500, 404 ; avec et sans
  phrase propre).
- **Le sélecteur** (selon §5) : coupure → « Pas de connexion. Réessayez. » ;
  403 → la phrase d'aujourd'hui.

**Mutations à voir rouges** : `loadFailure` qui ne voit plus le 0 ;
`loadFailureMessage` qui rend toujours `NO_CONNECTION_MESSAGE` (la table 5xx) ;
une page qui revient à `message` sans `loadFailureMessage` ; la Journée sans
la raison ; une page qui garde sa phrase propre sur une coupure.

## 8. Déploiement

Web au merge (Vercel), **après #619** (sans lui, une coupure lève encore et
aucune page n'atteint son état d'erreur). Rien côté serveur.

## 9. Hors périmètre, consigné

- **Les enregistrements** : leurs phrases d'échec (« L'enregistrement a
  échoué. Réessayez. », …) restent génériques ; elles sont vraies sur une
  coupure (#619 §3). Les faire dire « Pas de connexion » est une autre tâche,
  écran par écran.
- **Le web client** (`lib/api/account.ts`) : sa propre tâche (en cours dans
  une autre session) ; il pourra reprendre `loadFailure` si la même question
  s'y pose.
- **Les lectures secondaires silencieuses** (#619 §3) : silencieuses sur une
  coupure comme sur un 5xx.
- **Les deux phrases de l'app** (§1) : « Connexion au serveur impossible »
  (`api_pro_service`, `api_auth_service`, `api_appointment_service`,
  `api_provider_service`) et « Pas de connexion. Réessayez. » (les autres).
  Les aligner sur une seule est une tâche de l'app.
