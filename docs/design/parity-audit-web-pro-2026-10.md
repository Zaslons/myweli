# Audit de parité — web Pro ↔ app Pro (2026-10-19)

| | |
|---|---|
| **Statut** | **Constat** — chaque écart est une tranche à part (§6). **§2, lignes 1–3 corrigées le 2026-10-19** dans #642 ([web-pro-access.md](web-pro-access.md) §12) : pas de « semaine », l'essai démarre à la mise en ligne sur le web aussi, la FAQ ne dit plus « tout » |
| **Périmètre** | Toutes les routes de l'app Pro (`mobile/lib/core/router/pro_router.dart`, `mobile/lib/screens/provider/**`) face au web Pro (`web/app/pro/**`, `web/components/pro/**`, `web/lib/pro/**`, le BFF). **Exclus** : les sept écrans V2 de `screens/provider/features/**` (`FeatureFlags.futureProviderFeatures = false`) |
| **Base** | `feat/web-pro-access` (#642), donc avec le centre de notifications (#641) et l'accès public (#642) |
| **Méthode** | Lecture du code des deux côtés, chaque écart cité `fichier:ligne` ; puis **re-vérification à la main** des écarts qui touchent une promesse publique ou un bug (marqués ✔︎) |
| **Audit précédent** | [parity-audit-modules-2026-07.md](parity-audit-modules-2026-07.md) (clos le 2026-07-11) — aucune régression web ; deux de ses lignes étaient fausses (§5) |

## 1. Le verdict

**Aucun P0** : un salon peut faire sur le web tout l'essentiel (réservations,
journal, clients, catalogue, disponibilités, équipe, multi-salons, acompte,
avis, revenus, vérification, abonnement, notifications). **6 écarts P1** (un
salon le remarquerait), **11 P2** (finitions, cohérence). Le web a aussi des
choses que l'app n'a pas (§4).

## 2. Ce que le web promet sans le tenir — à corriger avant tout

| | Promesse | Réalité | Où |
|---|---|---|---|
| ✔︎ | `/professionnels` : « Vue journée, **semaine**, et par membre d’équipe » | Le web a Journée (par membre), Calendrier (mois), Liste — **pas de vue semaine** | `web/lib/pro/landing.ts:21` ; `web/components/pro/RendezVousClient.tsx:35-39` |
| ✔︎ | `/professionnels` étape 3 : « Mettez votre salon en ligne — vos 3 mois offerts **commencent** » ; FAQ : « Vous choisissez **ensuite** … l’offre » | Sur le web, « Mettre en ligne » reste **désactivé** tant qu'aucune offre n'est choisie (`onboarding.ts:64-71`, `GoLiveCard.tsx:33-34,93`), et le **premier choix démarre l'essai** (`salon_subscription_service.dart:155-160`) — l'horloge tourne pendant la configuration. Le **serveur**, lui, n'exige plus d'offre pour publier et démarre l'essai à la mise en ligne (`salon_provisioning_service.dart:211-238`, la voie compagnon) : **la barrière du web est restée l'ancienne** | ci-contre |
| | FAQ : « Faut-il installer une application ? Non : tout se gère depuis myweli.com » | Vrai pour la gestion courante ; faux pour les alertes quand l'onglet est fermé (push app seulement, `salon_notifier.dart:87-91`), les horaires en plusieurs plages (§3, n° 2), Apple | `web/lib/pro/landing.ts:63-64` |
| | Offre Pro : « Statistiques & **gestion** des avis » | Les avis sont en lecture seule, des deux côtés | `web/lib/pro/subscription-plans.ts:47` ; `AvisClient.tsx:20` |
| | Offre Business : « **Support prioritaire dédié** » | Le web Pro n'a **aucune** entrée d'aide (l'app : « Aide & Support ») | `subscription-plans.ts:59` ; `ProfilClient.tsx:342-357` |

## 3. Les écarts P1 (un salon le remarquerait)

1. **Accepter depuis « Journée » sans voir l'acompte.** Le panneau propose
   Accepter / Refuser mais ne montre ni le montant ni le justificatif, et
   n'a pas de lien vers la fiche du rendez-vous (`JournalPanel.tsx:180-212`) ;
   la grille n'a qu'un « ₣ » (`JournalGrid.tsx:381`). L'app ouvre la fiche
   avec le justificatif (`pro_journal_screen.dart:290`).
2. **Horaires en plusieurs plages.** L'app édite plusieurs plages par jour
   (`availability_screen.dart:1020-1024`) ; le web n'en montre et n'en édite
   qu'une, garde les autres invisibles (`lib/pro/availability.ts:32-38,107` ;
   `DayHoursEditor.tsx:55-63`). Les dates bloquées : une à la fois, passé
   accepté, sans confirmation (`DisponibilitesClient.tsx:276-295`).
