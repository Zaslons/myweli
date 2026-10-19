# Pro web — l'agenda garde sa vue et son jour dans l'adresse : revenir d'un rendez-vous ramène là où on était — spec

| | |
|---|---|
| **Statut** | **Brouillon — en attente de la validation du propriétaire** (UX, et les mots de l'adresse, §3 et §9) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-19 |
| **PRD ref / phase** | La parité web ↔ app Pro (le web suit le parcours de l'app, écran par écran) · V1 — tableau de bord Pro web |
| **Module** | web Pro — `/pro/rendez-vous` (`RendezVousClient` : Journée, Calendrier, Liste) et la fiche `/pro/rendez-vous/{id}` (« ← Rendez-vous ») |
| **Source** | Décision **Q2** de [web-pro-journal-panel-deposit.md](web-pro-journal-panel-deposit.md) (2026-10-19) : « le retour depuis la fiche ramène à aujourd'hui pour l'instant, le jour dans l'URL en tranche suivante » |
| **Dépend de** | [#644](https://github.com/Zaslons/myweli/pull/644) (le lien « Voir le rendez-vous » du panneau) — cette branche part de la sienne |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · aucun changement serveur, aucun contrat |

## 1. Le constat — relu sur le vrai chemin de code

L'agenda (`RendezVousClient.tsx`) garde tout ce qu'on regarde dans l'état
React, rien dans l'adresse :

- la vue — Journée / Calendrier / Liste (`:54`, `'journal'` au départ) ;
- le jour de la Journée (`journalDate`, `:57`, remis à « aujourd'hui » du
  salon au chargement, `:85`) ;
- le jour choisi du Calendrier (`selected`, `:61`, idem `:86`) ;
- l'onglet de la Liste (`listTab`, `:62`, « Aujourd'hui » au départ).

Or **chaque chemin vers une fiche quitte la page** : « Voir le rendez-vous »
du panneau (#644), une ligne du Calendrier, une ligne de la Liste
(`ProAppointmentRow`, `href=/pro/rendez-vous/{id}`). Au retour —
« ← Rendez-vous » de la fiche (`ProAppointmentDetailClient.tsx:177,209`) ou
le bouton Précédent du navigateur — la page est remontée et **tout repart de
zéro : Journée, aujourd'hui**. Un salon qui regardait mardi prochain, ou ses
demandes « En attente », doit tout refaire. Un rechargement fait pareil, et
l'adresse ne peut pas être partagée avec la réception.

**L'app** garde le jour : `ProJournalProvider` vit toute la session
(`_selectedDate`, `pro_journal_provider.dart:44`), la fiche est poussée par
dessus (`context.push('/pro/appointment/{id}')`) et le retour la dépile —
on retrouve la journée telle qu'on l'a laissée. Le provider ne remet le jour
à aujourd'hui qu'au **premier** chargement (`:126-132`).

## 2. Ce qu'on construit

### 2.1 L'adresse dit ce qu'on regarde

| On regarde | L'adresse |
|---|---|
| Journée, aujourd'hui | `/pro/rendez-vous` |
| Journée, le 25 octobre | `/pro/rendez-vous?jour=2026-10-25` |
| Calendrier, aujourd'hui choisi | `/pro/rendez-vous?vue=calendrier` |
| Calendrier, le 25 octobre choisi | `/pro/rendez-vous?vue=calendrier&jour=2026-10-25` |
| Liste, « Aujourd'hui » | `/pro/rendez-vous?vue=liste` |
| Liste, « En attente » | `/pro/rendez-vous?vue=liste&filtre=en-attente` |

- **Les valeurs par défaut ne s'écrivent pas** : Journée, aujourd'hui,
  l'onglet « Aujourd'hui ». Ainsi `/pro/rendez-vous` reste l'adresse de
  « maintenant », et une adresse gardée n'épingle jamais « aujourd'hui » à une
  date qui passera.
- `jour` est un **jour du salon** (`AAAA-MM-JJ` dans le fuseau du salon, la
  même clé que la Journée utilise déjà) ; « aujourd'hui » est celui du salon.
- `filtre` : `aujourdhui` · `a-venir` · `en-attente` · `tous` (les quatre
  onglets de la Liste).
- **Chaque changement remplace l'adresse, sans ajouter d'entrée à
  l'historique** : ‹ / › / « Aujourd'hui » / le champ date / ← → T, un clic
  dans le Calendrier, un onglet. Sinon Précédent devrait remonter jour par
  jour avant de quitter la page. Aucun aller-retour serveur : l'adresse change
  sans recharger (l'API d'historique du navigateur, que Next 14.2 suit).
- **Une adresse fausse ne casse rien** : `jour=2026-02-30`, `jour=demain`,
  `vue=semaine`, `filtre=x` → la valeur par défaut, en silence ; l'adresse est
  réécrite propre au premier changement.

### 2.2 Aller à une fiche et revenir

- Les liens de l'agenda vers une fiche **emportent la vue et le jour** :
  `/pro/rendez-vous/{id}?jour=2026-10-25` (panneau, lignes du Calendrier et
  de la Liste).
- **« ← Rendez-vous » de la fiche rend ces mêmes paramètres** :
  `/pro/rendez-vous?jour=2026-10-25` — y compris sur « Rendez-vous
  introuvable. ». La fiche ne transmet que `vue`, `jour`, `filtre`, validés ;
  rien d'autre (pas de `salon`, pas d'adresse arbitraire : le lien reste
  `/pro/rendez-vous`).
- **Précédent** du navigateur ramène à la même adresse, donc au même jour.
- **Recharger** l'agenda garde la vue et le jour.

### 2.3 Ce qui reste comme aujourd'hui

- **« Rendez-vous » dans le menu ouvre la Journée d'aujourd'hui** (Q2 :
  recommandé) — c'est l'adresse nue. L'app, elle, retrouve le dernier jour
  vu tant que la session dure ; sur le web, un lien de menu qui ramène à
  « maintenant » est ce qu'on attend, et « Précédent » couvre le retour.
- Une fiche ouverte depuis ailleurs (Accueil, fiche client, Revenus, une
  notification) n'a pas de paramètres : « ← Rendez-vous » mène à la Journée
  d'aujourd'hui, comme maintenant.
- Le Calendrier et la Journée gardent chacun leur jour (pas de jour commun
  aux deux vues : ce serait un autre changement).
- Aucun texte de l'interface ne change.

## 3. Les mots de l'adresse — à valider

| Paramètre | Valeurs | Pourquoi |
|---|---|---|
| `vue` | `calendrier` · `liste` (Journée = absent) | les noms des onglets, sans accent ni majuscule |
| `jour` | `AAAA-MM-JJ` | la forme du champ date, et celle de l'API Journée |
| `filtre` | `aujourdhui` · `a-venir` · `en-attente` (« Aujourd'hui » = absent) · `tous` | les noms des onglets de la Liste |

En français comme les chemins (`/pro/rendez-vous`, `/mon-compte`,
`/recherche?commune=`). L'espace Pro n'est pas indexé (`robots: noindex`) :
aucun effet SEO.

## 4. États et cas limites

- **Avant `/me`** la page est en squelette ; l'adresse est lue **après** le
  chargement du salon (il faut son fuseau pour savoir ce qu'est
  « aujourd'hui ») — pas de flash d'aujourd'hui puis du bon jour.
- **Changement de salon** (le sélecteur) : la page est remontée et relit
  l'adresse — le nouveau salon s'ouvre sur le même jour et la même vue.
- **Collaborateur** : même chose ; sa Journée est la sienne (le serveur filtre).
- **Rendu serveur** : rien n'est lu de l'adresse côté serveur (la page est un
  client) — pas de décalage d'hydratation.
- **Une adresse d'un autre fuseau** (partagée entre deux salons) : `jour` est
  un jour calendaire, lu dans le fuseau du salon actif — c'est le sens voulu.

## 5. Architecture

- **`lib/pro/agenda-url.ts`** (nouveau, pur, testé) :
  `readAgenda(search, today)` → `{ view, journalDate, selected, listTab }` avec
  les défauts et la validation ; `agendaQuery(state, today)` → la chaîne
  (`""` ou `?…`), sans les défauts ; `agendaParams(search)` → les seuls
  `vue`/`jour`/`filtre` valides, pour la fiche.
- **`RendezVousClient`** : lit `window.location.search` dans l'effet de
  chargement (après `/me`) ; écrit par `window.history.replaceState` à chaque
  changement d'état (un effet sur `view`/`journalDate`/`selected`/`listTab`).
  Passe la requête courante aux liens vers les fiches (`ProAppointmentRow`,
  `JournalGrid` → `JournalPanel`).
- **`ProAppointmentDetailClient`** : lit les paramètres de l'agenda dans
  l'adresse et les rend à « ← Rendez-vous ».
- Aucun changement serveur, aucun contrat.

## 6. Sécurité

L'adresse ne porte que des valeurs d'affichage, validées contre des listes
fermées ou un format de date ; le lien de retour est toujours construit
(`/pro/rendez-vous` + paramètres validés), jamais recopié — pas de redirection
ouverte. Rien de personnel dans l'adresse (pas de client, pas de téléphone).

## 7. Performance

Aucune requête de plus : remplacer l'adresse ne recharge rien. La lecture de
l'adresse remplace la remise à « aujourd'hui » qui existe déjà.

## 8. Tests — vus rouges d'abord

- **Unitaires** (`pro-agenda-url.test.ts`) : lecture (chaque vue, chaque
  filtre, les défauts, les dates impossibles, les valeurs inconnues), écriture
  (les défauts omis, l'ordre stable), l'aller-retour lecture → écriture.
- **RTL** (`RendezVousClient`) : `?jour=` ouvre ce jour (la requête Journée
  part pour cette date) ; › réécrit l'adresse **sans** entrée d'historique ;
  revenir à aujourd'hui rend l'adresse nue ; `?vue=liste&filtre=en-attente`
  ouvre l'onglet ; une adresse fausse ouvre aujourd'hui ; les liens des lignes
  emportent la requête.
- **RTL** (fiche) : « ← Rendez-vous » rend `vue`/`jour`/`filtre`, ignore le
  reste et les valeurs fausses ; idem sur « Rendez-vous introuvable. ».
- **e2e** (`pro.spec.ts`) : Journée → › → bloc → « Voir le rendez-vous » →
  Précédent → **le même jour** ; Liste → « Tous » → une ligne → « ← Rendez-vous »
  → **Liste, « Tous »** ; un rechargement garde le jour.

## 9. Questions au propriétaire

- **Q1** — les mots de l'adresse (§3) : `vue` / `jour` / `filtre`, valeurs en
  français sans accents (recommandé) ?
- **Q2** — « Rendez-vous » dans le menu ouvre **la Journée d'aujourd'hui**
  (recommandé), ou le dernier jour vu comme l'app ?
