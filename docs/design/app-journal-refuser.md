# App Pro — « Refuser » dans « Ma journée » refuse la demande (au lieu de noter une absence) — spec

| | |
|---|---|
| **Statut** | **Construit le 2026-10-19** (branche `fix/app-journal-refuser`) — correctif d'un défaut ; **aucun texte nouveau**, aucun changement serveur · **Mergé (#643) le 2026-10-20** — app au prochain build |
| **Owner** | Sadreddine |
| **PRD ref / phase** | Le cycle de vie d'un rendez-vous côté salon (accepter / refuser) · V1 |
| **Module** | app Pro — `journal` (« Ma journée ») |
| **Origine** | [parity-audit-web-pro-2026-10.md](parity-audit-web-pro-2026-10.md) §5, re-vérifié dans le code |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-verification-guardrails (avant de dire « fait ») |

## 1. Le défaut — relu sur `main`

- « Ma journée » (`mobile/lib/screens/provider/journal/pro_journal_screen.dart`),
  appui long sur une demande **en attente** : la feuille d'actions propose
  « Accepter » et **« Refuser »**, et « Refuser » appelle
  **`journal.noShow(a.id)`** (`_actionSheet`, ~l. 397-401).
- `ProJournalProvider` n'a **pas** de `reject` : seulement `accept`,
  `complete`, `noShow`, `arrive`, `reschedule`.
- Le serveur accepte `pending → noShow`
  (`backend/lib/src/appointments/pro_appointment_service.dart:112-117`).
- **Effet** : une demande refusée est enregistrée comme **absence du
  client** (`noShow`) au lieu d'un refus (`reject` → `cancelled`) — son
  compteur d'absences monte (badge sur sa fiche et sur les cartes du
  journal), et il n'est **pas prévenu** : la route `reject` envoie
  « Réservation refusée » (`routes/appointments/[id]/reject.dart:28-30`), la
  route `no-show` n'envoie rien.
- Les deux autres chemins sont justes : la fiche du rendez-vous « Rejeter »
  appelle `rejectAppointment` (`pro_appointment_detail_screen.dart:285-289`) ;
  le web « Refuser » appelle `reject` (`web/components/pro/JournalPanel.tsx:206`).
- Présent depuis la création du journal (#191, 2026-07-10).

## 2. Le correctif

- `ProJournalProvider.reject(id)` → `ProServiceInterface.rejectAppointment(id,
  null)` — le service que la fiche utilise déjà ; même comportement que
  `accept` (agir puis relire la journée, erreur dans `error`).
- « Refuser » appelle `journal.reject`. Le libellé ne change pas.
- **Pas de confirmation ajoutée** : ni la fiche (« Rejeter ») ni le web
  (« Refuser ») n'en ont ; en ajouter une ici seule ferait une troisième
  forme. Question ouverte pour une tranche de cohérence (§4).

## 3. Tests (rouge d'abord)

`test/widget/pro_journal_screen_test.dart` : une demande en attente, appui
long, « Refuser » → le service reçoit `rejectAppointment('a3', null)` et
**jamais** `markNoShow`. Vu rouge sur `main`.

## 4. Hors de cette tranche

- **Les données déjà écrites** : une demande refusée depuis « Ma journée »
  entre le 2026-07-10 et ce correctif est en base comme `noShow`. Rien ne
  distingue à coup sûr ces lignes d'une vraie absence (aucun horodatage de
  transition) ; un indice : `status = 'noShow'` **sans** `arrivedAt` et
  marqué **avant** l'heure du rendez-vous. À regarder par le propriétaire —
  aucune requête n'a été lancée contre la production.
- Confirmer (ou non) un refus, de façon cohérente sur les trois surfaces.
- Le libellé : « Rejeter » (fiche de l'app) / « Refuser » (journal, web).
