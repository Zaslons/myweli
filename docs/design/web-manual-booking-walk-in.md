# Web Pro — réservation manuelle : « Client sans numéro », le nom facultatif, comme l'app — spec

| | |
|---|---|
| **Statut** | **Validé le 2026-10-20** — Q1 = **(a) comme l'app** : téléphone obligatoire pour un nouveau client sauf « Client sans numéro », le nom facultatif (§6) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-20 |
| **PRD ref / phase** | FR-APPT-008 (réservation saisie par le salon) · parité web ↔ app Pro · V1 |
| **Module** | web Pro — `ManualBookingDialog` (ses trois portes : « + Nouveau rendez-vous », la grille de la Journée, la fiche client), `lib/pro/manual-booking.ts` |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §4 (P2) : « le web exige un nom, pas de « Client sans numéro » (`manual-booking.ts:41-52`, même commentaire faux) » |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · aucun changement serveur |

## 1. Le constat — relu sur le vrai chemin de code

- **L'app** (`pro_manual_booking_screen.dart:221,336-371`) : « Téléphone du
  client » **obligatoire** (« Saisissez un numéro de téléphone. »), sauf si
  la case **« Client sans numéro »** est cochée — elle désactive le champ ;
  « Nom du client (optionnel) ». Un client de passage dont on ne sait rien se
  réserve donc en deux gestes.
- **Le web** (`ManualBookingDialog.tsx`, `manual-booking.ts:41-52`) : le
  champ « Client (nom ou téléphone)… » cherche dans la clientèle **ou** nomme
  un nouveau client ; « Créer » reste grisé **tant qu'aucun nom n'est
  tapé** ; le téléphone est **facultatif**. Le commentaire dit « mirroring
  the app » — c'est l'inverse : le web exige ce que l'app laisse libre, et
  laisse libre ce que l'app exige.
- **Le serveur** accepte les deux absents (`clientName` et `clientPhone`
  facultatifs) ; sans téléphone, **aucune fiche client** n'est créée (un
  invité du seul planning, `clients_service.recordBooking`) ; un rendez-vous
  sans nom s'affiche « Client » partout (app, web, `anonymousClientLabel`).

## 2. Le parcours proposé (Q1 = a)

Section CLIENT, aucun client choisi :

1. « Client (nom ou téléphone)… » — **inchangé** : cherche dans la
   clientèle ; le texte tapé devient le nom d'un nouveau client. **Facultatif.**
2. « Téléphone (pour retrouver ce client) » — **toujours visible** (aujourd'hui
   il n'apparaît qu'après un nom tapé), **obligatoire** pour un nouveau
   client.
3. **« Client sans numéro »** — une case, sous le téléphone : cochée, le champ
   est désactivé, son erreur effacée, et rien n'est envoyé.

« Créer » s'active dès qu'une prestation et une date/heure sont choisies (le
client n'est plus une condition du bouton) ; à l'envoi, sans client choisi
ni « Client sans numéro », un téléphone vide ou faux est dit **sous le
champ** (« Saisissez un numéro de téléphone. », la phrase de l'app et du
web) et rien ne part. Un client **choisi** dans la liste : rien ne change.

Sans nom ni numéro, le rendez-vous s'affiche « Client » dans la Journée, la
liste, la fiche — comme ceux de l'app.

## 3. Les états et cas limites

- Cocher « Client sans numéro » après une erreur de téléphone → l'erreur part.
- Décocher → le champ revient avec ce qui y était tapé.
- Choisir un client de la liste → la case et le champ disparaissent (comme
  aujourd'hui pour le téléphone) ; « Changer » les ramène.
- Ouvert depuis une fiche client (le client déjà choisi) → inchangé.

## 4. Ce qui ne change pas

La recherche, les prestations, la date/heure, la note, le total, les refus
du serveur (créneau pris, numéro refusé), l'e-mail… et le serveur.

## 5. Les tests (rouges d'abord)

- **Pur** (`manual-booking.ts`) : la nouvelle règle d'envoi — prestations +
  date suffisent au bouton ; le client se juge à l'envoi (choisi, ou « sans
  numéro », ou un téléphone valide).
- **Composant** : réserver sans nom ni numéro (case cochée) → envoie
  `clientName` et `clientPhone` absents ; nom seul sans case → erreur sous le
  téléphone, rien n'est envoyé ; la case désactive le champ et efface son
  erreur ; un client choisi → ni case ni champ.
- **e2e** : les parcours existants qui tapent un nom seul (« Nouvelle
  Cliente », « Cliente Standalone », le toast d'axe) cochent la case ou
  saisissent un numéro ; axe + cibles (la case ≥ 48 px) + reflow.

## 6. Question au propriétaire

- **Q1 — la règle.** (a) **Comme l'app** (recommandé) : téléphone
  obligatoire pour un nouveau client, sauf « Client sans numéro » ; le nom
  facultatif — chaque client qui a un numéro a sa fiche (absences,
  historique). (b) Garder le téléphone facultatif du web et rendre seulement
  le nom facultatif : « Créer » marche sans rien, pas de case — plus court,
  mais différent de l'app et sans fiche pour qui n'a pas laissé de numéro.
- **Les mots** : aucun nouveau — « Client sans numéro » et « Saisissez un
  numéro de téléphone. » sont ceux de l'app.