3. **Pas de « Se connecter avec Apple » sur le web Pro** (`ProLoginOptions.tsx:31`)
   alors que l'app l'a (`pro_login_screen.dart:75-76`) et que le backend
   (`routes/auth/provider/apple.dart`) et le web client
   (`components/auth/AppleSignInButton.tsx`) l'ont. Un salon inscrit avec
   Apple sur iPhone ne peut pas ouvrir le web. Idem à l'inscription.
4. ✔︎ **L'essai démarre au choix d'offre sur le web**, à la mise en ligne
   dans l'app (§2, deuxième ligne).
5. **Aucune alerte pour un salon « web seulement »** — *traité le
   2026-10-20 : un e-mail quand aucun push n'arrive
   ([salon-email-alerts.md](salon-email-alerts.md)) ; et la notification du
   navigateur sur ordinateur ([web-pro-browser-push.md](web-pro-browser-push.md),
   2026-10-20 — seul un push de l'app remplace l'e-mail).* — quand l'onglet est
   fermé : le serveur ne prévient un salon que par push mobile
   (`salon_notifier.dart:87-91`) ; le web ne relit le fil que tant que
   l'onglet est visible (`ProNotificationsContext.tsx:125-127`).
6. ✔︎ **Pas de vue semaine** sur le web (§2, première ligne).

## 4. Les écarts P2, et ce que le web a en plus

**P2** : le tableau de bord n'a la liste de mise en ligne qu'en brouillon,
6 étapes contre 8 dans l'app, sans barre de progression
(`onboarding.ts:33-72`, `GoLiveCard.tsx:12-13` dit « mirrors the app » —
faux) · réservation manuelle : le web exige un nom, pas de « Client sans
numéro » (`manual-booking.ts:41-52`, même commentaire faux) · fiche
rendez-vous : justificatif à cliquer, sans consigne, échec silencieux
(`ProAppointmentDetailClient.tsx:319-343`) ; « Absent » proposé sur un
rendez-vous futur (`lifecycle.ts:22-31`), et sans confirmation dans le panneau
(`JournalPanel.tsx:230-236`) — l'app ne l'offre qu'une fois le rendez-vous
commencé, avec confirmation · acompte : règles différentes (web 1–100 % /
0–720 h, app 5–80 % / 12-24-48 h), sans l'exemple ni « MyWeli ne le traite
pas » (`deposit.ts:57-75`, `AcompteClient.tsx:206-273`) · Profil : liens
Acompte / Abonnement / Vérification montrés à un Manager qui n'y a pas droit
(`ProfilClient.tsx:342-357`) ; aucune aide/support · Médias : changements
perdus sans avertissement, suppression sans confirmation
(`MediasClient.tsx:125,185-190,214-216`) · Avis : moyenne calculée sur la page
chargée, total serveur (`AvisClient.tsx:88,110`) · inscription : adresse
obligatoire dans l'app, facultative sur le web.

**Le web en plus** (voulu ou bienvenu) : le choix d'offre (voie compagnon) ;
glisser-déposer pour reprogrammer, y compris vers un autre artiste ;
« Reprogrammer » sur la fiche ; l'interrupteur « Service actif » ; la
recherche client dans la réservation manuelle ; des avis plus riches ;
l'accueil avec la liste du jour ; les raccourcis clavier.

## 5. Côté app — relevé en passant

- ✔︎ **Bug P1 dans l'app** : dans « Ma journée », l'appui long sur une
  demande en attente propose « Refuser »… qui appelle `noShow`
  (`pro_journal_screen.dart:397-401`) ; le serveur accepte
  `pending → noShow` (`pro_appointment_service.dart:112-117`). Une demande
  refusée est enregistrée comme **une absence du client** (le compteur
  d'absences de sa fiche monte) au lieu d'être refusée. `ProJournalProvider`
  n'a même pas de `reject`. Le web appelle bien `reject`
  (`JournalPanel.tsx:206`).
- L'audit de juillet se trompait sur deux lignes : 3.3 (« interrupteur actif
  des deux côtés » — l'app n'a jamais eu d'interface pour) et 3.9 (« plages
  multiples des deux côtés » — le web les préserve sans les montrer).
- Ajouté à l'app depuis juillet, absent ou partiel sur le web : les alertes
  push (#239), Apple activé par défaut, le blocage de dates en lot (A14e,
  #296), la voie compagnon (#551 — d'où l'écart d'essai).

## 6. L'ordre proposé (une chose à la fois)

1. **Corriger les promesses du §2** dans #642 (texte à valider) — et décider
   de l'essai : aligner le web sur le serveur (mise en ligne sans offre,
   l'essai démarre à la publication) ou changer le texte.
2. **Le bug « Refuser » de l'app** (petit, et il pénalise des clients à tort).
3. **Le panneau « Journée » : acompte, justificatif, lien vers la fiche**.
4. **Horaires en plusieurs plages + dates bloquées en lot** sur le web.
5. **Apple sur le web Pro**.
6. **Alertes d'un salon web** (e-mail ? push web ?) — une décision produit.
7. **Vue semaine**.
8. Les P2, par lots.
