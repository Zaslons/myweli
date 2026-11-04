# Le cron d'entretien quotidien — `/internal/cron/maintenance` — spec

| | |
|---|---|
| **Statut** | **Déployé le 2026-10-21** (#667, `46126a3`, révision `myweli-api-00044-z42`) ; le job `myweli-maintenance` créé et forcé : 200 (§11). Construit le même jour ; ce qui a été vu : §10. Validé le même jour — Q1 : **03:30 UTC** ; Q2 : **un script pour les trois jobs** ; Q3 : **déployer, puis créer le job et le forcer le même jour** ; Q4 : **les deux crons dans le contrat** (§9) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-10-21 |
| **PRD ref / phase** | Exploitation (V1) — aucune fonctionnalité visible |
| **Module** | backend (une route, un service), infra (un job Cloud Scheduler), docs |
| **Origine** | [write-idempotency.md](write-idempotency.md) §10 « Ce qui reste » ; le commentaire de `routes/internal/cron/subscriptions.dart` (« A FOURTH rider is when to extract, and it should take all three ») |
| **Skills checked** | myweli-backend-guardrails ✓ · myweli-dev-guardrails ✓ |
| **Dépend de** | #666 (la purge des clés d'idempotence n'existe que là) |

## 1. Le constat — relu sur le vrai chemin

`POST /internal/cron/subscriptions` (job `myweli-subscriptions`, tous les jours
à 03:00 UTC) fait **cinq** choses, dans cet ordre :

| # | Tâche | Depuis | Ce qu'elle rend |
|---|---|---|---|
| 1 | le tour des offres (`SubscriptionScheduler.tick`) — sa raison d'être | R2a | `notices`, `unpublished` |
| 2 | la purge du verrou de connexion admin (`pruneAdminLoginThrottle`, 24 h) | 0035 | `throttleRowsPruned` |
| 3 | la purge des fenêtres de limite (`pruneRateLimitWindows`, `kRateLimitRetention`) | 0034 / front door | `rateLimitWindowsPruned` |
| 4 | la remise à zéro du salon de démonstration (`DemoResetService.tickIfDue`, tous les 7 jours) | T69 | `demoReset` |
| 5 | la purge des clés d'idempotence (`pruneIdempotencyKeys`, 24 h) | #666 | `idempotencyKeysPruned` |

Le commentaire du fichier fixait la règle : les tâches d'entretien montent sur
ce cron tant qu'elles sont trois ; **la quatrième impose d'extraire
`/internal/cron/maintenance`, et l'extraction les prend toutes.** #666 a ajouté
la quatrième (la 5 du tableau) en le disant.

Ce que coûte le mélange, au-delà de la règle :
- **Une panne de l'un arrête les autres.** Si le tour des offres lève une
  exception, la route répond 500 : ni purge, ni remise à zéro de la démo ce
  jour-là — et l'alerte « A cron call was REFUSED » parle d'abonnements.
- **Le nom ment** : « subscriptions » purge des tables de sécurité.

Ce qui existe déjà et ne change pas :
- **L'authentification** : `CronAuth`, le jeton OIDC signé par Google, rien
  d'autre ; 404 quand la paire `CRON_OIDC_AUDIENCE` / `CRON_SERVICE_ACCOUNT`
  n'est pas configurée, 403 sinon (BACKEND.md §7 T21).
- **L'alerte** (`infra/gcp/86-cron-auth-alert.sh`) : toute réponse non 2xx sur
  `/internal/cron/*` — elle couvre la nouvelle route **sans changement**. Son
  angle mort, écrit dans le script, reste : un job qui ne tourne plus du tout
  n'alerte pas.
- **Les jobs de production** (lus le 2026-10-21, sans rien changer) :
  `myweli-reminders` (`*/15 * * * *`) et `myweli-subscriptions` (`0 3 * * *`),
  UTC, `https://api.myweli.com/internal/cron/…`, jeton OIDC de
  `myweli-scheduler@myweli.iam.gserviceaccount.com`, audience
  `https://api.myweli.com`, délai de 180 s, aucune nouvelle tentative. **Créés à
  la main** : `infra-gcp-migration.md` §5 note que les déclarer dans le dépôt est
  dû.

## 2. Ce qui change

### 2.1 Le serveur

- **`POST /internal/cron/maintenance`** : la même porte que les deux autres
  (`CronAuth` ; 404 / 403 ; 405 pour un autre verbe). Il exécute, dans l'ordre
  d'aujourd'hui, les tâches 2 à 5 et répond leurs comptes :
  `{ throttleRowsPruned, rateLimitWindowsPruned, idempotencyKeysPruned, demoReset }`.
  Une purge qui échoue reste un `null` dans la réponse et une ligne
  `*_prune_failed` (comme aujourd'hui) ; la remise à zéro qui lève une exception
  reste un 500 (comme aujourd'hui), et l'alerte le voit.
- **Le travail dans un service, la route mince** : `MaintenanceTick`
  (`lib/src/maintenance/maintenance_tick.dart`) reçoit les quatre tâches et
  rend les quatre comptes ; la route authentifie et délègue. C'est ce qui
  permet de **tester le comportement** (les comptes, le `null`, l'ordre) — les
  crons n'ont aujourd'hui que des épingles de source.
- **`POST /internal/cron/subscriptions`** ne fait plus que le tour des offres :
  `{ notices, unpublished }`.
- **Les épingles existantes** (`admin_test.dart`, `origin_front_door_wiring_test.dart`,
  `rate_limiter_test.dart`, `idempotency_wiring_test.dart`) suivent leurs tâches
  vers la nouvelle route ; `cron_auth_test.dart` lit **tous** les fichiers de
  `routes/internal/cron/` au lieu d'une liste écrite à la main (la leçon de
  `no_secret_in_url_test.dart`).

### 2.2 L'infrastructure

- **Un job `myweli-maintenance`** : `POST https://api.myweli.com/internal/cron/maintenance`,
  le même compte de service, la même audience, le même délai (180 s), aucune
  nouvelle tentative — à l'heure de Q1.
- **Déclaré dans le dépôt** (Q2) : `infra/gcp/99-scheduler-jobs.sh`, qui crée
  ce qui manque et ne touche pas à ce qui existe, pour les **trois** jobs —
  ce qui ferme la dette de `infra-gcp-migration.md` §5.
- **Staging** (retiré, `staging.state` = `absent`) : `90-staging.sh` crée aussi
  `myweli-maintenance-staging`, en pause comme les autres, pour le chemin du
  retour.

### 2.3 Le contrat et les docs

- `openapi.yaml` : `/internal/cron/maintenance` **et** `/internal/cron/subscriptions`
  (qui n'y a jamais été) — Q4.
- BACKEND.md §7 : la ligne T21 nomme les trois routes (même porte, même risque).
- DEPLOYMENT.md §6, `infra-gcp-migration.md` §5 : trois jobs.

## 3. La bascule (Q3)

1. Fusionner (après #666) et **déployer le backend** — la nouvelle route existe,
   l'ancienne ne purge plus.
2. **Créer le job** (`99-scheduler-jobs.sh`) — une mutation du cloud : je la
   prépare, tu dis oui.
3. **Le forcer une fois** (`gcloud scheduler jobs run myweli-maintenance`) et
   lire dans le journal du service le **200** et l'absence de toute ligne
   `*_prune_failed`. Les quatre comptes sont dans la **réponse**, que Cloud
   Scheduler ne garde pas : le journal ne montre que le statut (§11).

Entre 1 et 2, au plus une journée sans purge : sans effet (des tables de
quelques lignes, une démo remise à zéro tous les 7 jours et seulement si elle
est due, un verrou admin qui décroît un jour plus tard). Lancer les deux crons
le même jour est sans risque aussi : chaque tâche est idempotente.

## 4. Les états

| Situation | Réponse | Ce qui se voit |
|---|---|---|
| Tout va bien | 200, les quatre comptes | rien |
| Une purge échoue | 200, ce compte à `null` | une ligne `*_prune_failed` |
| La remise à zéro de la démo lève | 500 | l'alerte « A cron call was REFUSED » |
| Le tour des offres lève | 500 sur `/subscriptions` seulement | l'alerte — et l'entretien a tourné quand même |
| Pas de jeton / mauvais jeton | 403 | l'alerte |
| Paire OIDC non configurée | 404 | l'alerte |

## 5. Sécurité

Aucune nouvelle frontière : la même porte que les deux autres crons, joignable
seulement avec un jeton OIDC de `myweli-scheduler@` pour l'audience
`https://api.myweli.com`. Un appel forgé ne peut que déclencher plus tôt des
purges idempotentes et une remise à zéro gardée par son échéance.

## 6. Les tests (rouges d'abord)

- `MaintenanceTick` : les quatre tâches tournent, dans l'ordre, chacune une fois ;
  leurs comptes ressortent tels quels ; un `null` reste un `null` ; la
  remise à zéro qui lève fait lever le tick.
- La route : 405 pour un autre verbe ; elle lit `MaintenanceTick` et rend ses
  quatre clés ; `/subscriptions` ne nomme plus aucune des quatre.
- Les épingles déplacées, et `cron_auth_test` sur tout le dossier.
- `99-scheduler-jobs.sh` : `bash -n`, et un test qui vérifie que chaque route
  de `routes/internal/cron/` a son job dans le script (une route sans job est
  le défaut de Render).
- **Mutations** : une tâche oubliée par le tick, une tâche restée sur
  `/subscriptions`, un compte manquant dans la réponse, une route sans job.

## 7. Hors de cette tranche

- L'angle mort de l'alerte (un job qui ne tourne plus) : il demande un compteur,
  un seuil et une fenêtre (le script dit pourquoi) — une tranche à part.

## 8. Les mots

Aucun : rien de visible par une personne.

## 9. Questions au propriétaire

- **Q1 — l'heure** : **03:30 UTC chaque jour** (recommandé — une demi-heure
  après le tour des offres, pour ne jamais partager la petite base au même
  instant), ou 03:00 comme aujourd'hui ?
- **Q2 — déclarer les jobs** : **un script `infra/gcp/99-scheduler-jobs.sh`
  pour les trois jobs** (recommandé — ferme la dette « créés à la main »), ou
  seulement le nouveau, à la main comme les autres ?
- **Q3 — la bascule** : **déployer, puis créer le job et le forcer le même
  jour** (recommandé — une journée sans purge est sans effet), ou garder les
  tâches sur les deux crons le temps d'un déploiement (deux PR) ?
- **Q4 — le contrat** : **documenter les deux crons internes** dans
  `openapi.yaml` (recommandé — `/subscriptions` n'y a jamais été), ou seulement
  le nouveau ?

**Décisions (2026-10-21).** Q1, Q2, Q3 et Q4 : les recommandations. La
création du job (§3, étape 2) reste une mutation du cloud : elle est demandée
au moment de la faire.

## 10. Construit — ce qui a été vu

**Comme écrit.** `MaintenanceTick` (`lib/src/maintenance/maintenance_tick.dart`),
la route `routes/internal/cron/maintenance.dart`, le cron des abonnements
ramené à `{ notices, unpublished }`, `infra/gcp/99-scheduler-jobs.sh`, le job
de staging, les deux crons dans `openapi.yaml`, T21, DEPLOYMENT.md §6,
`infra-gcp-migration.md` §5.

**Vérifié contre la production, sans rien y changer** : le script, lancé sans
`APPLY`, relit les deux jobs faits à la main et les trouve **identiques** à ce
qu'il déclare (horaire, UTC, adresse, POST, audience, compte de service,
180 s) ; `myweli-maintenance` y est « MISSING — would create ». La forme
déclarée est donc celle qui tourne, pas une supposition.

**Trouvé en construisant** :
- `cron_auth_test` listait les routes à la main (deux) : il lit maintenant le
  dossier, et en exige trois.
- Plusieurs commentaires et deux specs (`backend-admin-login-throttle.md`,
  `infra-cloudflare-front-door.md`) disaient que les purges montaient sur le
  cron des abonnements : ils pointent vers le nouveau.

**Mutations vues rouges (15)** : une tâche oubliée, l'ordre changé, un `null`
deviné en 0, l'échec de la remise à zéro avalé, un compte manquant, la remise
à zéro jugée à un autre instant, une mauvaise fenêtre pour le verrou admin, la
purge des clés non branchée, la route qui ne lit pas le tick, le tick non
fourni, une tâche restée sur `/subscriptions`, le job non déclaré, la mauvaise
heure, le job de staging oublié, la route absente du contrat.

**La bascule (§3)** : faite le même jour — §11.

## 11. En production — 2026-10-21

Dans l'ordre de §3, chaque étape sur l'accord du propriétaire :

1. **#666 fusionné** (`deadda7`) puis **déployé** : révision
   `myweli-api-00043-gqr` (migration `0040`). **#667 rebasé** sur main (ses
   cinq commits inchangés), **fusionné** (`46126a3`, arbre identique à la tête
   de la PR) puis **déployé** : révision `myweli-api-00044-z42`, 100 % du
   trafic, l'empreinte de l'image égale à celle du tag `46126a3` ; `/health` et
   `/providers` à 200.
2. **`APPLY=1 bash infra/gcp/99-scheduler-jobs.sh`** : `myweli-maintenance`
   créé ; relu ensuite, les **trois** jobs correspondent à ce que le script
   déclare. Premier passage prévu : 2026-10-22 03:30 UTC.
3. **Forcé à 12:06:58 UTC** : **200** en 112 ms sur `myweli-api-00044-z42`,
   appelé par `Google-Cloud-Scheduler` ; aucune ligne `*_prune_failed` ni
   d'erreur ensuite. C'est aussi la preuve que la table `idempotency_keys`
   (0040) existe : sans elle, la purge des clés aurait écrit
   `idempotency_prune_failed`.
4. **Le cron des abonnements forcé à 12:15:19 UTC** (aucun vrai salon encore —
   accord du propriétaire) : **200** en 16 ms, sans erreur — le tour des offres
   seul.

**Ce qui a été vu en le faisant** :
- **Les comptes ne sont pas dans le journal.** La réponse les porte, mais Cloud
  Scheduler ne garde pas les corps et la route n'écrit rien quand tout va
  bien : le journal dit le statut, et une purge en échec écrit sa ligne. §3
  disait à tort de « lire les quatre comptes » — corrigé.
- **Une sonde anonyme déclenche l'alerte.** Pour vérifier que la route
  existait, un `POST` sans jeton (12:06:20 UTC) a reçu le **403** attendu — et
  l'alerte « A cron call was REFUSED » a envoyé son e-mail, comme elle le doit
  pour tout non-2xx sur `/internal/cron/*`. Pour vérifier une route de cron,
  forcer son job plutôt que la sonder.

